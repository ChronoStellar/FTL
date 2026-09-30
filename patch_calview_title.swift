import Foundation

let file = "FTL/view/Calendar/CalendarView.swift"
var content = try String(contentsOfFile: file)

content = content.replacingOccurrences(of: "        .navigationTitle(\"Calendar\")\n", with: "")

try content.write(toFile: file, atomically: true, encoding: .utf8)
