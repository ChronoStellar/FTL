//
//  GmailService.swift
//  google-api-test
//
//  Read-only Gmail access: the signed-in user's profile and recent message
//  headers. Uses the Gmail REST API v1.
//

import Foundation

struct GmailService {
    private let client: GoogleAPIClient
    private let base = URL(string: "https://gmail.googleapis.com/gmail/v1/")!

    init(auth: GoogleAuthManager) {
        self.client = GoogleAPIClient(auth: auth)
    }

    /// The signed-in user's Gmail profile (address + total message count).
    func profile() async throws -> Profile {
        try await client.send(base.appending(path: "users/me/profile"))
    }

    /// Fetches Subject/From/Date headers + snippet for messages matching `query`.
    /// Defaults to `in:inbox`. Accepts any Gmail search syntax, e.g. "from:boss@example.com" or "subject:invoice".
    func recentMessages(maxResults: Int = 10, query: String = "in:inbox") async throws -> [Message] {
        var listURL = base.appending(path: "users/me/messages")
        listURL.append(queryItems: [
            .init(name: "maxResults", value: String(maxResults)),
            .init(name: "q", value: query.isEmpty ? "in:inbox" : query),
        ])
        let list: MessageList = try await client.send(listURL)

        // The list endpoint returns only IDs; fetch metadata for each one.
        var messages: [Message] = []
        for ref in list.messages ?? [] {
            var msgURL = base.appending(path: "users/me/messages/\(ref.id)")
            msgURL.append(queryItems: [
                .init(name: "format", value: "metadata"),
                .init(name: "metadataHeaders", value: "Subject"),
                .init(name: "metadataHeaders", value: "From"),
                .init(name: "metadataHeaders", value: "Date"),
            ])
            let message: Message = try await client.send(msgURL)
            messages.append(message)
        }
        return messages
    }

    // MARK: - Models

    struct Profile: Decodable, Identifiable {
        let emailAddress: String
        let messagesTotal: Int
        let threadsTotal: Int
        var id: String { emailAddress }
    }

    struct MessageList: Decodable {
        let messages: [MessageRef]?
    }

    struct MessageRef: Decodable {
        let id: String
    }

    struct Message: Decodable, Identifiable {
        let id: String
        let snippet: String?
        let payload: Payload?

        var subject: String { header("Subject") ?? "(no subject)" }
        var from: String    { header("From")    ?? "(unknown sender)" }

        /// Parses the first "Rp." amount found in the snippet, then falls back to the subject.
        /// Matches patterns like "Rp. 50.000", "Rp.50,000", "Rp. 1.500.000", etc.
        var spending: String? {
            let sources = [snippet ?? "", subject]
            let pattern = #"Rp\.?\s*[\d.,]+"#
            for source in sources {
                if let range = source.range(of: pattern, options: .regularExpression) {
                    return String(source[range])
                }
            }
            return nil
        }

        /// The email's Date header formatted as a short locale date string.
        var emailDate: String? {
            guard let raw = header("Date") else { return nil }
            // RFC 2822 date, e.g. "Tue, 02 Sep 2026 08:23:11 +0700"
            let formatters: [DateFormatter] = [
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
                    return f
                }(),
                {
                    let f = DateFormatter()
                    f.locale = Locale(identifier: "en_US_POSIX")
                    f.dateFormat = "dd MMM yyyy HH:mm:ss Z"
                    return f
                }(),
            ]
            for formatter in formatters {
                if let date = formatter.date(from: raw) {
                    let display = DateFormatter()
                    display.dateStyle = .medium
                    display.timeStyle = .none
                    return display.string(from: date)
                }
            }
            return raw // fall back to raw string if parsing fails
        }

        private func header(_ name: String) -> String? {
            payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        struct Payload: Decodable {
            let headers: [Header]?
        }
        struct Header: Decodable {
            let name: String
            let value: String
        }
    }
}
