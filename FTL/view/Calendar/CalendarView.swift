import SwiftUI

struct CalendarView: View {
    let environment: AppEnvironment
    let interval: DateInterval
    @State private var viewModel: CalendarViewModel
    
    init(environment: AppEnvironment, interval: DateInterval) {
        self.environment = environment
        self.interval = interval
        _viewModel = State(wrappedValue: environment.makeCalendarViewModel())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: FTLSpacing.lg) {
                let calendar = Calendar.current
                let monthStart = interval.start
                let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
                
                let firstWeekday = calendar.component(.weekday, from: monthStart)
                let leadingEmptySpaces = firstWeekday - calendar.firstWeekday
                let spaces = leadingEmptySpaces < 0 ? leadingEmptySpaces + 7 : leadingEmptySpaces
                
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                
                // Weekday headers
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(FTLTypography.captionSmall)
                            .foregroundStyle(FTLColor.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(0..<spaces, id: \.self) { _ in
                        Color.clear.aspectRatio(1, contentMode: .fit)
                    }
                    
                    ForEach(1...daysInMonth, id: \.self) { day in
                        if let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) {
                            let isToday = calendar.isDateInToday(date)
                            let total = viewModel.dailyTotals[calendar.startOfDay(for: date)]
                            
                            VStack(spacing: 2) {
                                Text("\(day)")
                                    .font(FTLTypography.caption)
                                    .foregroundStyle(isToday ? FTLColor.accent : FTLColor.textPrimary)
                                    .padding(.top, 4)
                                
                                if let money = total {
                                    Text(MoneyFormatter.compact(money))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(FTLColor.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aspectRatio(0.8, contentMode: .fill)
                            .background(FTLColor.glassFill, in: RoundedRectangle(cornerRadius: 6))
                            .overlay {
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(isToday ? FTLColor.accent.opacity(0.5) : FTLColor.controlBorder, lineWidth: isToday ? 1 : 0.5)
                            }
                        }
                    }
                }
            }
            .padding(FTLSpacing.screenMargin)
        }
        .background(FTLColor.ground)
        .navigationTitle("Calendar")
        .task(id: interval) {
            await viewModel.load(interval: interval)
        }
    }
}

// Extension to format compact numbers in Calendar
extension MoneyFormatter {
    static func compact(_ money: Money) -> String {
        let val = money.minorUnits
        if val >= 1_000_000 {
            let m = Double(val) / 1_000_000.0
            return String(format: "%.1fM", m)
        } else if val >= 1_000 {
            let k = Double(val) / 1_000.0
            // if it's like 50.0k, we could just do 50k
            if val % 1_000 == 0 {
                return "\(val / 1_000)k"
            }
            return String(format: "%.1fk", k)
        }
        return "\(val)"
    }
}
