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
import UIKit
import FoundationModels

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
    /// Only for the pattern store — everything else here talks to the services
    /// directly on purpose.
    private let environment = AppEnvironment.shared

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

    @State private var probeReport: [String] = []
    @State private var isProbing = false

    @State private var caseReport: [String] = []
    @State private var isCasing = false

    @State private var pipelineReport: [String] = []
    @State private var pipelineFileURL: URL?
    @State private var isPiping = false

    @State private var coverageReport: [String] = []
    @State private var coverageFileURL: URL?
    @State private var isCovering = false

    // Tagging, in shadow (Stage 4.5)
    @State private var tagReport: [String] = []
    @State private var isScoring = false

    // What the queue has said about each learned pattern (Stage 4.5)
    @State private var patternReport: [String] = []
    @State private var isScoringPatterns = false

    // The whole pipeline from a mailbox nobody has written anything for
    @State private var endToEndReport: [String] = []
    @State private var endToEndFileURL: URL?
    @State private var isRunningEndToEnd = false

    // Train on July–August, test on September, check against the real Sheet
    @State private var holdoutReport: [String] = []
    @State private var holdoutFileURL: URL?
    @State private var isRunningHoldout = false

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
                // A stress-test session and a real one must never look alike
                // by accident — see `AppEnvironment.LedgerBackend`.
                LabeledContent("Ledger", value: environment.ledgerBackend.rawValue)
                Button("Sign out", role: .destructive) { auth.signOut() }
            }

            // The only thing in the app that runs without a tap, and therefore
            // the only one whose behaviour is otherwise invisible. Shown here
            // rather than on a release screen: a sync that found nothing is not
            // news, and a failed one is not something a person can act on.
            Section("Auto-sync") {
                LabeledContent("Last run", value: environment.autoSync.lastResult ?? "not yet this session")
                Button("Force a sync now") {
                    Task { _ = await environment.autoSync.syncIfDue(force: true) }
                }
            }

            // The agent extending its own reach — ROADMAP Automation item C.
            // Runs once per launch on its own (see `DiscoverySync`); this is
            // only for watching it happen and re-arming it without relaunching.
            Section("Discovery") {
                LabeledContent("Last run", value: environment.discoverySync.lastResult ?? "not yet this session")
                Button("Force a discovery sweep now") {
                    Task { _ = await environment.discoverySync.runIfDue(force: true) }
                }
                // No preset, no oracle — even blu has to be discovered and
                // learned the same coverage-only way a sender this app has
                // never seen would be. See `AppEnvironment.pureAgentMode`.
                Toggle(
                    "Pure agent mode",
                    isOn: Binding(
                        get: { environment.pureAgentMode },
                        set: { environment.pureAgentMode = $0 }
                    )
                )
                Text("Drops blu's preset and its hand-written oracle. Takes effect on the next sync, not retroactively. Defaults ON right now for testing — see AppEnvironment.pureAgentMode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            // Synthetic cases with the answers attached. Deterministic — no
            // model, no network, no device patterns — so a red line here is a
            // regression rather than a difference of opinion about real mail.
            // The one harness that starts at NOTHING — no preset, no
            // hand-written parser, no learned pattern, no memory. Everything
            // else in this screen starts somewhere.
            Section("End-to-end · empty state") {
                Text("100 invented emails, 6 senders, nothing written for any of them. Runs the whole arc: discover → learn → sync → tag → settle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isRunningEndToEnd ? "Running…" : "Run end-to-end from zero") {
                    Task { await runEndToEnd() }
                }
                .disabled(isRunningEndToEnd)

                if let endToEndFileURL {
                    ShareLink(item: endToEndFileURL) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }

                ForEach(Array(endToEndReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(line.contains("✗") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            // Real Gmail, real Sheet, nothing scripted. The one harness that
            // asks whether the loop generalises forward in TIME the way it's
            // supposed to generalise across senders — see
            // `TemporalHoldoutRunner`.
            Section("Temporal holdout") {
                Text("Learns July–August from your real mailbox into isolated stores, then reads September using ONLY what it just learned, and checks the result against your real Sheet. Read-only both ends — writes nothing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(isRunningHoldout ? "Running…" : "Train Jul–Aug, test Sep") {
                    Task { await runTemporalHoldout() }
                }
                .disabled(isRunningHoldout)

                if let holdoutFileURL {
                    ShareLink(item: holdoutFileURL) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }

                ForEach(Array(holdoutReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(line.contains("✗") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Fixture cases") {
                Button(isCasing ? "Running…" : "Run pipeline cases") {
                    Task { await runCases() }
                }
                .disabled(isCasing)

                ForEach(Array(caseReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("✗") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            // The pipeline as a pipeline. Everything else in this screen
            // measures a component; this runs the real rail end to end and
            // shows what lands in the queue.
            Section("Pipeline · rail over the corpus") {
                Button(isPiping ? "Running…" : "Run the rail over the corpus") {
                    Task { await runPipeline() }
                }
                .disabled(isPiping)

                if let pipelineFileURL {
                    ShareLink(item: pipelineFileURL) {
                        Label("Share ledger rows (.tsv)", systemImage: "square.and.arrow.up")
                    }
                }

                ForEach(Array(pipelineReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            // How much of the money mail the app can actually read, measured
            // with the REAL parsers and whatever patterns are stored on this
            // device — not a re-implementation. A coverage number produced by
            // separate code measures the separate code.
            Section("Coverage · emails with Rp") {
                Button(isCovering ? "Reading…" : "Run coverage report") {
                    Task { await runCoverage() }
                }
                .disabled(isCovering)

                if let coverageFileURL {
                    ShareLink(item: coverageFileURL) {
                        Label("Share report", systemImage: "square.and.arrow.up")
                    }
                }

                ForEach(Array(coverageReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            // The shadow run for the second tool, and the only thing that can
            // decide the auto-commit threshold.
            //
            // Roadmap #14 is explicit that the number is a measurement rather
            // than a preference: run the tagger for a month without acting on
            // it, then count how often it would have matched you — per
            // merchant, because per merchant is the scope the evidence has.
            // Nothing here routes on the overall figure; it is printed to be
            // argued with.
            Section("Tagging · shadow scoreboard") {
                Button(isScoring ? "Counting…" : "Score the tagger against your approvals") {
                    Task { await runTagScoreboard() }
                }
                .disabled(isScoring)

                ForEach(Array(tagReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            // The loop's own scoreboard, and on a mailbox with no hand-written
            // parser the only one it has. Nothing is verified at synthesis
            // there — `verify` has no oracle — so this is where a pattern's
            // accuracy actually comes from.
            Section("Patterns · what the queue said") {
                Button(isScoringPatterns ? "Counting…" : "Score the learned patterns") {
                    Task { await runPatternScoreboard() }
                }
                .disabled(isScoringPatterns)

                ForEach(Array(patternReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Live Trace · Parsers & Agents") {
                LiveTraceSection()
            }

            // Isolates ONE variable at a time. `unsupportedLanguageOrLocale`
            // arrived on a prompt whose examples the recognizer called English,
            // so the refusal is not about the receipt's language — and every
            // further guess about which text "must" have triggered it is worth
            // less than one controlled call.
            Section("Model probe") {
                Button(isProbing ? "Probing…" : "Probe the model") {
                    Task { await probeModel() }
                }
                .disabled(isProbing)

                ForEach(Array(probeReport.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(line.hasPrefix("⚠︎") ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Pattern synthesis · blu") {
                Button(isSynthesizing ? "Proposing…" : "Learn a pattern for blu") {
                    Task { await runSynthesis(domain: BluReceiptParser.domain) }
                }
                .disabled(isSynthesizing)

                // The real test: a sender with NO hand-written parser, so
                // nothing can vouch for the result and it can only go
                // provisional.
                Button(isSynthesizing ? "Proposing…" : "Learn a pattern for Grab") {
                    Task { await runSynthesis(domain: "grab.com") }
                }
                .disabled(isSynthesizing)

                // Naming the sender is the last piece of hand-conditioning.
                // This one picks its own.
                Button(isSynthesizing ? "Working…" : "Learn what's unread") {
                    Task { await runDiscovery() }
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
    /// Times one phase and reports it, so "it got slower" is answerable
    /// without guessing which part.
    @discardableResult
    private func timed<T>(_ label: String, into lines: inout [String], _ work: () async throws -> T) async rethrows -> T {
        let started = Date.now
        let value = try await work()
        lines.append(String(format: "  %.2fs  %@", Date.now.timeIntervalSince(started), label))
        return value
    }

    /// How often the tagger's suggestion matched what you actually approved.
    ///
    /// Per merchant first and overall second, because that is the order the
    /// numbers are usable in. Invariant 10 scopes trust "per merchant, per
    /// sender, per tool — never a global switch", so the aggregate is context
    /// for reading the rows rather than a figure anything could be gated on.
    ///
    /// It also prints, for every merchant, what the threshold would COST there:
    /// at 80%, one row in five is wrong and lands unseen, and that sentence is
    /// only meaningful next to how many rows the merchant actually produces.
    private func runTagScoreboard() async {
        isScoring = true
        defer { isScoring = false }

        guard let memory = environment.tagMemory else {
            tagReport = ["⚠︎ no tag memory in this environment (sample fixtures don't accrue)"]
            return
        }

        var lines: [String] = []
        do {
            let board = try await memory.scoreboard()
            guard board.decisions > 0 else {
                tagReport = [
                    "Nothing decided yet.",
                    "",
                    "The scoreboard fills from the approval queue: every row you",
                    "approve records what was suggested against what you chose.",
                    "Approve a few and come back.",
                ]
                return
            }

            lines.append("\(board.decisions) decision(s) · \(board.suggested) carried a suggestion")
            if board.suggested > 0 {
                lines.append(String(format: "overall agreement %d/%d (%.1f%%)", board.agreed, board.suggested, board.hitRate * 100))
                lines.append("⚠︎ overall is for reading only — auto is scoped per merchant")
            } else {
                lines.append("nothing to score yet: no row has arrived pre-tagged")
            }
            lines.append("")
            lines.append("merchant                          n   agreed   settled")

            for history in board.byMerchant.prefix(40) {
                // Layout appended when there is one — see `TagKey`. This is
                // what makes "grab" showing up as several rows here, one per
                // service, visible rather than one row that could never
                // settle.
                let displayName = history.key.layout.map { "\(history.merchantRaw) · \($0)" } ?? history.merchantRaw
                let name = String(displayName.prefix(30)).padding(toLength: 30, withPad: " ", startingAt: 0)
                let agreement = history.suggested == 0
                    ? "  —   "
                    : String(format: "%2d/%-2d ", history.agreed, history.suggested)
                let settled = history.settled().map { outcome in
                    "\(outcome.categoryID?.rawValue ?? "not a spend") \(outcome.agreed)/\(outcome.of)"
                } ?? "—"
                lines.append("\(name) \(String(format: "%3d", history.total))  \(agreement)  \(settled)")
            }
            if board.byMerchant.count > 40 {
                lines.append("… \(board.byMerchant.count - 40) more")
            }
        } catch {
            lines = ["⚠︎ \(error)"]
        }
        tagReport = lines
    }

    /// The whole pipeline from an empty state. See `EndToEndRunner`.
    ///
    /// On a failure the model is asked to read the evidence the run recorded and
    /// say where to look. It is given that evidence and forbidden to go past it
    /// — see `FailureExplainer` — and its answer is labelled a guess, because
    /// nothing checks it.
    private func runEndToEnd() async {
        isRunningEndToEnd = true
        defer { isRunningEndToEnd = false }
        endToEndFileURL = nil
        do {
            var report = try await EndToEndRunner().run()
            report.reading = await FailureExplainer().read(report.failures)

            var lines = report.lines
            lines.append("")
            if report.isClean {
                lines.append("✓ all assertions held")
            } else {
                lines.append("✗ \(report.failures.count) assertion(s) failed")
                if let reading = report.reading {
                    lines.append("")
                    lines.append("⚠︎ the model's reading of the evidence above — a guess,")
                    lines.append("  not a measurement. Check it before acting on it.")
                    for line in reading.split(separator: "\n") { lines.append("  \(line)") }
                } else if !FailureExplainer.isAvailable {
                    lines.append("  (no on-device model here — evidence above is all there is)")
                }
            }
            endToEndReport = lines
            endToEndFileURL = Self.exportReport(lines)
        } catch {
            endToEndReport = ["⚠︎ \(error)"]
        }
    }

    /// Real Gmail (read-only), real Sheet (read-only) — see
    /// `TemporalHoldoutRunner` for what it does and does not measure.
    private func runTemporalHoldout() async {
        isRunningHoldout = true
        defer { isRunningHoldout = false }
        holdoutFileURL = nil
        do {
            let report = try await TemporalHoldoutRunner().run(
                auth: auth,
                ledger: environment.ledger,
                config: .julyAugustToSeptember()
            )
            holdoutReport = report.lines
            holdoutFileURL = Self.exportHoldoutReport(report.lines)
        } catch {
            holdoutReport = ["⚠︎ \(error)"]
        }
    }

    private static func exportHoldoutReport(_ lines: [String]) -> URL? {
        let header = [
            "FTL — temporal holdout: train Jul–Aug, test Sep, compare to the Sheet",
            ISO8601DateFormatter().string(from: .now),
            "",
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ftl-temporal-holdout.txt")
        do {
            try (header + lines).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Same idiom as the pipeline and coverage exports: a plain file in tmp,
    /// handed to `ShareLink`. A run whose output only exists on a phone screen
    /// cannot be diffed against the last one.
    private static func exportReport(_ lines: [String]) -> URL? {
        let header = [
            "FTL — end-to-end pipeline run from an empty state",
            ISO8601DateFormatter().string(from: .now),
            "",
        ]
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ftl-end-to-end.txt")
        do {
            try (header + lines).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// How the queue has voted on each learned pattern's rows.
    ///
    /// Reported as an ACCEPTANCE rate, not an accuracy, and the distinction is
    /// not pedantry: the queue cannot edit an amount or a merchant, so
    /// approving a row is a vote that it looked right rather than a check that
    /// it was. Dropped rows are counted apart for the same reason — a drop may
    /// be a misread or a perfectly-read email you did not want, and from here
    /// those are indistinguishable.
    private func runPatternScoreboard() async {
        isScoringPatterns = true
        defer { isScoringPatterns = false }

        guard let memory = environment.patternMemory else {
            patternReport = ["⚠︎ no pattern memory in this environment"]
            return
        }
        var lines: [String] = []
        do {
            let board = try await memory.scoreboard()
            guard board.settled > 0 else {
                patternReport = [
                    "No settled rows from a learned pattern yet.",
                    "",
                    "This fills from the approval queue: every row you approve or",
                    "drop is a verdict on the pattern that read it. Nothing here",
                    "until a learned pattern has produced rows AND you have",
                    "settled some — which today needs a sender blu doesn't cover.",
                ]
                return
            }
            let policy = PatternTrustPolicy.default
            lines.append("\(board.settled) settled row(s) across \(board.byPattern.count) pattern(s)")
            lines.append(String(format: "vouched at ≥%.0f%% over ≥%d rows", policy.acceptanceThreshold * 100, policy.minimumSettled))
            lines.append("")
            lines.append("pattern                              kept  fixed  dropped  accept  vouched")
            for record in board.byPattern {
                let name = String(record.patternID.prefix(34)).padding(toLength: 34, withPad: " ", startingAt: 0)
                lines.append(String(
                    format: "%@ %5d %6d %8d %6.0f%%  %@",
                    name, record.accepted, record.correctedKind, record.dropped,
                    record.acceptanceRate * 100,
                    policy.isVouchedFor(record) ? "yes" : "not yet"
                ))
            }
            lines.append("")
            lines.append("kept = approved as read · fixed = you flipped spend/non-spend")
            lines.append("⚠︎ acceptance, not accuracy — the queue can't correct a figure yet")
        } catch {
            lines = ["⚠︎ \(error)"]
        }
        patternReport = lines
    }

    /// The fixture suite. Deterministic, so this is the one thing in this
    /// screen that can be believed without being re-read every time.
    private func runCases() async {
        isCasing = true
        defer { isCasing = false }

        var lines: [String] = []
        do {
            let fixture = try PipelineFixture.load()
            let report = try await PipelineCaseRunner().run(fixture)

            lines.append("\(report.passed)/\(report.outcomes.count) passed · \(report.failures.count) failing · \(report.known.count) known issue(s)")
            lines.append("")

            for outcome in report.outcomes {
                let mark = outcome.passed ? (outcome.knownIssue == nil ? "✓" : "◐") : "✗"
                lines.append("\(mark) \(outcome.name)")
                for difference in outcome.differences {
                    lines.append("    \(difference)")
                }
                if let known = outcome.knownIssue, outcome.passed {
                    lines.append("    known: \(known)")
                }
            }
        } catch {
            lines.append("✗ failed to run: \(error)")
        }
        caseReport = lines
    }

    /// The whole pipeline, end to end, over recorded mail.
    ///
    /// Real `GmailRail`, real parsers, real precedence, real dedup, real
    /// patterns off this device — only the mailbox and the two stores are
    /// swapped, and the stores are swapped so a test run cannot pollute the
    /// actual approval queue.
    ///
    /// The counts matter less than the ROWS. A pipeline that queues 137 entries
    /// and a pipeline that queues 137 correct entries look identical from the
    /// summary line, and the second one is the only one worth shipping.
    private func runPipeline() async {
        isPiping = true
        defer { isPiping = false }

        var lines: [String] = []
        do {
            // Phase timings, because "it got slower" needs an answer, not a
            // theory. The corpus load is 75 MB of JSON and has always been the
            // floor; everything after it is the pipeline's own cost.
            let corpus = try await timed("load corpus (75 MB JSON)", into: &lines) {
                try EmailCorpus.load()
            }
            lines.append("  — \(corpus.emails.count) emails")
            // `empty: true` is load-bearing. The default seeds this store with
            // SampleLedger's preview fixtures, and the first run of this
            // harness reported them as pipeline output — placeholder rows dated
            // today, so they sorted straight to the top of the sample. A test
            // whose fixtures are indistinguishable from its results is worse
            // than no test.
            let provisional = InMemoryProvisionalStore(empty: true)
            let before = try await provisional.pending().count

            // Everything real except the mailbox and where rows land.
            let rail = GmailRail(
                exporter: CorpusEmailSource(corpus.emails),
                parsers: [BluReceiptParser()],
                provisional: provisional,
                log: InMemoryCaptureLog(),
                patterns: environment.patterns,
                fetchLimit: corpus.emails.count
            )

            let result = try await timed("rail.sync — fetch, parse, dedup, queue", into: &lines) {
                try await rail.sync()
            }
            lines.append("fetched \(result.fetched) · queued \(result.queued) · flagged \(result.flagged)")
            lines.append("not a purchase \(result.notAPurchase) · skipped \(result.skipped) · seen \(result.alreadySeen)")
            lines.append("possible duplicates \(result.duplicates)")

            // Second pass, same log: nothing should come through. Dedup is the
            // thing standing between a re-sync and duplicate spending, and it
            // has never been checked over more than a few emails.
            let again = try await timed("rail.sync again — dedup only", into: &lines) {
                try await rail.sync()
            }
            lines.append("re-sync → queued \(again.queued) (expect 0), already seen \(again.alreadySeen)")

            let pending = try await provisional.pending()
            lines.append("")
            // Stated, not assumed — this is the number that was silently wrong.
            lines.append("queue \(before) before → \(pending.count) row(s) after")
            if before != 0 {
                lines.append("⚠︎ store was not empty — results are contaminated")
            }

            var bySource: [String: Int] = [:]
            var flagged: [String: Int] = [:]
            for entry in pending {
                let source: String
                switch entry.provenance {
                case .rule(let id): source = id.rawValue
                case .model(let confidence): source = "model \(confidence)"
                case .manual: source = "manual"
                }
                bySource[source, default: 0] += 1
                for flag in entry.flags { flagged[flag.reason.rawValue, default: 0] += 1 }
            }
            for (rule, count) in bySource.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(count)×  \(rule)")
            }
            if !flagged.isEmpty {
                lines.append("flags: " + flagged.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            }

            // The last untested link, and the only output that matters: run the
            // queue through the REAL approval service into a ledger, and emit
            // the rows in the exact shape `SheetsLedgerStore` appends.
            //
            // Approving everything is not a claim that everything is correct —
            // it is how you see what WOULD be written. A wrong merchant, a
            // thousandfold amount, a spend that should have been a transfer:
            // all obvious in the row, all invisible in a count.
            let ledger = InMemoryLedgerStore(empty: true)
            let approvals = DefaultApprovalService(store: provisional, ledger: ledger)
            let approved = try await timed("approve \(pending.count) rows into the ledger", into: &lines) {
                try await approvals.approve(pending.map(\.id))
            }
            lines.append("approved \(approved.written.count), failed \(approved.failed.count)")

            let written = try await ledger.all()
                .sorted { $0.date > $1.date }
            let tsv = ([SheetsSchema.transactionColumns.joined(separator: "\t")]
                + written.map { SheetsSchema.row(from: $0).joined(separator: "\t") })
                .joined(separator: "\n")

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ftl-ledger-rows.tsv")
            try tsv.write(to: url, atomically: true, encoding: .utf8)
            pipelineFileURL = url

            lines.append("")
            lines.append("\(written.count) row(s) — sheet format, share for the full file")
            lines.append(SheetsSchema.transactionColumns.joined(separator: "\t"))
            for tx in written.prefix(6) {
                lines.append(SheetsSchema.row(from: tx).joined(separator: "\t"))
            }
        } catch {
            lines.append("⚠︎ failed: \(error.localizedDescription)")
        }
        pipelineReport = lines
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        return formatter
    }()

    /// What share of the money mail the app can read today, and who is next.
    ///
    /// Restricted to emails carrying `Rp`/`IDR`, because those are the ones
    /// that could possibly be a transaction — scoring against all 1,000 would
    /// bury the real number under newsletters and make it look worse than it is.
    ///
    /// Runs the same parser list and the same precedence as `GmailRail`, over
    /// the patterns actually persisted on this device, so the number describes
    /// the shipping app rather than a model of it.
    ///
    /// The last block is the point of the whole thing: the senders with the
    /// most unread money mail are the ranked worklist for the loop.
    private func runCoverage() async {
        isCovering = true
        defer { isCovering = false }

        var lines: [String] = []
        do {
            let corpus = try EmailCorpus.load()
            let candidates = corpus.emailsWithCurrency()

            // Mirrors AppEnvironment.makeGmailRail: hand-written first, then
            // learned patterns most-specific-first.
            let learned = (try? await environment.patterns?.active()) ?? []
            let parsers: [any ReceiptParser] = [BluReceiptParser()]
                + learned
                    .sorted { $0.bodyContains.count > $1.bodyContains.count }
                    .map(PatternDrivenParser.init(pattern:))

            lines.append("corpus \(corpus.emails.count) · with Rp/IDR \(candidates.count)")
            lines.append("parsers \(parsers.count) — \(learned.count) learned")
            lines.append("")

            var read = 0
            var notAPurchase = 0
            var missing: [String: Int] = [:]
            var byParser: [String: (read: Int, incomplete: Int, notAPurchase: Int)] = [:]
            var unclaimed: [String: Int] = [:]

            for email in candidates {
                guard let parser = parsers.first(where: { $0.canParse(email) }) else {
                    unclaimed[email.senderDomain, default: 0] += 1
                    continue
                }
                let name = parser.id.rawValue
                switch parser.parse(email) {
                case .parsed:
                    read += 1
                    byParser[name, default: (0, 0, 0)].read += 1
                case .incomplete(let field):
                    missing[field, default: 0] += 1
                    byParser[name, default: (0, 0, 0)].incomplete += 1
                case .notAPurchase:
                    notAPurchase += 1
                    byParser[name, default: (0, 0, 0)].notAPurchase += 1
                case .notApplicable:
                    // Claimed then declined — not the parser's template after
                    // all. Counts as unread, because no row comes out of it.
                    unclaimed[email.senderDomain, default: 0] += 1
                }
            }

            let incomplete = missing.values.reduce(0, +)
            let unread = unclaimed.values.reduce(0, +)
            func share(_ n: Int) -> String {
                candidates.isEmpty ? "—" : String(format: "%.0f%%", Double(n) / Double(candidates.count) * 100)
            }

            lines.append("read           \(read)  (\(share(read)))")
            lines.append("incomplete     \(incomplete)" + (missing.isEmpty ? "" : " — " + missing.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")))
            lines.append("not a purchase \(notAPurchase)")
            lines.append("unread         \(unread)  (\(share(unread)))")

            lines.append("")
            lines.append("by parser")
            for (name, tally) in byParser.sorted(by: { $0.value.read > $1.value.read }) {
                var detail = "\(tally.read) read"
                if tally.incomplete > 0 { detail += ", \(tally.incomplete) incomplete" }
                if tally.notAPurchase > 0 { detail += ", \(tally.notAPurchase) non-spend" }
                lines.append("  \(name) — \(detail)")
            }

            lines.append("")
            lines.append("unread senders — the loop's worklist")
            // A sender already covered still shows unread mail, and that is the
            // right answer, not a gap: Grab sends far more promos than receipts
            // and a layout pattern deliberately refuses them. Marking those
            // rows stops the list reading as "learn Grab again".
            let covered = Set(learned.map(\.senderDomain) + [BluReceiptParser.domain])
            for (domain, count) in unclaimed.sorted(by: { $0.value > $1.value }).prefix(10) {
                let known = covered.contains { domain.hasSuffix($0) }
                lines.append("  \(count)×  \(domain)\(known ? "   (covered — these are its other mail)" : "")")
            }

            // Written out as well as shown: a report you can only screenshot is
            // hard to compare against the next run.
            let text = lines.joined(separator: "\n")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("ftl-coverage.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            coverageFileURL = url
        } catch {
            lines.append("⚠︎ failed: \(error.localizedDescription)")
        }
        coverageReport = lines
    }

    /// Which variable actually causes `unsupportedLanguageOrLocale`.
    ///
    /// Four calls, changing one thing at a time:
    ///
    ///   1. a bare English prompt with no receipt in it at all
    ///   2. the real instructions + an English blu excerpt  (this used to work)
    ///   3. the real instructions + an English Grab ride excerpt
    ///   4. the real instructions + an Indonesian Grab food excerpt
    ///
    /// If 1 fails, the session is refusing before it has seen any receipt and
    /// the cause is the DEVICE — its language settings, not the mail. If 1 and
    /// 2 pass while 3 and 4 fail, the framework is doing its own content
    /// language detection and disagreeing with `NLLanguageRecognizer`. If all
    /// four pass, the failure is in guided generation rather than the session,
    /// which probe 5 checks by asking for the real `@Generable` type.
    private func probeModel() async {
        isProbing = true
        defer { isProbing = false }

        var lines: [String] = []

        let model = SystemLanguageModel.default
        lines.append("availability: \(model.availability)")
        lines.append("supported: \(model.supportedLanguages.map { $0.maximalIdentifier }.sorted().joined(separator: " "))")
        lines.append("locale: \(Locale.current.identifier) · \(Locale.current.language.maximalIdentifier)")
        lines.append("preferred: \(Locale.preferredLanguages.prefix(3).joined(separator: " "))")
        lines.append("current supported: \(model.supportedLanguages.contains(Locale.current.language))")

        func probe(_ label: String, instructions: String?, prompt: String) async {
            do {
                let session = instructions.map { LanguageModelSession(instructions: $0) }
                    ?? LanguageModelSession()
                let reply = try await session.respond(
                    to: prompt,
                    options: GenerationOptions(temperature: 0.1)
                )
                lines.append("✅ \(label): \(reply.content.prefix(40))")
            } catch {
                lines.append("⚠︎ \(label): \(error)")
            }
        }

        await probe("1 bare English", instructions: nil, prompt: "Reply with the single word OK.")

        // Real excerpts, real instructions — the only difference from the
        // synthesis call is that the answer is plain text.
        let corpus = try? EmailCorpus.load()
        func excerpt(domain: String, layout: String? = nil) -> String? {
            guard let corpus else { return nil }
            let layouts = SenderTriage.templates(from: corpus.emails(from: domain))
            let chosen: SenderTriage.Template?
            if let layout {
                chosen = layouts.first { $0.key == layout }
            } else {
                chosen = layouts.first
            }
            return chosen?.emails.first.map(FoundationModelSynthesizer.excerpt)
        }

        let blu = excerpt(domain: BluReceiptParser.domain)
        let ride = excerpt(domain: "grab.com", layout: "compliments")
        let food = excerpt(domain: "grab.com", layout: "diterbitkan")

        let ask = "Name the word that appears immediately before the amount. Answer with that word only."
        if let blu {
            await probe("2 blu excerpt", instructions: FoundationModelSynthesizer.probeInstructions, prompt: "\(ask)\n\n\(blu)")
        }
        if let ride {
            await probe("3 ride excerpt", instructions: FoundationModelSynthesizer.probeInstructions, prompt: "\(ask)\n\n\(ride)")
        }
        if let food {
            await probe("4 food excerpt", instructions: FoundationModelSynthesizer.probeInstructions, prompt: "\(ask)\n\n\(food)")
        }

        // 5: identical to 3, except it asks for the real guided-generation type.
        // Separates "the session refuses this text" from "the schema refuses".
        if let ride {
            do {
                let session = LanguageModelSession(instructions: FoundationModelSynthesizer.probeInstructions)
                let reply = try await session.respond(
                    to: "\(ask)\n\n\(ride)",
                    generating: ProposedPattern.self,
                    options: GenerationOptions(temperature: 0.1)
                )
                lines.append("✅ 5 ride + @Generable: amountAfter \(reply.content.amountAfter)")
            } catch {
                lines.append("⚠︎ 5 ride + @Generable: \(error)")
            }
        }

        probeReport = lines
    }

    private func runSynthesis(domain: String) async {
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
            let fromSender = corpus.emails(from: domain)
            let layouts = SenderTriage.templates(from: fromSender)
            lines.append("corpus \(corpus.emails.count) · \(domain) \(fromSender.count) email(s)")
            lines.append("layouts: \(layouts.map { "\($0.emails.count)×\($0.key.isEmpty ? "—" : $0.key)" }.joined(separator: ", "))")

            let learner = DefaultPatternLearner(
                synthesizer: FoundationModelSynthesizer(),
                oracle: ParserOracle(BluReceiptParser())
            )
            let started = Date.now
            let outcomes = await learner.learn(
                senderDomain: domain,
                from: fromSender,
                policy: .default
            )
            lines.append(String(format: "elapsed %.1fs", Date.now.timeIntervalSince(started)))

            // One block per layout. A sender that half-succeeds is the normal
            // case now, and a report that collapsed to one verdict would hide
            // exactly the half that needs looking at.
            for result in outcomes {
                lines.append("")
                lines.append("── \(result.template.isEmpty ? "single layout" : result.template) · \(result.emailCount) email(s)")
                if !result.discriminators.isEmpty {
                    lines.append("  identified by: \(result.discriminators.joined(separator: " + "))")
                }

                // What the gate SAW, not only what it decided. A refusal has
                // twice been diagnosed by reasoning about which text it must
                // have been reading; print it instead.
                if let layout = layouts.first(where: { $0.key == result.template }) {
                    let excerpts = layout.emails
                        .prefix(PatternSynthesisPolicy.default.maxExamples)
                        .map(FoundationModelSynthesizer.excerpt)
                    let tally = DefaultLanguageGate.languageTally(of: excerpts)
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key)×\($0.value)" }
                        .joined(separator: " ")
                    lines.append("  examples read as: \(tally)")
                }

                lines.append(contentsOf: await report(result.outcome))
            }
        } catch {
            lines.append("⚠︎ failed: \(error.localizedDescription)")
        }
        synthReport = lines
    }

    /// The loop choosing its own targets — the last hand-conditioned step.
    ///
    /// Same learner, same bars, same persistence as the per-sender buttons.
    /// The only difference is that nobody typed a domain.
    private func runDiscovery() async {
        isSynthesizing = true
        defer { isSynthesizing = false }

        var lines: [String] = []
        guard FoundationModelSynthesizer.isAvailable else {
            synthReport = ["⚠︎ FoundationModels unavailable here — needs a real device."]
            return
        }

        do {
            let corpus = try EmailCorpus.load()

            // The app's current reach, as the rail sees it — so "unread" means
            // unread by the shipping app, patterns learned so far included.
            let learned = (try? await environment.patterns?.active()) ?? []
            let parsers: [any ReceiptParser] = [BluReceiptParser()]
                + learned
                    .sorted { $0.bodyContains.count > $1.bodyContains.count }
                    .map(PatternDrivenParser.init(pattern:))
            let isRead: (CapturedEmail) -> Bool = { email in
                guard let parser = parsers.first(where: { $0.canParse(email) }) else { return false }
                if case .parsed = parser.parse(email) { return true }
                return false
            }
            // Senders with at least one active pattern — a rarer layout from
            // the SAME sender gets the relaxed evidence floor. See
            // `PatternSynthesisPolicy.minimumProvisionalEvidenceForKnownSender`.
            let knownSenders = Set(parsers.compactMap { ($0 as? DomainScopedParser)?.domain })

            let discovery = PatternDiscovery(
                learner: DefaultPatternLearner(
                    synthesizer: FoundationModelSynthesizer(),
                    oracle: ParserOracle(BluReceiptParser())
                )
            )

            let shortlist = discovery.candidates(in: corpus.emails, isRead: isRead, knownSenders: knownSenders)
            lines.append("candidates: \(shortlist.count)")
            for candidate in shortlist.prefix(6) {
                let shape = candidate.transactionalLayouts
                    .map { String(format: "%d@%.2f", $0.emails.count, $0.amountVariance) }
                    .joined(separator: " ")
                lines.append("  \(candidate.senderDomain) — \(candidate.unreadMoneyMail) unread · \(shape)")
            }

            let started = Date.now
            let findings = await discovery.run(over: corpus.emails, isRead: isRead, knownSenders: knownSenders)
            lines.append(String(format: "elapsed %.1fs", Date.now.timeIntervalSince(started)))

            for finding in findings {
                lines.append("")
                lines.append("══ \(finding.senderDomain)")
                for result in finding.outcomes {
                    lines.append("── \(result.template.isEmpty ? "single layout" : result.template) · \(result.emailCount) email(s)")
                    lines.append(contentsOf: await report(result.outcome))
                }
            }
            if findings.isEmpty {
                lines.append("nothing to learn — no unread sender clears the bars")
            }
        } catch {
            lines.append("⚠︎ failed: \(error.localizedDescription)")
        }
        synthReport = lines
    }

    /// One outcome, rendered — and persisted when it earned it.
    private func report(_ outcome: SynthesisOutcome) async -> [String] {
        var lines: [String] = []
        switch outcome {
        case .promoted(let pattern, let feedback):
            lines.append("✅ PROMOTED — \(Self.describe(feedback))")
            lines.append(contentsOf: Self.describe(pattern))
            // Without this the loop forgets everything it learned the
            // moment this screen closes.
            do {
                try await environment.patterns?.save(pattern)
                let active = (try? await environment.patterns?.active()) ?? []
                lines.append("saved · \(active.count) active pattern(s) — the rail will use it next sync")
            } catch {
                lines.append("⚠︎ promoted but NOT saved: \(error.localizedDescription)")
            }
        case .provisional(let pattern, let coverage, let evidence):
            lines.append(String(format: "◐ PROVISIONAL — reads %.0f%% of %d emails, correctness UNVERIFIED", coverage * 100, evidence))
            lines.append(contentsOf: Self.describe(pattern))
            do {
                try await environment.patterns?.save(pattern)
                lines.append("saved · its rows will arrive flagged for review")
            } catch {
                lines.append("⚠︎ not saved: \(error.localizedDescription)")
            }

        case .rejected(let best, let feedback, let attempts, let lastError):
            lines.append("⚠︎ REJECTED after \(attempts) attempt(s)")
            if let lastError { lines.append("⚠︎ last call threw: \(lastError)") }
            if let feedback { lines.append("best: \(Self.describe(feedback))") }
            if let best { lines.append(contentsOf: Self.describe(best)) }
            for failure in (feedback?.failures.prefix(4) ?? []) {
                lines.append("⚠︎ \(failure.field): got \(failure.extracted ?? "nil") want \(failure.expected ?? "?")")
            }
        case .insufficientEvidence(let available):
            lines.append("⚠︎ insufficient evidence — \(available) email(s)")
        case .notTransactional(let distinct, let of):
            lines.append("○ not transactional — only \(distinct) distinct figure-set(s) in \(of) email(s), no model call spent")
        case .gated(let reason):
            lines.append("⚠︎ LanguageGate refused: \(reason)")
        }
        return lines
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
            "  body:    \(pattern.bodyContains.isEmpty ? "(any)" : pattern.bodyContains.joined(separator: " + "))",
            "  amount:  \(anchors(pattern.amount))",
            "  merchant:\(anchors(pattern.merchant))",
            "  nonSpend:\(pattern.nonSpendMarkers.isEmpty ? " (none)" : " " + pattern.nonSpendMarkers.map { "\($0.contains) → \($0.type?.rawValue ?? "unspecified")" }.joined(separator: " | "))",
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

private struct LiveTraceSection: View {
    @State private var filter: Filter = .all
    @State private var copied: Bool = false
    private var stub: PipelineDebugStub { PipelineDebugStub.shared }

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case agent = "🤖 Agent"
        case preMade = "📦 Pre-made"
        case taggers = "🏷️ Taggers"

        var id: String { rawValue }
    }

    var filteredEvents: [PipelineDebugEvent] {
        switch filter {
        case .all:
            return stub.events
        case .agent:
            return stub.events.filter { event in
                switch event.kind {
                case .parserMatched(let origin): return origin.isAgent
                case .taggerApplied(let source): return source.isAgent
                case .synthesisAttempt: return true
                default: return false
                }
            }
        case .preMade:
            return stub.events.filter { event in
                if case .parserMatched(let origin) = event.kind {
                    return origin.isPreset
                }
                return false
            }
        case .taggers:
            return stub.events.filter { event in
                switch event.kind {
                case .taggerApplied, .taggerSkipped: return true
                default: return false
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Metrics grid
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    metricPill("📦 Pre-made", count: stub.countPreMadeParsers, color: .blue)
                    metricPill("🤖 Agent Parsers", count: stub.countAgentParsers, color: .purple)
                    metricPill("🛠️ Hardcoded", count: stub.countHardcodedParsers, color: .orange)
                }
                HStack {
                    metricPill("🤖 Agent Tagger", count: stub.countAgentTaggerCalls, color: .indigo)
                    metricPill("🧠 Memory Hits", count: stub.countMemoryTaggerHits, color: .teal)
                    metricPill("⏭️ Skipped", count: stub.countSkippedEmails, color: .gray)
                }
            }
            .padding(.vertical, 4)

            // Actions & Filter
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                Button(copied ? "Copied!" : "Copy") {
                    UIPasteboard.general.string = stub.formattedLogDump()
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        copied = false
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)

                Button("Clear") {
                    stub.clear()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }

            if filteredEvents.isEmpty {
                Text(stub.events.isEmpty ? "No events recorded yet. Sync Gmail or run corpus to see live parser & agent trace." : "No events matching filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(filteredEvents) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(event.badge)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeColor(event.tagColorName).opacity(0.15))
                                .foregroundStyle(badgeColor(event.tagColorName))
                                .clipShape(RoundedRectangle(cornerRadius: 4))

                            Text(event.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)

                            Spacer()

                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Text(event.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(event.details)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.85))
                            .padding(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }

    private func metricPill(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(count > 0 ? color : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.08))
        .clipShape(Capsule())
    }

    private func badgeColor(_ name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "teal": return .teal
        case "indigo": return .indigo
        case "green": return .green
        default: return .gray
        }
    }
}

#Preview {
    DebugView()
        .environmentObject(GoogleAuthManager.shared)
}
