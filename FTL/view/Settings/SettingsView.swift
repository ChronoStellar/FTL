//
//  SettingsView.swift
//  FTL — view/Settings · Phase 1
//
//  Reached from the FTL wordmark. The design has no other home for it, and Sign
//  out has to be reachable.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthManager
    let environment: AppEnvironment
    let onDone: () -> Void

    // Spreadsheet config & sync state
    @State private var spreadsheetIDText: String = SheetsService.activeSpreadsheetID
    @State private var isEditingSpreadsheetID: Bool = false
    @State private var isSyncingSpreadsheet: Bool = false
    @State private var syncStatus: String?

    // Budget state
    @State private var budgetTree: [BudgetNode] = []
    @State private var editingNode: BudgetNode?
    @State private var editingCeilingDigits: String = ""
    @State private var isAddingCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryDigits: String = ""

    #if DEBUG
    @State private var developerTool: DeveloperTool?
    @State private var isMigrating: Bool = false
    @State private var migrationResult: String?
    @State private var didMigrate: Bool = false
    #endif

    private var currentInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: .now) ?? .init(start: .now, duration: 0)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Account")
                        .padding(.bottom, FTLSpacing.labelGap)
                    accountPanel

                    SectionLabel(text: "Spreadsheet Ledger")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    spreadsheetPanel

                    SectionLabel(text: "Budget Ceilings")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    budgetPanel

                    SectionLabel(text: "Trust")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    trustPanel

                    #if DEBUG
                    SectionLabel(text: "Developer")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    debugPanel
                    #endif
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
                .padding(.bottom, FTLSpacing.xxl)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(FTLColor.sheetBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDone).tint(FTLColor.textTertiary)
                }
            }
            .task {
                await loadBudgets()
            }
            .sheet(item: $editingNode) { node in
                editCeilingSheet(for: node)
            }
            .sheet(isPresented: $isAddingCategory) {
                addCategorySheet
            }
        }
        .presentationDetents([.large])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private var accountPanel: some View {
        PanelCard {
            valueRow("Name", auth.name ?? "—")
            valueRow("Email", auth.email ?? "—")
            PanelRow(showsDivider: false) {
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                    onDone()
                }
                .font(FTLTypography.rowTitle)
                .tint(FTLColor.destructive)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Spreadsheet Panel

    private var spreadsheetPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            PanelCard {
                PanelRow(showsDivider: true) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Spreadsheet ID / URL")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Spacer()
                            Button(isEditingSpreadsheetID ? "Cancel" : "Edit") {
                                if !isEditingSpreadsheetID {
                                    spreadsheetIDText = SheetsService.activeSpreadsheetID
                                }
                                isEditingSpreadsheetID.toggle()
                            }
                            .font(FTLTypography.caption)
                            .tint(FTLColor.accent)
                        }

                        if isEditingSpreadsheetID {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Paste Google Sheets URL or ID", text: $spreadsheetIDText)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)

                                HStack {
                                    Button("Reset to Default") {
                                        spreadsheetIDText = SheetsService.defaultSpreadsheetID
                                    }
                                    .font(FTLTypography.captionSmall)
                                    .tint(FTLColor.textTertiary)

                                    Spacer()

                                    Button("Save") {
                                        saveSpreadsheetID()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.top, 4)
                        } else {
                            Text(SheetsService.activeSpreadsheetID)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(FTLColor.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                PanelRow(showsDivider: false) {
                    HStack {
                        Button {
                            Task { await syncSpreadsheet() }
                        } label: {
                            HStack(spacing: 8) {
                                if isSyncingSpreadsheet {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundStyle(FTLColor.accent)
                                }
                                Text("Sync with Spreadsheet")
                                    .font(FTLTypography.rowTitle)
                                    .foregroundStyle(FTLColor.textPrimary)
                            }
                        }
                        .disabled(isSyncingSpreadsheet)
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }

                if let syncStatus {
                    PanelRow(showsDivider: false) {
                        Text(syncStatus)
                            .font(FTLTypography.captionSmall)
                            .foregroundStyle(syncStatus.contains("Failed") ? FTLColor.destructive : FTLColor.textSecondary)
                    }
                }
            }

            Text("Transactions and budgets are read from and written to this spreadsheet. Tab 'transactions' stores entries, and tab 'budgets' stores category ceilings.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    // MARK: - Budget Ceilings Panel

    private var budgetPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            PanelCard {
                if let root = budgetTree.first {
                    // Total Monthly Budget
                    Button {
                        startEditing(root)
                    } label: {
                        PanelRow(showsDivider: !root.children.isEmpty) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Monthly Total Budget")
                                        .font(FTLTypography.rowTitle)
                                        .foregroundStyle(FTLColor.textPrimary)
                                    Text("Overall month ceiling")
                                        .font(FTLTypography.captionSmall)
                                        .foregroundStyle(FTLColor.textQuaternary)
                                }
                                Spacer()
                                Text(MoneyFormatter.rp(root.ceiling))
                                    .font(FTLTypography.amountEmphasis)
                                    .foregroundStyle(root.ceiling.minorUnits > 0 ? FTLColor.textPrimary : FTLColor.textTertiary)
                                Chevron()
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Child Categories
                    ForEach(Array(root.children.enumerated()), id: \.element.id) { index, child in
                        Button {
                            startEditing(child)
                        } label: {
                            PanelRow(showsDivider: index < root.children.count - 1) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(child.name)
                                            .font(FTLTypography.rowTitle)
                                            .foregroundStyle(FTLColor.textPrimary)
                                        Text("Category ceiling")
                                            .font(FTLTypography.captionSmall)
                                            .foregroundStyle(FTLColor.textQuaternary)
                                    }
                                    Spacer()
                                    Text(MoneyFormatter.rp(child.ceiling))
                                        .font(FTLTypography.amountEmphasis)
                                        .foregroundStyle(child.ceiling.minorUnits > 0 ? FTLColor.textPrimary : FTLColor.textTertiary)
                                    Chevron()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    PanelRow(showsDivider: false) {
                        Text("Loading budgets…")
                            .font(FTLTypography.caption)
                            .foregroundStyle(FTLColor.textTertiary)
                    }
                }

                PanelRow(showsDivider: false) {
                    Button {
                        newCategoryName = ""
                        newCategoryDigits = ""
                        isAddingCategory = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(FTLColor.accent)
                            Text("Add Budget Category")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Set spending limits for each category. Ceilings are synchronized with the 'budgets' tab in your spreadsheet.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    // MARK: - Trust Panel

    private var trustPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            PanelCard {
                valueRow("Mode", environment.trustLevel.rawValue.capitalized, showsDivider: false)
            }
            Text("Every captured row waits for your approval. Auto-approval stays off until accuracy is re-measured — unattended writes require strict verification.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    #if DEBUG
    private var debugPanel: some View {
        PanelCard {
            debugRow("Google API harness", .harness, showsDivider: true)
            debugRow("Evaluation", .evaluation, showsDivider: true)

            // Legacy data migration
            PanelRow(showsDivider: migrationResult != nil) {
                Button {
                    Task { await runMigration() }
                } label: {
                    HStack(spacing: 8) {
                        if isMigrating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(FTLColor.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Migrate Legacy Data")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(didMigrate ? FTLColor.textTertiary : FTLColor.textPrimary)
                            Text("Import entries from month-named tabs into the transactions tab")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isMigrating || didMigrate)
            }

            if let migrationResult {
                PanelRow(showsDivider: false) {
                    Text(migrationResult)
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(
                            migrationResult.contains("Failed")
                                ? FTLColor.destructive
                                : FTLColor.textSecondary
                        )
                }
            }
        }
        // Presented rather than pushed: a NavigationLink inside this sheet's
        // stack doesn't push, and a lab bench doesn't need to be in the
        // navigation hierarchy anyway.
        .sheet(item: $developerTool) { tool in
            NavigationStack {
                switch tool {
                case .harness: DebugView()
                case .evaluation: EvaluationView()
                }
            }
        }
    }

    private func debugRow(_ title: String, _ tool: DeveloperTool, showsDivider: Bool) -> some View {
        Button { developerTool = tool } label: {
            PanelRow(showsDivider: showsDivider) {
                HStack {
                    Text(title)
                        .font(FTLTypography.rowTitle)
                        .foregroundStyle(FTLColor.textPrimary)
                    Spacer()
                    Chevron()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    enum DeveloperTool: String, Identifiable {
        case harness, evaluation
        var id: String { rawValue }
    }
    #endif

    private func valueRow(_ label: String, _ value: String, showsDivider: Bool = true) -> some View {
        PanelRow(showsDivider: showsDivider) {
            HStack {
                Text(label)
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(FTLColor.textPrimary)
                Spacer(minLength: FTLSpacing.sm)
                Text(value)
                    .font(FTLTypography.bodyRegular)
                    .foregroundStyle(FTLColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Sheets & Actions

    private func editCeilingSheet(for node: BudgetNode) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FTLSpacing.lg) {
                    VStack(spacing: 8) {
                        Text(node.name)
                            .font(FTLTypography.sectionLabel)
                            .foregroundStyle(FTLColor.textSecondary)

                        let currentMinor = Int(editingCeilingDigits) ?? 0
                        Text(MoneyFormatter.rp(Money.idr(currentMinor)))
                            .font(FTLTypography.display)
                            .foregroundStyle(FTLColor.textPrimary)
                    }
                    .padding(.top, FTLSpacing.lg)

                    PanelCard {
                        PanelRow(showsDivider: false) {
                            HStack {
                                Text("Ceiling (IDR)")
                                    .font(FTLTypography.rowTitle)
                                    .foregroundStyle(FTLColor.textPrimary)
                                Spacer()
                                TextField("0", text: $editingCeilingDigits)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(FTLTypography.amountEmphasis)
                                    .foregroundStyle(FTLColor.accent)
                            }
                        }
                    }

                    // Quick increments
                    HStack(spacing: 8) {
                        presetButton("+100k", add: 100_000)
                        presetButton("+500k", add: 500_000)
                        presetButton("+1M", add: 1_000_000)
                        presetButton("+5M", add: 5_000_000)
                        Button("Clear") {
                            editingCeilingDigits = "0"
                        }
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Text("This ceiling sets the maximum monthly spend target for \(node.name) in your spreadsheet.")
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textQuaternary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("Set Ceiling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingNode = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amount = Int(editingCeilingDigits) ?? 0
                        Task { await saveCeiling(node: node, minorUnits: amount) }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private var addCategorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FTLSpacing.lg) {
                    PanelCard {
                        PanelRow(showsDivider: true) {
                            HStack {
                                Text("Name")
                                    .font(FTLTypography.rowTitle)
                                    .foregroundStyle(FTLColor.textPrimary)
                                Spacer()
                                TextField("e.g. Entertainment", text: $newCategoryName)
                                    .multilineTextAlignment(.trailing)
                                    .font(FTLTypography.bodyRegular)
                            }
                        }

                        PanelRow(showsDivider: false) {
                            HStack {
                                Text("Monthly Ceiling")
                                    .font(FTLTypography.rowTitle)
                                    .foregroundStyle(FTLColor.textPrimary)
                                Spacer()
                                TextField("Optional (e.g. 1000000)", text: $newCategoryDigits)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(FTLTypography.bodyRegular)
                            }
                        }
                    }

                    Text("New categories will be appended to the 'budgets' tab in your active Google Sheet.")
                        .font(FTLTypography.captionSmall)
                        .foregroundStyle(FTLColor.textQuaternary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.horizontal, FTLSpacing.screenMargin)
                .padding(.top, FTLSpacing.lg)
            }
            .scrollContentBackground(.hidden)
            .background(FTLColor.sheetBackground)
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isAddingCategory = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let amount = Int(newCategoryDigits) ?? 0
                        Task { await addCategory(name: newCategoryName, minorUnits: amount) }
                    }
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(FTLColor.ground)
        .presentationCornerRadius(FTLRadius.sheet)
    }

    private func presetButton(_ title: String, add: Int) -> some View {
        Button(title) {
            let current = Int(editingCeilingDigits) ?? 0
            editingCeilingDigits = String(current + add)
        }
        .font(FTLTypography.captionSmall)
        .foregroundStyle(FTLColor.textPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(FTLColor.controlFill, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Logic

    private func loadBudgets() async {
        do {
            budgetTree = try await environment.budgets.tree(for: currentInterval)
        } catch {
            syncStatus = "Failed to load budgets: \(error.localizedDescription)"
        }
    }

    private func startEditing(_ node: BudgetNode) {
        editingCeilingDigits = String(node.ceiling.minorUnits)
        editingNode = node
    }

    private func saveCeiling(node: BudgetNode, minorUnits: Int) async {
        do {
            try await environment.budgets.setCeiling(Money.idr(minorUnits), for: node.id, in: currentInterval)
            await loadBudgets()
            editingNode = nil
        } catch {
            syncStatus = "Failed to update ceiling: \(error.localizedDescription)"
        }
    }

    private func addCategory(name: String, minorUnits: Int) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let slug = trimmed.lowercased().replacingOccurrences(of: " ", with: "_")
        let cat = SpendCategory(id: CategoryID(rawValue: slug), name: trimmed, parentID: CategoryID(rawValue: "total"))
        do {
            try await environment.budgets.addCategory(cat, under: CategoryID(rawValue: "total"))
            if minorUnits > 0 {
                try await environment.budgets.setCeiling(Money.idr(minorUnits), for: cat.id, in: currentInterval)
            }
            await loadBudgets()
            isAddingCategory = false
        } catch {
            syncStatus = "Failed to add category: \(error.localizedDescription)"
        }
    }

    private func saveSpreadsheetID() {
        let cleanID = SheetsService.extractSpreadsheetID(from: spreadsheetIDText)
        SheetsService.activeSpreadsheetID = cleanID
        spreadsheetIDText = cleanID
        isEditingSpreadsheetID = false
        Task {
            await syncSpreadsheet()
        }
    }

    private func syncSpreadsheet() async {
        isSyncingSpreadsheet = true
        syncStatus = "Connecting to Google Sheet…"
        do {
            let (tabCount, txCount, budgetCount) = try await SheetsService(auth: auth).testConnection()
            _ = try await environment.ledger.reload()
            await loadBudgets()
            syncStatus = "Synced! \(txCount) transactions, \(budgetCount) budgets across \(tabCount) tabs."
        } catch {
            syncStatus = "Sync failed: \(error.localizedDescription)"
        }
        isSyncingSpreadsheet = false
    }

    #if DEBUG
    private func runMigration() async {
        isMigrating = true
        migrationResult = "Scanning month-named tabs…"
        do {
            let migration = environment.makeLegacyMigration()
            let result = try await migration.migrate()
            // Invalidate the ledger cache so the dashboard picks up the new rows
            _ = try? await environment.ledger.reload()
            didMigrate = true
            if result.rowsMigrated == 0 {
                migrationResult = "No legacy data found across \(result.tabsScanned) month tabs."
            } else {
                migrationResult = "Migrated \(result.rowsMigrated) rows from \(result.tabsScanned) tab\(result.tabsScanned == 1 ? "" : "s")."
                    + (result.rowsSkipped > 0 ? " \(result.rowsSkipped) skipped (unparseable)." : "")
            }
        } catch {
            migrationResult = "Failed: \(error.localizedDescription)"
        }
        isMigrating = false
    }
    #endif
}
