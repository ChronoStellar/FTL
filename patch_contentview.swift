import Foundation

let path = "FTL/view/ContentView.swift"
let content = try! String(contentsOfFile: path)
let newContent = content.replacingOccurrences(of: """
    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
""", with: """
    enum Tab {
        case home, calendar
    }
    @State private var selectedTab: Tab = .home
    @State private var calendarPath: [Route] = []

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $path) {
                HomeView(
""")

let newContent2 = newContent.replacingOccurrences(of: """
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
        }
        // Also fire-and-forget, and deliberately its own `.task` rather than
""", with: """
            .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack(path: $calendarPath) {
                if let interval = home.month?.interval {
                    CalendarView(environment: environment, interval: interval)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(Tab.calendar)
        }
        // Also fire-and-forget, and deliberately its own `.task` rather than
""")

try! newContent2.write(toFile: path, atomically: true, encoding: .utf8)
