import Foundation

let file = "FTL/view/ContentView.swift"
var content = try String(contentsOfFile: file)

let search = """
            NavigationStack(path: $calendarPath) {
                if let interval = home.month?.interval {
                    CalendarView(environment: environment, interval: interval)
                } else {
                    ProgressView()
                }
            }
"""
let replace = """
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
"""
content = content.replacingOccurrences(of: search, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
