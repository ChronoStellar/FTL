//
//  SheetsService.swift
//  google-api-test
//
//  Expense tracker backed by one spreadsheet with one tab per month
//  (e.g. "September 2026"), each tab having columns:
//  Date | Category | Description | Amount.
//

import Foundation

struct SheetsService {
    // Default spreadsheet ID
    static let defaultSpreadsheetID = "1wdjmVUJln-Iwjw-fyS43kmC0WleXhRzyNbVJcqrh8Hc"

    /// The active spreadsheet ID, persisted in UserDefaults.
    static var activeSpreadsheetID: String {
        get {
            let custom = UserDefaults.standard.string(forKey: "ftl_custom_spreadsheet_id")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let custom, !custom.isEmpty { return custom }
            return defaultSpreadsheetID
        }
        set {
            let clean = extractSpreadsheetID(from: newValue)
            UserDefaults.standard.set(clean, forKey: "ftl_custom_spreadsheet_id")
        }
    }

    /// Helper to extract clean spreadsheet ID from a raw ID or full Google Sheets URL.
    static func extractSpreadsheetID(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.range(of: #"/spreadsheets/d/([a-zA-Z0-9-_]+)"#, options: .regularExpression) {
            let sub = trimmed[match]
            let parts = sub.split(separator: "/")
            if parts.count >= 3 {
                return String(parts[2])
            }
        }
        return trimmed
    }

    /// Legacy accessor for backwards compatibility.
    static var spreadsheetID: String {
        activeSpreadsheetID
    }

    /// Column headers written when a new month tab is created.
    static let headers = ["Date", "Category", "Description", "Amount"]

    private let auth: GoogleAuthManager
    private let client: GoogleAPIClient
    private let spreadsheetID: String
    private let base = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/")!

    init(auth: GoogleAuthManager, spreadsheetID: String? = nil) {
        self.auth = auth
        self.client = GoogleAPIClient(auth: auth)
        self.spreadsheetID = spreadsheetID ?? Self.activeSpreadsheetID
    }

    // MARK: - Expense API

    struct Expense {
        var date: Date = .now
        var category: String
        var description: String
        var amount: Double
    }

    /// Appends an expense to the tab for its month, creating that tab if needed.
    func addExpense(_ expense: Expense) async throws {
        let tab = try await ensureMonthTab(for: expense.date)
        let row = [
            Self.dateFormatter.string(from: expense.date),
            expense.category,
            expense.description,
            Self.amountString(expense.amount),
        ]
        try await append(range: Self.a1(tab: tab, "A:D"), values: [row])
    }

    /// Reads all data rows (excluding the header) for a given month.
    /// Returns an empty array if that month's tab doesn't exist yet.
    func readMonth(for date: Date = .now) async throws -> [[String]] {
        let tab = Self.monthTabName(for: date)
        guard try await tabTitles().contains(tab) else { return [] }
        let rows = try await read(range: Self.a1(tab: tab, "A:D"))
        return Array(rows.dropFirst()) // drop the header row
    }

    /// Deletes a specific row by 0-based data index (excluding header) from the month's tab.
    func deleteMonthRow(at rowIndex: Int, for date: Date = .now) async throws {
        let tab = Self.monthTabName(for: date)
        guard try await tabTitles().contains(tab) else { return }
        var allRows = try await read(range: Self.a1(tab: tab, "A:D"))
        let targetIndex = rowIndex + 1 // skip header
        guard targetIndex < allRows.count else { return }
        allRows.remove(at: targetIndex)

        try await clear(range: Self.a1(tab: tab, "A:D"))
        if !allRows.isEmpty {
            try await write(range: Self.a1(tab: tab, "A1"), values: allRows, inputOption: "RAW")
        }
    }

    /// The tab name for a date, e.g. "September 2026".
    nonisolated static func monthTabName(for date: Date = .now) -> String {
        monthFormatter.string(from: date)
    }

    /// Ensures the month's tab exists (creating it with headers) and returns its name.
    func ensureMonthTab(for date: Date = .now) async throws -> String {
        let title = Self.monthTabName(for: date)
        if try await tabTitles().contains(title) == false {
            try await createTab(title: title)
            try await write(range: Self.a1(tab: title, "A1:D1"), values: [Self.headers])
        }
        return title
    }

    // MARK: - Generic values API

    /// Reads a range, e.g. "'September 2026'!A:D", returning rows of cell strings.
    func read(range: String) async throws -> [[String]] {
        if auth.isSignedIn {
            do {
                let url = base.appending(path: "\(spreadsheetID)/values/\(range)")
                let response: ValueRange = try await client.send(url)
                if let vals = response.values, !vals.isEmpty {
                    return vals
                }
            } catch {
                // If authenticated request fails, attempt public CSV fallback
                if let publicRows = try? await readPublicCSV(range: range), !publicRows.isEmpty {
                    return publicRows
                }
                throw error
            }
        }
        // Unauthenticated or fallback
        return (try? await readPublicCSV(range: range)) ?? []
    }

    private func readPublicCSV(range: String) async throws -> [[String]] {
        var sheetName = ""
        if let exclamation = range.firstIndex(of: "!") {
            sheetName = String(range[..<exclamation]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        } else {
            sheetName = range.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
        }

        var urlString = "https://docs.google.com/spreadsheets/d/\(spreadsheetID)/gviz/tq?tqx=out:csv"
        if !sheetName.isEmpty {
            if let encoded = sheetName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&sheet=\(encoded)"
            }
        }
        guard let url = URL(string: urlString) else { return [] }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return []
        }
        guard let csvText = String(data: data, encoding: .utf8) else { return [] }
        return parseCSV(csvText)
    }

    private func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (char == "\r" || char == "\n") && !inQuotes {
                if char == "\r" && text.index(after: index) < text.endIndex && text[text.index(after: index)] == "\n" {
                    index = text.index(after: index)
                }
                currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                if !currentRow.isEmpty && currentRow.contains(where: { !$0.isEmpty }) {
                    rows.append(currentRow)
                }
                currentRow = []
                currentField = ""
            } else {
                currentField.append(char)
            }
            index = text.index(after: index)
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.isEmpty && currentRow.contains(where: { !$0.isEmpty }) {
                rows.append(currentRow)
            }
        }
        return rows
    }

    /// Overwrites a range. `USER_ENTERED` parses values as if typed (numbers,
    /// dates, formulas); `RAW` stores them verbatim — use RAW for anything that
    /// has to read back byte-identical.
    func write(range: String, values: [[String]], inputOption: String = "USER_ENTERED") async throws {
        var url = base.appending(path: "\(spreadsheetID)/values/\(range)")
        url.append(queryItems: [.init(name: "valueInputOption", value: inputOption)])
        let body = try JSONEncoder().encode(ValueRange(range: range, values: values))
        try await client.send(url, method: "PUT", body: body)
    }

    /// Appends rows after the last row of data in the range's table.
    func append(range: String, values: [[String]], inputOption: String = "USER_ENTERED") async throws {
        var url = base.appending(path: "\(spreadsheetID)/values/\(range):append")
        url.append(queryItems: [
            .init(name: "valueInputOption", value: inputOption),
            .init(name: "insertDataOption", value: "INSERT_ROWS"),
        ])
        let body = try JSONEncoder().encode(ValueRange(values: values))
        try await client.send(url, method: "POST", body: body)
    }

    /// Clears all values from a range without deleting the cells themselves.
    func clear(range: String) async throws {
        let url = base.appending(path: "\(spreadsheetID)/values/\(range):clear")
        try await client.send(url, method: "POST", body: Data("{}".utf8))
    }

    // MARK: - Spreadsheet structure

    /// Titles of all tabs in the spreadsheet.
    func tabTitles() async throws -> [String] {
        if auth.isSignedIn {
            do {
                var url = base.appending(path: spreadsheetID)
                url.append(queryItems: [.init(name: "fields", value: "sheets.properties.title")])
                let response: Spreadsheet = try await client.send(url)
                if let sheets = response.sheets, !sheets.isEmpty {
                    return sheets.map(\.properties.title)
                }
            } catch {
                // Fall through to known tabs
            }
        }
        return [Self.monthTabName(for: .now), "Sheet1", SheetsSchema.Tab.transactions, SheetsSchema.Tab.budgets]
    }

    /// Creates a new tab (worksheet) with the given title.
    func createTab(title: String) async throws {
        let url = base.appending(path: "\(spreadsheetID):batchUpdate")
        let request = BatchUpdate(requests: [
            .init(addSheet: .init(properties: .init(title: title)))
        ])
        try await client.send(url, method: "POST", body: try JSONEncoder().encode(request))
    }

    /// Tests connection to the active spreadsheet and returns tabs count, transaction rows, and budget rows.
    func testConnection() async throws -> (tabCount: Int, transactionCount: Int, budgetCount: Int) {
        let titles = try await tabTitles()
        var txCount = 0
        var bgCount = 0

        let txRows = try await read(range: Self.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange))
        let monthRows = try await read(range: Self.a1(tab: Self.monthTabName(for: .now), "A:D"))
        let sheet1Rows = try await read(range: Self.a1(tab: "Sheet1", "A:D"))
        txCount = max(txRows.count > 1 ? txRows.count - 1 : 0, monthRows.count > 1 ? monthRows.count - 1 : 0, sheet1Rows.count > 1 ? sheet1Rows.count - 1 : 0)

        let bgRows = try await read(range: Self.a1(tab: SheetsSchema.Tab.budgets, SheetsSchema.budgetRange))
        bgCount = max(0, bgRows.count - 1)

        return (max(1, titles.count), txCount, bgCount)
    }

    // MARK: - Helpers

    /// A1 notation with the tab name single-quoted (required for names with spaces).
    nonisolated static func a1(tab: String, _ range: String) -> String {
        "'\(tab)'!\(range)"
    }

    private static func amountString(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "LLLL yyyy" // "September 2026"
        return f
    }()

    // MARK: - Models

    struct ValueRange: Codable {
        var range: String?
        var values: [[String]]?
    }

    private struct Spreadsheet: Decodable {
        let sheets: [Sheet]?
        struct Sheet: Decodable {
            let properties: Properties
            struct Properties: Decodable { let title: String }
        }
    }

    private struct BatchUpdate: Encodable {
        let requests: [Request]
        struct Request: Encodable {
            let addSheet: AddSheet
        }
        struct AddSheet: Encodable {
            let properties: Properties
            struct Properties: Encodable { let title: String }
        }
    }
}
