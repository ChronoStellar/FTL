import SwiftUI
import Observation

@Observable @MainActor
final class CalendarViewModel {
    private let calc: CalcTool
    private let calendar: Calendar
    
    var dailyTotals: [Date: Money] = [:]
    
    init(calc: CalcTool, calendar: Calendar = .current) {
        self.calc = calc
        self.calendar = calendar
    }
    
    func load(interval: DateInterval) async {
        do {
            let txs = try await calc.transactions(in: interval, categoryID: nil, limit: 10000)
            var totals: [Date: Int] = [:]
            var currency: CurrencyCode? = nil
            
            for tx in txs {
                guard tx.countsTowardBudget else { continue }
                let startOfDay = calendar.startOfDay(for: tx.date)
                totals[startOfDay, default: 0] += tx.amount.minorUnits
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
        } catch {
            print("Calendar view load error: \(error)")
        }
    }
}
