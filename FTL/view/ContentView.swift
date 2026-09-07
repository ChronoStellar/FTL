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

    @State private var home: HomeViewModel
    @State private var path: [Route] = []
    @State private var sheet: SheetRoute?

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
                onOpenQueue: { sheet = .queue }
            )
            .background(GlowBackground())
            .navigationDestination(for: Route.self, destination: destination)
            .toolbar { homeToolbar }
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(FTLColor.textTertiary)
        .task { await home.load() }
        .sheet(item: $sheet, content: sheetContent)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // The wordmark doubles as the way into Settings. The design has no
            // other affordance for it, and burying it behind a gesture would make
            // Sign out unreachable.
            Button { sheet = .settings } label: {
                Text("FTL")
                    .font(FTLTypography.wordmark)
                    .tracking(FTLTypography.wordmarkTracking)
                    .foregroundStyle(FTLColor.textTertiary)
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
            Button { sheet = .add } label: {
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
            GoalScreen(environment: environment)
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
            ApprovalQueueScreen(environment: environment, onDone: { sheet = nil })
                .onDisappear { Task { await home.load() } }

        case .add:
            AddSpendScreen(
                environment: environment,
                interval: home.month?.interval ?? .init(start: .now, duration: 0),
                onCancel: { sheet = nil },
                onCommit: {
                    sheet = nil
                    Task { await home.load() }
                }
            )

        case .settings:
            SettingsView(environment: environment, onDone: {
                sheet = nil
                Task { await home.load(forceReload: true) }
            })
        }
    }

    // MARK: - Routes

    enum Route: Hashable {
        case bucket(id: CategoryID, name: String)
        case goal
    }

    enum SheetRoute: String, Identifiable {
        case months, queue, add, settings
        var id: String { rawValue }
    }
}
