import Foundation

let file = "FTL/view/ContentView.swift"
var content = try String(contentsOfFile: file)

let search = """
            NavigationStack {
                AnalyzeView(environment: environment)
"""
let replace = """
            NavigationStack {
                if #available(iOS 27.0, macOS 27.0, *) {
                    AnalyzeView(environment: environment, interval: home.month?.interval ?? DateInterval(start: .now, end: .now))
                        .toolbar { homeToolbar }
                        .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    Text("Analyze requires iOS 27")
                }
            }
            .tabItem { Label("Analyze", systemImage: "sparkles") }
            .tag(Tab.analyze)
"""

// First, I need to remove the previous snippet to replace it properly
let exactSearch = """
            NavigationStack {
                AnalyzeView(environment: environment)
                    .toolbar { homeToolbar }
                    .toolbarBackground(FTLColor.navBackground, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Analyze", systemImage: "sparkles") }
            .tag(Tab.analyze)
"""

content = content.replacingOccurrences(of: exactSearch, with: replace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
