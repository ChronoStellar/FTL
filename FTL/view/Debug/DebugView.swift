//
//  DebugView.swift
//  FTL — view/Debug
//
//  A raw harness over the Google rails: hit Gmail, hit Sheets, see exactly what
//  comes back. Deliberately outside the architecture — it talks straight to the
//  services with no view model, because its whole job is to test the plumbing
//  before the pipeline exists to wrap it.
//
//  DEBUG builds only. The tab that hosts it is compiled out of Release.
//
//  Originally ContentView.swift — the Phase-0 feasibility screen.
//

import SwiftUI

struct DebugView: View {
    var body: some View {
        NavigationStack {
            DebugHarness()
                .navigationTitle("Debug")
        }
    }
}

private struct DebugHarness: View {
    @EnvironmentObject private var auth: GoogleAuthManager

    @State private var profile: GmailService.Profile?
    @State private var messages: [GmailService.Message] = []
    @State private var gmailQuery = ""
    @State private var status: String?

    // Expense entry state
    @State private var date = Date.now
    @State private var category = ""
    @State private var expenseDescription = ""
    @State private var amount = ""
    @State private var monthRows: [[String]] = []
    @State private var viewedMonth = Date.now

    // Exporter state
    @State private var exportProgress: ExportProgress = .idle
    @State private var exportedJSONURL: URL?
    @State private var exportedCSVURL: URL?
    @State private var isExporting = false
    @State private var exportTargetCount = 1000

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Name", value: auth.name ?? "—")
                LabeledContent("Email", value: auth.email ?? "—")
                Button("Sign out", role: .destructive) { auth.signOut() }
            }

            Section("Gmail") {
                TextField("Filter (e.g. from:someone subject:invoice)", text: $gmailQuery)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Load profile & recent mail") {
                    Task { await loadGmail() }
                }
                if let profile {
                    LabeledContent("Total messages", value: "\(profile.messagesTotal)")
                }
                ForEach(messages) { message in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(message.subject)
                                .font(.subheadline).bold().lineLimit(1)
                            Text(message.emailDate ?? "Unknown date")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let spending = message.spending {
                            Text(spending)
                                .font(.subheadline)
                                .foregroundStyle(.green)
                                .bold()
                        } else {
                            Text("—")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section("Gmail Exporter") {
                Text("Fetches the latest \(exportTargetCount) emails (metadata, plain & html body, excluding pdf/images) and exports to JSON & CSV.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isExporting ? "Exporting..." : "Export Latest \(exportTargetCount) Emails") {
                    Task { await runGmailExport() }
                }
                .disabled(isExporting)

                if isExporting || exportProgress != .idle {
                    Text(exportProgress.message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let json = exportedJSONURL, let csv = exportedCSVURL {
                    HStack(spacing: 12) {
                        ShareLink(item: json) {
                            Label("Share JSON", systemImage: "arrow.up.doc")
                        }
                        ShareLink(item: csv) {
                            Label("Share CSV", systemImage: "tablecells")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section("Add expense") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Category", text: $category)
                TextField("Description", text: $expenseDescription)
                TextField("Amount", text: $amount)
                    .keyboardType(.decimalPad)
                Button("Add to \(SheetsService.monthTabName(for: date))") {
                    Task { await addExpense() }
                }
                .disabled(category.isEmpty || Double(amount) == nil)
            }

            Section("Entries") {
                HStack {
                    Button { Task { await changeMonth(by: -1) } } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text(SheetsService.monthTabName(for: viewedMonth)).bold()
                    Spacer()
                    Button { Task { await changeMonth(by: 1) } } label: {
                        Image(systemName: "chevron.right")
                    }
                }
                .buttonStyle(.borderless)

                if monthRows.isEmpty {
                    Text("No entries.").foregroundStyle(.secondary)
                }
                ForEach(Array(monthRows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.joined(separator: " | "))
                            .font(.system(.footnote, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            Task { await deleteExpense(at: index) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        Task { await deleteExpense(at: index) }
                    }
                }
            }
            .task { await loadMonth() }

            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Actions

    private func loadGmail() async {
        let service = GmailService(auth: auth)
        do {
            profile = try await service.profile()
            messages = try await service.recentMessages(maxResults: 10, query: gmailQuery.isEmpty ? "in:inbox" : gmailQuery)
            status = "Loaded \(messages.count) messages."
        } catch {
            status = error.localizedDescription
        }
    }

    private func addExpense() async {
        guard let amountValue = Double(amount) else {
            status = "Enter a valid amount."
            return
        }
        let minorUnits = Int(amountValue.rounded())
        let txDate = date
        let txCategory = category.trimmingCharacters(in: .whitespaces)
        let txDesc = expenseDescription.trimmingCharacters(in: .whitespaces)

        let tx = LedgerTransaction(
            id: UUID(),
            date: txDate,
            amount: Money(minorUnits: minorUnits, currency: .idr),
            merchantRaw: txDesc.isEmpty ? "Manual entry" : txDesc,
            merchant: txDesc.isEmpty ? nil : txDesc,
            categoryID: txCategory.isEmpty ? nil : CategoryID(rawValue: txCategory.lowercased()),
            kind: .spend,
            nonSpendType: nil,
            source: .manual,
            sourcesMerged: [],
            splits: [],
            lineItems: [],
            provenance: .manual,
            flags: [],
            capturedAt: txDate,
            approvedAt: .now,
            notes: "Added via Debug harness"
        )

        let sheetsLedger = SheetsLedgerStore(auth: auth)
        let service = SheetsService(auth: auth)
        let expense = SheetsService.Expense(
            date: txDate,
            category: txCategory,
            description: txDesc,
            amount: amountValue
        )
        do {
            // 1. Write to canonical transactions tab
            try await sheetsLedger.append([tx])
            // 2. Write to month tab
            try await service.addExpense(expense)
            status = "Added to transactions & \(SheetsService.monthTabName(for: txDate))."
            category = ""
            expenseDescription = ""
            amount = ""
            viewedMonth = txDate // jump the viewer to the month we just added to
            await loadMonth()
        } catch {
            status = error.localizedDescription
        }
    }

    private func deleteExpense(at index: Int) async {
        guard index < monthRows.count else { return }
        let row = monthRows[index]
        let service = SheetsService(auth: auth)
        let ledgerStore = SheetsLedgerStore(auth: auth)
        do {
            // Delete from month tab
            try await service.deleteMonthRow(at: index, for: viewedMonth)

            // Also delete matching transaction from canonical transactions tab if found
            let rowDesc = row.count > 2 ? row[2] : ""
            let rowAmount = row.count > 3 ? (Double(row[3]) ?? 0) : 0
            let minor = Int(rowAmount.rounded())

            let allTx = try await ledgerStore.all()
            if let match = allTx.first(where: {
                $0.merchantRaw == rowDesc && $0.amount.minorUnits == minor
            }) {
                try await ledgerStore.delete(match.id)
            }

            status = "Deleted entry."
            await loadMonth()
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func changeMonth(by months: Int) async {
        guard let newMonth = Calendar.current.date(byAdding: .month, value: months, to: viewedMonth) else { return }
        viewedMonth = newMonth
        await loadMonth()
    }

    private func loadMonth() async {
        let service = SheetsService(auth: auth)
        do {
            monthRows = try await service.readMonth(for: viewedMonth)
            status = "Loaded \(monthRows.count) entries for \(SheetsService.monthTabName(for: viewedMonth))."
        } catch {
            status = error.localizedDescription
        }
    }

    private func runGmailExport() async {
        isExporting = true
        let exporter = GmailExporter(auth: auth)
        do {
            let (json, csv) = try await exporter.exportLatestEmails(
                targetCount: exportTargetCount,
                query: gmailQuery
            ) { progress in
                Task { @MainActor in
                    self.exportProgress = progress
                }
            }
            exportedJSONURL = json
            exportedCSVURL = csv
            isExporting = false
        } catch {
            exportProgress = .failed(error.localizedDescription)
            isExporting = false
        }
    }
}

#Preview {
    DebugView()
        .environmentObject(GoogleAuthManager.shared)
}
