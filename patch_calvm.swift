import Foundation

let file = "FTL/viewModel/CalendarViewModel.swift"
var content = try String(contentsOfFile: file)

let search = """
    var dailyTotals: [Date: Money] = [:]
"""
let replace = """
    var dailyTotals: [Date: Money] = [:]
    var dailyEmergencyTotals: [Date: Money] = [:]
"""
content = content.replacingOccurrences(of: search, with: replace)

let loopSearch = """
            for tx in txs {
                guard tx.countsTowardBudget else { continue }
                let startOfDay = calendar.startOfDay(for: tx.date)
                totals[startOfDay, default: 0] += tx.amount.minorUnits
                if currency == nil {
                    currency = tx.amount.currency
                }
            }
"""
let loopReplace = """
            var eTotals: [Date: Int] = [:]
            for tx in txs {
                guard tx.countsTowardBudget || tx.categoryID == .emergency else { continue }
                let startOfDay = calendar.startOfDay(for: tx.date)
                
                if tx.categoryID == .emergency {
                    eTotals[startOfDay, default: 0] += tx.amount.minorUnits
                }
                // Also add it to totals if it counts toward budget
                if tx.countsTowardBudget {
                    totals[startOfDay, default: 0] += tx.amount.minorUnits
                }
                
                if currency == nil {
                    currency = tx.amount.currency
                }
            }
"""
content = content.replacingOccurrences(of: loopSearch, with: loopReplace)

let resultSearch = """
            self.dailyTotals = result
        } catch {
"""
let resultReplace = """
            self.dailyTotals = result
            
            var eResult: [Date: Money] = [:]
            for (date, minor) in eTotals {
                eResult[date] = Money(minorUnits: minor, currency: c)
            }
            self.dailyEmergencyTotals = eResult
        } catch {
"""
content = content.replacingOccurrences(of: resultSearch, with: resultReplace)

try content.write(toFile: file, atomically: true, encoding: .utf8)
