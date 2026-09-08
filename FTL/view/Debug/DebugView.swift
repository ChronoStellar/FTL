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

    // Budgets-tab inspector
    @State private var budgetReport: [String] = []
    @State private var isInspecting = false

    // Pattern synthesis (Stage 4)
    @State private var synthReport: [String] = []
    @State private var isSynthesizing = false

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

            Section("Pattern synthesis · blu") {
                Button(isSynthesizing ? "Proposing…" : "Learn a pattern for blu") {
                    Task { await runSynthesis() }
                }
                .disabled(isSynthesizing)

                ForEach(Array(synthReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Budgets tab (raw)") {
                Button(isInspecting ? "Reading…" : "Inspect budgets + categories") {
                    Task { await inspectBudgets() }
                }
                .disabled(isInspecting)

                ForEach(Array(budgetReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            if let status {
                Section { Text(status).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    // MARK: Actions

    /// Dumps the budgets tab verbatim and re-runs the app's own resolution over
    /// it, so a bucket that "should be there" but isn't can be read off the
    /// screen instead of guessed at. Every fix in this area so far has been a
    /// hypothesis about data nobody could see; this is how that stops.
    ///
    /// Reads both tabs raw rather than going through the stores on purpose —
    /// the stores are exactly what's under suspicion, so their view of the
    /// sheet is not evidence.
    private func inspectBudgets() async {
        isInspecting = true
        defer { isInspecting = false }

        let service = SheetsService(auth: auth)
        var lines: [String] = []
        do {
            let raw = try await service.read(
                range: SheetsService.a1(tab: SheetsSchema.Tab.budgets, SheetsSchema.budgetRange)
            )
            let rows = Array(raw.dropFirst())
            lines.append("budgets tab: \(rows.count) row(s) below the header")

            // Verbatim, with empty vs absent cells distinguished — a blank
            // parent column and a missing one behave differently.
            var ids: Set<String> = []
            for (index, row) in rows.enumerated() {
                let cell = { (i: Int) -> String in
                    i < row.count ? (row[i].isEmpty ? "∅" : row[i]) : "—"
                }
                lines.append("\(index + 1). id=\(cell(0)) name=\(cell(1)) parent=\(cell(2)) ceiling=\(cell(3)) month=\(cell(4))")
                if let first = row.first, !first.isEmpty {
                    ids.insert(CategoryID(rawValue: first).rawValue)
                }
            }

            // A root is a row with no parent. No root means no tree.
            let roots = rows.filter { $0.count > 2 && $0[2].trimmingCharacters(in: .whitespaces).isEmpty }
            lines.append(roots.isEmpty
                ? "⚠︎ no root row — nothing has an empty parent column"
                : "roots: \(roots.compactMap { $0.first }.joined(separator: ", "))")

            // Parents that point at an id no row actually has.
            for row in rows where row.count > 2 {
                let parent = row[2].trimmingCharacters(in: .whitespaces)
                guard !parent.isEmpty, !ids.contains(CategoryID(rawValue: parent).rawValue) else { continue }
                lines.append("⚠︎ '\(row.first ?? "?")' points at parent '\(parent)' — no row has that id")
            }

            // Categories the ledger actually uses that have no budget row.
            let txRaw = try await service.read(
                range: SheetsService.a1(tab: SheetsSchema.Tab.transactions, SheetsSchema.transactionRange)
            )
            let used = Set(
                txRaw.dropFirst()
                    .compactMap { $0.count > 6 ? $0[6] : nil }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { CategoryID(rawValue: $0).rawValue }
            )
            let missing = used.subtracting(ids).sorted()
            lines.append(missing.isEmpty
                ? "every transaction category has a budget row"
                : "⚠︎ used on transactions, no budget row: \(missing.joined(separator: ", "))")

            // Same id, different spelling — what the lowercasing now collapses.
            let rawIDs = rows.compactMap { $0.first }.filter { !$0.isEmpty }
            if rawIDs.count != Set(rawIDs.map { CategoryID(rawValue: $0).rawValue }).count {
                lines.append("⚠︎ duplicate ids once normalized — the tab has the same bucket spelled more than one way")
            }

            // Where the transactions tab's data actually sits. `values.append`
            // writes "starting with the first column of the table it finds", so
            // a missing header or a row whose leading cells are blank moves
            // every future append sideways.
            lines.append("—")
            let header = txRaw.first ?? []
            lines.append(header.first?.lowercased() == SheetsSchema.transactionColumns.first
                ? "transactions header: OK (\(header.count) cols)"
                : "⚠︎ transactions header missing or shifted — first cell = '\(header.first ?? "—")'")

            let txRows = Array(txRaw.dropFirst())
            lines.append("transactions: \(txRows.count) data row(s)")
            for (offset, row) in txRows.suffix(3).enumerated() {
                let occupied = row.indices.filter { !row[$0].trimmingCharacters(in: .whitespaces).isEmpty }
                let span = occupied.isEmpty
                    ? "empty"
                    : "\(Self.columnLetter(occupied.first!))–\(Self.columnLetter(occupied.last!))"
                lines.append("row \(txRows.count - min(3, txRows.count) + offset + 1): \(row.count) cells, filled \(span)")
            }
            if let offender = txRows.firstIndex(where: { row in
                let leadingEmpty = (row.first ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                let hasLater = row.dropFirst().contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                return leadingEmpty && hasLater
            }) {
                lines.append("⚠︎ row \(offender + 1) has an empty first cell but data further right — this is what drags an append off column A")
            }
        } catch {
            lines = ["failed: \(error.localizedDescription)"]
        }
        budgetReport = lines
    }

    /// Runs the whole loop against blu: propose from 5 examples, verify against
    /// the ~111 held out, retry on failure, report what came back.
    ///
    /// `BluReceiptParser` is the oracle, which is why this can run before
    /// `labels.json` exists — the truth for this sender is already in the
    /// codebase, and 116/116 is the bar its replacement has to clear.
    private func runSynthesis() async {
        isSynthesizing = true
        defer { isSynthesizing = false }

        var lines: [String] = []

        // Availability first: the corpus load below is 75 MB of JSON, and there
        // is no reason to pay for it only to discover there's no model.
        guard FoundationModelSynthesizer.isAvailable else {
            synthReport = ["⚠︎ FoundationModels unavailable here — needs a real device."]
            return
        }

        do {
            // ⚠️ Loads the whole 75 MB export to use ~116 of it. Fine for a
            // debug run on a desk; do not put this behind a user-facing button.
            let corpus = try EmailCorpus.load()
            let blu = corpus.emails(from: BluReceiptParser.domain)
            lines.append("corpus \(corpus.emails.count) · blu \(blu.count)")

            let learner = DefaultPatternLearner(
                synthesizer: FoundationModelSynthesizer(),
                oracle: ParserOracle(BluReceiptParser())
            )
            let started = Date.now
            let outcome = await learner.learn(
                senderDomain: BluReceiptParser.domain,
                from: blu,
                policy: .default
            )
            lines.append(String(format: "elapsed %.1fs", Date.now.timeIntervalSince(started)))

            switch outcome {
            case .promoted(let pattern, let feedback):
                lines.append("✅ PROMOTED — \(Self.describe(feedback))")
                lines.append(contentsOf: Self.describe(pattern))
            case .rejected(let best, let feedback, let attempts):
                lines.append("⚠︎ REJECTED after \(attempts) attempt(s)")
                if let feedback { lines.append("best: \(Self.describe(feedback))") }
                if let best { lines.append(contentsOf: Self.describe(best)) }
                for failure in (feedback?.failures.prefix(4) ?? []) {
                    lines.append("⚠︎ \(failure.field): got \(failure.extracted ?? "nil") want \(failure.expected ?? "?")")
                }
            case .insufficientEvidence(let available):
                lines.append("⚠︎ insufficient evidence — \(available) email(s)")
            case .gated(let reason):
                lines.append("⚠︎ LanguageGate refused: \(reason)")
            }
        } catch {
            lines.append("⚠︎ failed: \(error.localizedDescription)")
        }
        synthReport = lines
    }

    private static func describe(_ feedback: PatternFeedback) -> String {
        String(format: "%d/%d correct (%.1f%%)", feedback.succeeded, feedback.attempted, feedback.accuracy * 100)
    }

    /// The artifact, in full. The point of the loop is that this is readable —
    /// if it isn't, you can't revoke what you can't understand.
    private static func describe(_ pattern: ExtractionPattern) -> [String] {
        func anchors(_ list: [ExtractionPattern.Anchor]) -> String {
            list.map { anchor in
                let ends = anchor.before.isEmpty ? "…\(ExtractionPattern.Anchor.window) chars" : anchor.before.joined(separator: " | ")
                return "after '\(anchor.after)' → \(ends)"
            }.joined(separator: "  ,  ")
        }
        return [
            "  subject: \(pattern.subjectContains.isEmpty ? "(any)" : pattern.subjectContains.joined(separator: " | "))",
            "  amount:  \(anchors(pattern.amount))",
            "  merchant:\(anchors(pattern.merchant))",
            "  nonSpend:\(pattern.nonSpendMarkers.isEmpty ? " (none)" : " " + pattern.nonSpendMarkers.joined(separator: " | "))",
            "  verified on \(pattern.verifiedAgainst) · v\(pattern.version) · \(pattern.author)",
        ]
    }

    private static func columnLetter(_ index: Int) -> String {
        guard index < 26 else { return "?\(index)" }
        return String(UnicodeScalar(UInt8(65 + index)))
    }

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
            categoryID: txCategory.isEmpty ? nil : CategoryID(rawValue: txCategory),
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
