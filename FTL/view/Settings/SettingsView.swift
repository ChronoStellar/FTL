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
    /// Categories real transactions reference but that never got a budget row —
    /// see `loadMissingCategories()`.
    @State private var missingCategories: [CategoryID] = []
    @State private var isShowingIncomeSplit: Bool = false
    @State private var isBackgroundRefreshOn: Bool = BackgroundRefresh.isEnabled
    @State private var isDigestOn: Bool = NotificationSchedule.isEnabled
    @State private var digestTime: Date = {
        var components = DateComponents()
        components.hour = NotificationSchedule.hour
        components.minute = NotificationSchedule.minute
        return Calendar.current.date(from: components) ?? .now
    }()
    @State private var dailyBudgetEnabled: Bool = DailyBudgetManager.amount != nil
    @State private var dailyBudgetDigits: String = {
        if let amount = DailyBudgetManager.amount { return String(amount) }
        return ""
    }()
    @State private var dailyBudgetRollsOver: Bool = DailyBudgetManager.rollsOver
    @State private var notificationsDenied: Bool = false
    @State private var widgetRefreshMessage: String? = nil

    #if DEBUG
    @State private var developerTool: DeveloperTool?
    @State private var isSyncingMail: Bool = false
    @State private var mailSyncResult: String?
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
                    
                    dailyBudgetPanel
                        .padding(.top, FTLSpacing.xl)

                    SectionLabel(text: "Budget Ceilings")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    budgetPanel

                    SectionLabel(text: "Background")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    backgroundPanel

                    SectionLabel(text: "Trust")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    trustPanel

                    SectionLabel(text: "Home Screen Widgets")
                        .padding(.top, FTLSpacing.xl)
                        .padding(.bottom, FTLSpacing.labelGap)
                    widgetsPanel

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
            .background(
                FTLColor.sheetBackground
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
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
            .sheet(isPresented: $isShowingIncomeSplit) {
                IncomeSplitScreen(
                    environment: environment,
                    interval: currentInterval,
                    onSkip: { isShowingIncomeSplit = false },
                    onSaved: {
                        isShowingIncomeSplit = false
                        Task { await loadBudgets() }
                    }
                )
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
                // `.tint` does not reach a `role: .destructive` button under the
                // default style — the system paints it its own red and ignores
                // the tint, which is why this was the one hue in the app that
                // was not `FTLColor`. The role stays for the accessibility
                // semantics; `.plain` is what lets the token win.
                Button("Sign out", role: .destructive) {
                    auth.signOut()
                    onDone()
                }
                .buttonStyle(.plain)
                .font(FTLTypography.rowTitle)
                .foregroundStyle(FTLColor.destructive)
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

    private var dailyBudgetPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            SectionLabel(text: "Daily Budget")
            
            PanelCard {
                PanelRow(showsDivider: dailyBudgetEnabled) {
                    Toggle("Enable Daily Budget", isOn: Binding(
                        get: { dailyBudgetEnabled },
                        set: { enabled in
                            dailyBudgetEnabled = enabled
                            if !enabled {
                                DailyBudgetManager.amount = nil
                                dailyBudgetDigits = ""
                            }
                        }
                    ))
                    .font(FTLTypography.rowTitle)
                    .foregroundStyle(FTLColor.textPrimary)
                    .tint(FTLColor.accent)
                }
                
                if dailyBudgetEnabled {
                    PanelRow(showsDivider: true) {
                        HStack {
                            Text("Limit (IDR)")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Spacer()
                            TextField("e.g. 150000", text: Binding(
                                get: { dailyBudgetDigits },
                                set: { newValue in
                                    let digits = String(newValue.filter { $0.isNumber })
                                    dailyBudgetDigits = digits
                                    DailyBudgetManager.amount = digits.isEmpty ? nil : Int(digits)
                                }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(FTLTypography.amountEmphasis)
                            .foregroundStyle(FTLColor.accent)
                        }
                    }
                    
                    PanelRow(showsDivider: false) {
                        Toggle("Roll over unspent to next day", isOn: Binding(
                            get: { dailyBudgetRollsOver },
                            set: { rollsOver in
                                dailyBudgetRollsOver = rollsOver
                                DailyBudgetManager.rollsOver = rollsOver
                            }
                        ))
                        .font(FTLTypography.body)
                        .foregroundStyle(FTLColor.textPrimary)
                        .tint(FTLColor.accent)
                    }
                }
            }
            
            Text("Replaces the monthly ceiling math with a strict daily allowance.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }
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

                if !missingCategories.isEmpty {
                    PanelRow(showsDivider: true) {
                        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
                            Text("Used in transactions, not in your buckets")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                            ForEach(missingCategories, id: \.self) { categoryID in
                                HStack {
                                    Text(categoryID.rawValue.capitalized)
                                        .font(FTLTypography.caption)
                                        .foregroundStyle(FTLColor.textPrimary)
                                    Spacer()
                                    Button("Add") {
                                        Task { await addMissingCategory(categoryID) }
                                    }
                                    .font(FTLTypography.captionSmall)
                                    .foregroundStyle(FTLColor.accent)
                                }
                            }
                        }
                    }
                }

                PanelRow(showsDivider: true) {
                    Button {
                        isShowingIncomeSplit = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.pie.fill")
                                .foregroundStyle(FTLColor.accent)
                            Text("Set Up by Income")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
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

            // Not a DEBUG-only concern: if the queue is running in memory, rows
            // awaiting approval die with the app and nothing else on screen
            // would say so.
            if !environment.isProvisionalStorePersistent {
                Text("The approval queue is running in memory this session — its rows will not survive a relaunch. Approve anything waiting before you quit.")
                    .font(FTLTypography.captionSmall)
                    .foregroundStyle(FTLColor.budgetOverCeiling)
            }
        }
    }

    // MARK: - Home Screen Widgets Panel

    private var widgetsPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.sm) {
            PanelCard {
                PanelRow(showsDivider: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FTLColor.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Budget of the Day")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text("Daily allowance, spent today, remaining balance & progress")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                        }
                        Spacer()
                    }
                }

                PanelRow(showsDivider: true) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(FTLColor.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Spending")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text("Quick shortcuts (+25k, +50k, +100k) & keypad link")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                        }
                        Spacer()
                    }
                }

                PanelRow(showsDivider: widgetRefreshMessage != nil) {
                    Button {
                        let snapshot = WidgetDataManager.shared.loadSnapshot()
                        WidgetDataManager.shared.saveSnapshot(snapshot)
                        widgetRefreshMessage = "Widgets refreshed at \(Date.now.formatted(date: .omitted, time: .standard))"
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(FTLColor.accent)
                            Text("Refresh Widget Timelines")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let widgetRefreshMessage {
                    PanelRow(showsDivider: false) {
                        Text(widgetRefreshMessage)
                            .font(FTLTypography.captionSmall)
                            .foregroundStyle(FTLColor.accent)
                    }
                }
            }

            Text("Both widgets support Small, Medium, and Lock Screen accessories. Add them from your iOS Home Screen or Lock Screen widget gallery.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    #if DEBUG
    private var debugPanel: some View {
        PanelCard {
            debugRow("Google API harness", .harness, showsDivider: true)
            debugRow("Evaluation", .evaluation, showsDivider: true)

            // Gmail rail — Stage 1 #4
            PanelRow(showsDivider: true) {
                Button {
                    Task { await syncMail() }
                } label: {
                    HStack(spacing: 8) {
                        if isSyncingMail {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "tray.and.arrow.down")
                                .foregroundStyle(FTLColor.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fetch receipts from Gmail")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Text(mailSyncResult ?? "blu only. Parsed rows wait in the approval queue.")
                                .font(FTLTypography.captionSmall)
                                .foregroundStyle(FTLColor.textQuaternary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSyncingMail)
            }

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

    // MARK: - Background Panel

    /// One toggle, and copy that does not promise what iOS will not deliver.
    ///
    /// Off by default: scheduling background work and posting notifications are
    /// both things to ask for. Turning it on is also where notification
    /// permission is requested — a prompt cannot be shown from a background
    /// task, so this is the only place it can happen.
    private var backgroundPanel: some View {
        VStack(alignment: .leading, spacing: FTLSpacing.labelGap) {
            PanelCard {
                PanelRow(showsDivider: false) {
                    // A Button row, not a `Toggle`. The switch rendered fine in
                    // `PanelRow` and swallowed every tap — its hit area does not
                    // survive that container, and rather than keep fighting it
                    // this follows the idiom every other row on this screen
                    // already uses, including "Mode · Assist" directly below:
                    // tap the row, state on the trailing edge.
                    Button {
                        Task { await setBackgroundRefresh(!isBackgroundRefreshOn) }
                    } label: {
                        HStack {
                            Text("Fetch in the background")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Spacer()
                            Text(isBackgroundRefreshOn ? "On" : "Off")
                                .font(FTLTypography.body)
                                .foregroundStyle(isBackgroundRefreshOn ? FTLColor.textPrimary : FTLColor.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(backgroundHint)
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)

            PanelCard {
                PanelRow(showsDivider: isDigestOn) {
                    Button {
                        Task { await setDigest(!isDigestOn) }
                    } label: {
                        HStack {
                            Text("Daily reminder")
                                .font(FTLTypography.rowTitle)
                                .foregroundStyle(FTLColor.textPrimary)
                            Spacer()
                            Text(isDigestOn ? digestTime.formatted(.dateTime.hour().minute()) : "Off")
                                .font(FTLTypography.body)
                                .foregroundStyle(isDigestOn ? FTLColor.textPrimary : FTLColor.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if isDigestOn {
                    PanelRow(showsDivider: false) {
                        DatePicker("Time", selection: Binding(
                            get: { digestTime },
                            set: { newTime in
                                digestTime = newTime
                                Task { await setDigestTime(newTime) }
                            }
                        ), displayedComponents: .hourAndMinute)
                        .font(FTLTypography.rowTitle)
                        .foregroundStyle(FTLColor.textPrimary)
                        .tint(FTLColor.accent)
                    }
                }
            }
            .padding(.top, FTLSpacing.md)

            Text("Fires at the hour you pick, every day, and only when something is actually waiting. Unlike the fetch above, this one iOS does keep to the minute.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)

            Text("For a fetch at an exact time, add \"Check for Receipts\" to a Time of Day automation in Shortcuts — that is the only scheduling iOS lets an app rely on.")
                .font(FTLTypography.captionSmall)
                .foregroundStyle(FTLColor.textQuaternary)
        }
    }

    private func setDigest(_ wanted: Bool) async {
        guard wanted else {
            NotificationSchedule.isEnabled = false
            NotificationSchedule.cancel()
            isDigestOn = false
            return
        }
        let granted = await BackgroundRefresh.requestAuthorization()
        notificationsDenied = !granted
        NotificationSchedule.isEnabled = true
        isDigestOn = true
        await refreshDigest()
    }

    private func setDigestTime(_ date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        if let hour = components.hour, let minute = components.minute {
            NotificationSchedule.hour = hour
            NotificationSchedule.minute = minute
            await refreshDigest()
        }
    }

    /// The reminder quotes a count, so it is re-pointed at the live queue every
    /// time it is touched — see `NotificationSchedule`.
    private func refreshDigest() async {
        let pending = (try? await environment.provisional.pending())?.count ?? 0
        await NotificationSchedule.refreshDigest(pendingCount: pending)
    }

    private var backgroundHint: String {
        if notificationsDenied {
            return "Notifications are turned off for FTL in iOS Settings. The fetch can still run, but nothing will tell you about it."
        }
        return "Notifies you when receipts arrive. iOS decides when to run this — usually when you tend to open the app, never in Low Power Mode, and not at all if the app is force-quit. Opening FTL always checks immediately, which is the reliable path."
    }

    private func setBackgroundRefresh(_ wanted: Bool) async {
        guard wanted else {
            BackgroundRefresh.isEnabled = false
            BackgroundRefresh.cancel()
            isBackgroundRefreshOn = false
            return
        }
        // Permission first: enabling a fetch whose whole point is to tell you
        // something, without the ability to tell you, is a dead switch.
        let granted = await BackgroundRefresh.requestAuthorization()
        notificationsDenied = !granted
        BackgroundRefresh.isEnabled = true
        BackgroundRefresh.schedule()
        isBackgroundRefreshOn = true
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
            .background(
                FTLColor.sheetBackground
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
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
            .background(
                FTLColor.sheetBackground
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
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
            await loadMissingCategories()
        } catch {
            syncStatus = "Failed to load budgets: \(error.localizedDescription)"
        }
    }

    /// Categories a transaction actually uses but that have no budget row at
    /// all — most commonly rows migrated from an old month-named tab, which
    /// stamp a categoryID straight from that sheet's free-text column
    /// (`SheetsLedgerStore.importLegacyMonthTabs`) with no budgets-tab row ever
    /// created to go with it. Real, silently un-budgeted spend, not a display
    /// glitch — worth surfacing rather than letting it sit invisible.
    private func loadMissingCategories() async {
        guard let root = budgetTree.first else {
            missingCategories = []
            return
        }
        let known = Self.flattenIDs(root)
        do {
            let all = try await environment.ledger.all()
            let used = Set(all.filter { $0.kind == .spend }.compactMap(\.categoryID))
            missingCategories = used.subtracting(known).sorted { $0.rawValue < $1.rawValue }
        } catch {
            // Best-effort: leave whatever the prompt already showed rather than
            // blank it over a transient read failure.
        }
    }

    private static func flattenIDs(_ node: BudgetNode) -> Set<CategoryID> {
        node.children.reduce(into: [node.id]) { set, child in
            set.formUnion(flattenIDs(child))
        }
    }

    /// One-tap fix for a row in `missingCategories` — adds it under Total with
    /// no ceiling yet, using the SAME id the transactions already carry (not a
    /// freshly re-slugged name) so it lines up exactly.
    private func addMissingCategory(_ categoryID: CategoryID) async {
        let cat = SpendCategory(
            id: categoryID,
            name: categoryID.rawValue.capitalized,
            parentID: CategoryID(rawValue: "total")
        )
        do {
            try await environment.budgets.addCategory(cat, under: CategoryID(rawValue: "total"))
            await loadBudgets()
        } catch {
            syncStatus = "Failed to add \(categoryID.rawValue): \(error.localizedDescription)"
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
        // Only the spaces need handling here — CategoryID trims and lowercases.
        let slug = trimmed.replacingOccurrences(of: " ", with: "_")
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
    private func syncMail() async {
        guard let rail = environment.makeGmailRail() else {
            mailSyncResult = "Not available in sample mode."
            return
        }
        isSyncingMail = true
        mailSyncResult = "Checking Gmail…"
        do {
            let result = try await rail.sync()
            mailSyncResult = result.summary
        } catch {
            mailSyncResult = "Failed: \(error.localizedDescription)"
        }
        isSyncingMail = false
    }

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
