//
//  GmailExporter.swift
//  FTL — services/GoogleAPI
//
//  Pulls the latest N (default 1,000) emails via the Gmail REST API v1,
//  extracts metadata and body text (plain & html, skipping binary/pdf/images),
//  and exports the dataset to formatted JSON and RFC 4180 CSV files.
//

import Foundation

/// Represents a single exported email with metadata and parsed body text.
struct ExportedEmail: Codable, Identifiable, Sendable {
    let id: String
    let threadId: String
    let labelIds: [String]
    let snippet: String
    let internalDate: String
    let date: String
    let from: String
    let to: String
    let cc: String?
    let subject: String
    let bodyPlain: String?
    let bodyHtml: String?
}

/// Progress state during batch export.
enum ExportProgress: Equatable, Sendable {
    case idle
    case fetchingIDs(fetched: Int, target: Int)
    case downloading(completed: Int, total: Int)
    case serializing
    case completed(count: Int, jsonURL: URL, csvURL: URL)
    case failed(String)

    var message: String {
        switch self {
        case .idle:
            return "Ready to export"
        case let .fetchingIDs(fetched, target):
            return "Fetching email list: \(fetched)/\(target)..."
        case let .downloading(completed, total):
            return "Downloading messages: \(completed)/\(total)..."
        case .serializing:
            return "Generating JSON and CSV files..."
        case let .completed(count, _, _):
            return "Exported \(count) emails successfully!"
        case let .failed(error):
            return "Export failed: \(error)"
        }
    }
}

actor GmailExporter: CapturedEmailSource {
    private let client: GoogleAPIClient
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/")!

    init(auth: GoogleAuthManager) {
        self.client = GoogleAPIClient(auth: auth)
    }

    /// Fetches messages matching `query` as `CapturedEmail` — the same shape the
    /// fixture corpus decodes into, so a parser cannot tell a live email from a
    /// recorded one.
    ///
    /// Shares this actor's ID paging and MIME/base64 extraction rather than
    /// GmailRail growing its own: two decoders for one wire format is how they
    /// drift, and the export is the thing the parsers were measured against.
    /// `CapturedEmailSource`. Forwards to the real fetch with the default
    /// concurrency — the protocol deliberately does not expose it, because how
    /// many sockets the network path opens is not something a recorded source
    /// has an opinion about.
    func fetchCaptured(query: String, limit: Int) async throws -> [CapturedEmail] {
        try await fetchCaptured(query: query, limit: limit, concurrency: 6)
    }

    func fetchCaptured(query: String, limit: Int, concurrency: Int = 6) async throws -> [CapturedEmail] {
        let ids = try await fetchMessageIDs(targetCount: limit, query: query, progress: { _ in })
        guard !ids.isEmpty else { return [] }
        let exported = await downloadMessages(ids: ids, concurrency: concurrency, progress: { _ in })
        return exported.map(CapturedEmail.init(exported:))
    }

    /// Fetches up to `targetCount` messages matching `query`, then writes `.json` and `.csv` files.
    ///
    /// - Parameters:
    ///   - targetCount: Number of emails to export (e.g. 1000).
    ///   - query: Gmail search query (default: "" for all inbox/all mail).
    ///   - concurrency: Simultaneous message detail download requests (default: 12).
    ///   - progress: Callback for UI updates.
    /// - Returns: URLs for the generated JSON and CSV files.
    func exportLatestEmails(
        targetCount: Int = 1000,
        query: String = "",
        concurrency: Int = 12,
        progress: @Sendable @escaping (ExportProgress) -> Void
    ) async throws -> (jsonURL: URL, csvURL: URL) {
        progress(.fetchingIDs(fetched: 0, target: targetCount))

        // Step 1: Paginate to collect message IDs
        let messageIds = try await fetchMessageIDs(targetCount: targetCount, query: query, progress: progress)

        guard !messageIds.isEmpty else {
            let errorMsg = "No messages found matching query."
            progress(.failed(errorMsg))
            throw NSError(domain: "GmailExporter", code: 404, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        progress(.downloading(completed: 0, total: messageIds.count))

        // Step 2: Concurrently download details for each message
        let emails = await downloadMessages(ids: messageIds, concurrency: concurrency, progress: progress)

        progress(.serializing)

        // Step 3: Serialize to JSON and CSV
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileManager = FileManager.default
        let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        let jsonURL = docDir.appendingPathComponent("gmail_export_\(timestamp).json")
        let csvURL = docDir.appendingPathComponent("gmail_export_\(timestamp).csv")

        // JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(emails)
        try jsonData.write(to: jsonURL, options: .atomic)

        // CSV
        let csvString = generateCSV(from: emails)
        // Prepend UTF-8 BOM so spreadsheet apps (Excel, Numbers) open characters correctly
        let bomCsv = "\u{FEFF}" + csvString
        guard let csvData = bomCsv.data(using: .utf8) else {
            throw NSError(domain: "GmailExporter", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to encode CSV to UTF-8."])
        }
        try csvData.write(to: csvURL, options: .atomic)

        progress(.completed(count: emails.count, jsonURL: jsonURL, csvURL: csvURL))
        return (jsonURL, csvURL)
    }

    // MARK: - Step 1: Fetching Message IDs

    private func fetchMessageIDs(
        targetCount: Int,
        query: String,
        progress: @Sendable (ExportProgress) -> Void
    ) async throws -> [String] {
        var collectedIDs: [String] = []
        var nextPageToken: String? = nil

        while collectedIDs.count < targetCount {
            let pageSize = min(500, targetCount - collectedIDs.count)
            var listURL = base.appending(path: "users/me/messages")
            var queryItems: [URLQueryItem] = [
                .init(name: "maxResults", value: String(pageSize)),
            ]
            if !query.isEmpty {
                queryItems.append(.init(name: "q", value: query))
            }
            if let nextPageToken {
                queryItems.append(.init(name: "pageToken", value: nextPageToken))
            }
            listURL.append(queryItems: queryItems)

            let response: APIListResponse = try await client.send(listURL)

            guard let messages = response.messages, !messages.isEmpty else {
                break
            }

            let newIDs = messages.map(\.id)
            collectedIDs.append(contentsOf: newIDs)
            progress(.fetchingIDs(fetched: collectedIDs.count, target: targetCount))

            if let token = response.nextPageToken, !token.isEmpty {
                nextPageToken = token
            } else {
                break // No more pages
            }
        }

        return Array(collectedIDs.prefix(targetCount))
    }

    // MARK: - Step 2: Concurrent Download

    private func downloadMessages(
        ids: [String],
        concurrency: Int,
        progress: @Sendable @escaping (ExportProgress) -> Void
    ) async -> [ExportedEmail] {
        let total = ids.count
        let workerCount = max(1, min(concurrency, total))

        return await withTaskGroup(of: ExportedEmail?.self) { group in
            var results: [ExportedEmail] = []
            results.reserveCapacity(total)

            var currentIndex = 0

            // Seed initial pool of concurrent tasks
            while currentIndex < workerCount {
                let id = ids[currentIndex]
                group.addTask { [self] in
                    await self.fetchSingleEmail(id: id)
                }
                currentIndex += 1
            }

            // As tasks complete, collect and schedule next
            for await email in group {
                if let email {
                    results.append(email)
                }
                let completedCount = results.count
                progress(.downloading(completed: completedCount, total: total))

                if currentIndex < total {
                    let nextID = ids[currentIndex]
                    group.addTask { [self] in
                        await self.fetchSingleEmail(id: nextID)
                    }
                    currentIndex += 1
                }
            }

            return results
        }
    }

    private func fetchSingleEmail(id: String) async -> ExportedEmail? {
        var msgURL = base.appending(path: "users/me/messages/\(id)")
        msgURL.append(queryItems: [
            .init(name: "format", value: "full")
        ])

        do {
            let raw: APIMessageDetail = try await client.send(msgURL)
            return parseMessage(raw)
        } catch {
            return nil
        }
    }

    // MARK: - Step 3: Parsing & MIME Extraction

    private func parseMessage(_ raw: APIMessageDetail) -> ExportedEmail {
        let headers = raw.payload?.headers ?? []
        func headerVal(_ name: String) -> String? {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        let subject = headerVal("Subject") ?? "(No Subject)"
        let from = headerVal("From") ?? "(Unknown Sender)"
        let to = headerVal("To") ?? ""
        let cc = headerVal("Cc")
        let date = headerVal("Date") ?? ""

        var bodyPlain: String?
        var bodyHtml: String?

        if let payload = raw.payload {
            let extracted = extractBodies(from: payload)
            bodyPlain = extracted.plain
            bodyHtml = extracted.html
        }

        return ExportedEmail(
            id: raw.id,
            threadId: raw.threadId,
            labelIds: raw.labelIds ?? [],
            snippet: raw.snippet ?? "",
            internalDate: raw.internalDate ?? "",
            date: date,
            from: from,
            to: to,
            cc: cc,
            subject: subject,
            bodyPlain: bodyPlain,
            bodyHtml: bodyHtml
        )
    }

    private func extractBodies(from payload: APIMessagePayload) -> (plain: String?, html: String?) {
        var plain: String?
        var html: String?

        func traverse(part: APIMessagePart) {
            let mime = (part.mimeType ?? "").lowercased()

            // Skip binary attachments, pdfs, images, audio, video
            if mime.hasPrefix("image/") || mime == "application/pdf" || mime.hasPrefix("video/") || mime.hasPrefix("audio/") || mime == "application/octet-stream" {
                return
            }

            if let dataString = part.body?.data, !dataString.isEmpty {
                if let decoded = decodeBase64URL(dataString) {
                    if mime == "text/plain", plain == nil {
                        plain = decoded
                    } else if mime == "text/html", html == nil {
                        html = decoded
                    }
                }
            }

            if let subparts = part.parts {
                for sub in subparts {
                    traverse(part: sub)
                }
            }
        }

        // Check root payload body
        if let rootData = payload.body?.data, !rootData.isEmpty {
            let mime = (payload.mimeType ?? "").lowercased()
            if let decoded = decodeBase64URL(rootData) {
                if mime == "text/plain" {
                    plain = decoded
                } else if mime == "text/html" {
                    html = decoded
                }
            }
        }

        // Traverse nested MIME parts
        if let parts = payload.parts {
            for part in parts {
                traverse(part: part)
            }
        }

        return (plain, html)
    }

    private func decodeBase64URL(_ base64Url: String) -> String? {
        var base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
            ?? String(data: data, encoding: .isoLatin1)
    }

    // MARK: - Step 4: CSV Serialization (RFC 4180)

    private func generateCSV(from emails: [ExportedEmail]) -> String {
        var lines: [String] = []
        let headers = [
            "id",
            "threadId",
            "internalDate",
            "date",
            "from",
            "to",
            "cc",
            "subject",
            "snippet",
            "labels",
            "bodyPlain"
        ]
        lines.append(headers.map { escapeCSV($0) }.joined(separator: ","))

        for email in emails {
            let row: [String] = [
                email.id,
                email.threadId,
                email.internalDate,
                email.date,
                email.from,
                email.to,
                email.cc ?? "",
                email.subject,
                email.snippet,
                email.labelIds.joined(separator: ";"),
                email.bodyPlain ?? ""
            ]
            lines.append(row.map { escapeCSV($0) }.joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }

    private func escapeCSV(_ text: String) -> String {
        if text.contains("\"") || text.contains(",") || text.contains("\n") || text.contains("\r") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return "\"\(text)\""
    }

    // MARK: - Internal DTOs

    private struct APIListResponse: Decodable {
        let messages: [MessageRef]?
        let nextPageToken: String?
        struct MessageRef: Decodable {
            let id: String
        }
    }

    private struct APIMessageDetail: Decodable {
        let id: String
        let threadId: String
        let labelIds: [String]?
        let snippet: String?
        let internalDate: String?
        let payload: APIMessagePayload?
    }

    private struct APIMessagePayload: Decodable {
        let mimeType: String?
        let headers: [APIHeader]?
        let body: APIMessageBody?
        let parts: [APIMessagePart]?
    }

    private struct APIMessagePart: Decodable {
        let mimeType: String?
        let body: APIMessageBody?
        let parts: [APIMessagePart]?
    }

    private struct APIMessageBody: Decodable {
        let size: Int?
        let data: String?
    }

    private struct APIHeader: Decodable {
        let name: String
        let value: String
    }
}
