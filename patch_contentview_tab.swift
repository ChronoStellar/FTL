import Foundation

let file = "FTL/view/ContentView.swift"
var content = try String(contentsOfFile: file)

let searchEnum = """
    enum Tab {
        case home, calendar
    }
"""
let replaceEnum = """
    enum Tab {
        case home, calendar, analyze
    }
"""
content = content.replacingOccurrences(of: searchEnum, with: replaceEnum)

let searchTab = """
            NavigationStack(path: $calendarPath) {
                if let interval = home.month?.interval {
                    CalendarView(environment: environment, interval: interval)
                        .toolbar { homeToolbar }
                        .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(Tab.calendar)
        }
"""
let replaceTab = """
            NavigationStack(path: $calendarPath) {
                if let interval = home.month?.interval {
                    CalendarView(environment: environment, interval: interval)
                        .toolbar { homeToolbar }
                        .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    ProgressView()
                }
            }
            .tabItem { Label("Calendar", systemImage: "calendar") }
            .tag(Tab.calendar)
            
            NavigationStack {
                AnalyzeView(environment: environment)
                    .toolbar { homeToolbar }
                    .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Analyze", systemImage: "sparkles") }
            .tag(Tab.analyze)
        }
"""
content = content.replacingOccurrences(of: searchTab, with: replaceTab)

try content.write(toFile: file, atomically: true, encoding: .utf8)
