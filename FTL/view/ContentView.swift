//
//  ContentView.swift
//  FTL — view
//
//  The signed-in shell. One NavigationStack — Home pushes to a bucket or the
//  goal — plus three sheets: months, the approval queue, and add spend.
//
//  No tab bar: the design puts the month in the title as a menu, the queue behind
//  a card on Home, and everything else one push deep.
//

import SwiftUI

struct ContentView: View {
    let environment: AppEnvironment

    /// Drives the one automatic thing in the app — see `AutoSync`. Watched
    /// here, on the signed-in shell, because that is the narrowest place that
    /// is only alive when there is a mailbox to sync and a queue to put rows in.
    @Environment(\.scenePhase) private var scenePhase

    @State private var home: HomeViewModel
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?

    /// Shown once: whether the income-split onboarding prompt has already
    /// appeared (skipped or completed) on this device. It stays reachable from
    /// Settings → Budget Ceilings afterwards — this only stops it nagging.
    @AppStorage("hasShownIncomeSplitOnboarding") private var hasShownIncomeSplitOnboarding = false

    init(environment: AppEnvironment) {
        self.environment = environment
        _home = State(wrappedValue: environment.makeHomeViewModel())
    }

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                viewModel: home,
                onOpenBucket: { path.append(.bucket(id: $0.id, name: $0.node.name)) },
                onOpenGoal: { path.append(.goal) },
                onOpenQueue: { sheet = .queue },
                onEditTransaction: { sheet = .edit($0) }
            )
            .background(GlowBackground())
            .navigationDestination(for: Route.self, destination: destination)
            .toolbar { homeToolbar }
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        // Also fire-and-forget, and deliberately its own `.task` rather than
        // chained after `syncMail` below: discovery fetches its own 180-day
        // window independently of the ordinary sync, nothing on screen is
        // waiting on it, and `DiscoverySync` bounds itself to one attempt per
        // launch on its own — see `DiscoverySync`.
        .task { _ = await environment.discoverySync.runIfDue() }
        .tint(FTLColor.textTertiary)
        .task {
            await home.load()
            offerIncomeSplitIfNeeded()
            // First launch always checks. The throttle only suppresses the
            // REPEAT foregrounds below, so opening the app is always a fresh
            // look — which is the whole behaviour a person notices.
            await syncMail(force: true)
        }
        // Home sits behind every pushed screen, and a bucket can change the
        // ledger under it — an amount corrected, a row retagged out of the
        // bucket, a row deleted. The pushed screen reloads itself; the hero
        // total, the meters and the recent list behind it do not, so popping
        // back used to reveal a Home describing the ledger as it was before
        // the edit.
        //
        // `load()` rather than `load(forceReload:)`: whatever wrote already
        // invalidated the store's cache, so this re-reads without a second
        // round trip to the Sheet. Guarded on the pop so a push costs nothing.
        .onChange(of: path) { previous, current in
            guard current.isEmpty, !previous.isEmpty else { return }
            Task { await home.load() }
        }
        // Coming back to the app is the trigger. Throttled inside `AutoSync`,
        // so flicking between apps costs nothing.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await syncMail() }
        }
        .sheet(item: $sheet, content: sheetContent)
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    /// Fetches in the background and refreshes Home only if something landed.
    ///
    /// Reloading unconditionally would re-read the whole Sheet on every
    /// foreground to change nothing. `syncIfDue` already knows whether the queue
    /// grew, so that is what decides.
    private func syncMail(force: Bool = false) async {
        guard await environment.autoSync.syncIfDue(force: force) else { return }
        await home.load()
    }

    /// Once, live-only, and only when there's real nothing set yet — a Total
    /// ceiling of zero with buckets already under it. Fixture data in
    /// `.sample()` isn't the user's income to ask about, and a sheet that
    /// already has ceilings has nothing this prompt would add.
    private func offerIncomeSplitIfNeeded() {
        guard environment.isLive, !hasShownIncomeSplitOnboarding,
              sheet == nil,
              let root = home.buckets.first, !root.node.children.isEmpty,
              root.node.ceiling.minorUnits == 0
        else { return }
        sheet = .incomeSplit
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // The wordmark doubles as the way into Settings. The design has no
            // other affordance for it, and burying it behind a gesture would make
            // Sign out unreachable.
            Button { sheet = .settings } label: {
                HStack(spacing: 7) {
                    FTLMark(width: FTLMarkSize.wordmark, tint: FTLColor.textTertiary)
                    Text("FTL")
                        .font(FTLTypography.wordmark)
                        .tracking(FTLTypography.wordmarkTracking)
                        .foregroundStyle(FTLColor.textTertiary)
                }
                // The bar hands the leading item a width that fitted the
                // wordmark alone; the mark pushed it over and the wordmark
                // silently truncated to "F". There is room either side of the
                // month pill — the item just has to refuse to be squeezed.
                .fixedSize()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .principal) {
            Button { sheet = .months } label: {
                HStack(spacing: 5) {
                    Text(home.monthTitle)
                        .font(FTLTypography.navTitle)
                        .foregroundStyle(FTLColor.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FTLColor.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(FTLColor.glassFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Month: \(home.monthTitle). Change month")
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            Button { sheet = .add() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(FTLColor.textPrimary)
                    .frame(width: FTLSpacing.minTapTarget, height: FTLSpacing.minTapTarget)
                    .background(FTLColor.controlFill, in: Circle())
                    .overlay { Circle().strokeBorder(FTLColor.controlBorder, lineWidth: 0.5) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add spend")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case let .bucket(id, name):
            BucketScreen(
                environment: environment,
                categoryID: id,
                name: name,
                interval: home.month?.interval ?? .init(start: .now, duration: 0)
            )
        case .goal:
            Text("Goal")
        }
    }

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .months:
            MonthPickerSheet(
                months: home.months,
                selectedID: home.selectedMonthID,
                onPick: { month in
                    sheet = nil
                    Task { await home.selectMonth(month) }
                }
            )

        case .queue:
            // Two refreshes, and they are not redundant.
            //
            // `onSettled` fires per approval while the sheet is still open, so
            // the hero total and the bucket meters behind it are already right
            // when it closes. It is the cheap one: `append` invalidates the
            // ledger cache, so the next read is fresh without forcing anything.
            //
            // `onDisappear` still forces a reload on the way out, which covers
            // everything that changed the sheet from somewhere else — a fetch
            // that ran while the queue was up, an amend, a failed write.
            ApprovalQueueScreen(
                environment: environment,
                onDone: { sheet = nil },
                onSettled: { Task { await home.load(forceReload: true) } }
            )
            .onDisappear { Task { await home.load(forceReload: true) } }

        case .add(let initialAmount):
            AddSpendScreen(
                environment: environment,
                interval: home.month?.interval ?? .init(start: .now, duration: 0),
                initialAmount: initialAmount,
                onCancel: { sheet = nil },
                onCommit: {
                    sheet = nil
                    Task { await home.load(forceReload: true) }
                }
            )

        case .settings:
            SettingsView(environment: environment, onDone: {
                sheet = nil
                Task { await home.load() }
            })

        case .edit(let transaction):
            EditTransactionScreen(
                environment: environment,
                transaction: transaction,
                onCancel: { sheet = nil },
                onSave: { edited in
                    sheet = nil
                    Task { await home.updateTransaction(edited) }
                },
                onDelete: {
                    sheet = nil
                    Task { await home.deleteTransaction(transaction) }
                }
            )

        case .incomeSplit:
            IncomeSplitScreen(
                environment: environment,
                interval: home.month?.interval ?? .init(start: .now, duration: 0),
                onSkip: {
                    hasShownIncomeSplitOnboarding = true
                    sheet = nil
                },
                onSaved: {
                    hasShownIncomeSplitOnboarding = true
                    sheet = nil
                    Task { await home.load() }
                }
            )
        }
    }

    // MARK: - Deep Linking

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "ftl" else { return }
        switch url.host {
        case "add":
            var initialAmount: Int? = nil
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let queryItems = components.queryItems,
               let amountStr = queryItems.first(where: { $0.name == "amount" })?.value,
               let parsed = Int(amountStr) {
                initialAmount = parsed
            }
            sheet = .add(initialAmount: initialAmount)
        case "home", "budget", "daily":
            sheet = nil
        default:
            break
        }
    }

    // MARK: - Routes

    enum Route: Hashable {
        case bucket(id: CategoryID, name: String)
        case goal
    }

    enum SheetRoute: Identifiable {
        case months, queue
        case add(initialAmount: Int? = nil)
        case settings, incomeSplit
        /// Carries the row, so the editor's view model is built from it once —
        /// see `EditTransactionScreen`. This is why the enum can no longer be
        /// `String`-backed.
        case edit(LedgerTransaction)

        var id: String {
            switch self {
            case .months: return "months"
            case .queue: return "queue"
            case .add(let initialAmount):
                if let initialAmount {
                    return "add-\(initialAmount)"
                }
                return "add"
            case .settings: return "settings"
            case .incomeSplit: return "incomeSplit"
            case .edit(let transaction): return "edit-\(transaction.id.uuidString)"
            }
        }
    }
}
