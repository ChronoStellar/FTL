import Foundation

let file = "FTL/view/Calendar/CalendarView.swift"
var content = try String(contentsOfFile: file)

let search = """
                            let isToday = calendar.isDateInToday(date)
                            let total = viewModel.dailyTotals[calendar.startOfDay(for: date)]
                            
                            VStack(spacing: 2) {
"""
let replace = """
                            let isToday = calendar.isDateInToday(date)
                            let total = viewModel.dailyTotals[calendar.startOfDay(for: date)]
                            let hasEmergency = viewModel.dailyEmergencyTotals[calendar.startOfDay(for: date)] != nil
                            
                            VStack(spacing: 2) {
"""
content = content.replacingOccurrences(of: search, with: replace)

let strokeSearch = """
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isToday ? FTLColor.accent.opacity(0.5) : FTLColor.controlBorder, lineWidth: isToday ? 1 : 0.5)
                            }
"""
let strokeReplace = """
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(hasEmergency ? Color.red : (isToday ? FTLColor.accent.opacity(0.5) : FTLColor.controlBorder), lineWidth: (hasEmergency || isToday) ? 1.5 : 0.5)
                            }
"""
content = content.replacingOccurrences(of: strokeSearch, with: strokeReplace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
