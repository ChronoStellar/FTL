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
    // The single spreadsheet this app operates on.
    // From the sheet URL: docs.google.com/spreadsheets/d/THIS_PART/edit
    static let spreadsheetID = "1wdjmVUJln-Iwjw-fyS43kmC0WleXhRzyNbVJcqrh8Hc"

    /// Column headers written when a new month tab is created.
    static let headers = ["Date", "Category", "Description", "Amount"]

    private let client: GoogleAPIClient
    private let spreadsheetID: String
    private let base = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/")!

    init(auth: GoogleAuthManager, spreadsheetID: String = SheetsService.spreadsheetID) {
        self.client = GoogleAPIClient(auth: auth)
        self.spreadsheetID = spreadsheetID
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

    /// The tab name for a date, e.g. "September 2026".
    static func monthTabName(for date: Date = .now) -> String {
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
        let url = base.appending(path: "\(spreadsheetID)/values/\(range)")
        let response: ValueRange = try await client.send(url)
        return response.values ?? []
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

    // MARK: - Spreadsheet structure

    /// Titles of all tabs in the spreadsheet.
    func tabTitles() async throws -> [String] {
        var url = base.appending(path: spreadsheetID)
        url.append(queryItems: [.init(name: "fields", value: "sheets.properties.title")])
        let response: Spreadsheet = try await client.send(url)
        return (response.sheets ?? []).map { $0.properties.title }
    }

    /// Creates a new tab (worksheet) with the given title.
    func createTab(title: String) async throws {
        let url = base.appending(path: "\(spreadsheetID):batchUpdate")
        let request = BatchUpdate(requests: [
            .init(addSheet: .init(properties: .init(title: title)))
        ])
        try await client.send(url, method: "POST", body: try JSONEncoder().encode(request))
    }

    // MARK: - Helpers

    /// A1 notation with the tab name single-quoted (required for names with spaces).
    static func a1(tab: String, _ range: String) -> String {
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
