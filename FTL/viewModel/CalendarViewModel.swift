import SwiftUI
import Observation

@Observable @MainActor
final class CalendarViewModel {
    private let calc: CalcTool
    private let calendar: Calendar
    
    var dailyTotals: [Date: Money] = [:]
    var dailyEmergencyTotals: [Date: Money] = [:]
    
    init(calc: CalcTool, calendar: Calendar = .current) {
        self.calc = calc
        self.calendar = calendar
    }
    
    func load(interval: DateInterval) async {
        do {
            let txs = try await calc.transactions(in: interval, categoryID: nil, limit: 10000)
            var totals: [Date: Int] = [:]
            var currency: CurrencyCode? = nil
            
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
            
            // default to IDR if no spend
            let c = currency ?? .idr
            var result: [Date: Money] = [:]
            for (date, minor) in totals {
                result[date] = Money(minorUnits: minor, currency: c)
            }
            self.dailyTotals = result
            
            var eResult: [Date: Money] = [:]
            for (date, minor) in eTotals {
                eResult[date] = Money(minorUnits: minor, currency: c)
            }
            self.dailyEmergencyTotals = eResult
        } catch {
            print("Calendar view load error: \(error)")
        }
    }
}
