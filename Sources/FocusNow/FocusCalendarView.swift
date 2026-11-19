import Charts
import FocusNowCore
import SwiftUI

/// Stats' Calendar view: when the focus happened. Today and This week draw
/// each session as a block on an hours axis; This month lists each day's
/// focus periods.
struct FocusCalendarView: View {
    let model: StatsViewModel
    let uses24Hour: Bool

    /// Whether the system shows times on a 24-hour clock.
    static var systemUses24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    var body: some View {
        if model.range == .month {
            MonthGrid(model: model, uses24Hour: uses24Hour)
        } else if let span = model.hourSpan {
            Timeline(model: model, span: span, uses24Hour: uses24Hour)
        } else {
            Text("No focus sessions")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Today or This week: one column per day, morning at the top.
private struct Timeline: View {
    let model: StatsViewModel
    let span: HourSpan
    let uses24Hour: Bool

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        GeometryReader { geo in
            // Roughly the plot's height per hour, to decide which blocks have room for a label.
            let perHour = max(0, geo.size.height - 28) / CGFloat(span.last - span.first)
            Chart {
                ForEach(model.focusDays) { day in
                    ForEach(day.blocks, id: \.sessionID) { block in
                        // Plotted as negative hours so the earliest hour is at the top.
                        RectangleMark(
                            x: .value("Day", column(day)),
                            yStart: .value("Start", -block.startHour),
                            yEnd: .value("End", -block.endHour),
                            width: .ratio(0.86))
                        .foregroundStyle(Theme.focus)
                        .cornerRadius(3)
                        .annotation(position: .overlay, alignment: .topLeading) {
                            if CGFloat(block.endHour - block.startHour) * perHour >= 15 {
                                // The whole span when the column is wide enough, else its start.
                                ViewThatFits(in: .horizontal) {
                                    Text(text(block))
                                    Text(startText(block))
                                }
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.onFocus)
                                .lineLimit(1)
                                .padding(.leading, 4)
                                .padding(.top, 2)
                            }
                        }
                        .accessibilityLabel(column(day))
                        .accessibilityValue(text(block))
                    }
                }
            }
            .chartXScale(domain: model.focusDays.map(column))
            .chartXAxis {
                AxisMarks(position: .top) { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) { Text(header(for: name)) }
                    }
                }
            }
            .chartYScale(domain: -Double(span.last)...(-Double(span.first)))
            .chartYAxis {
                AxisMarks(position: .leading, values: hourMarks.map { -Double($0) }) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let y = value.as(Double.self) { Text(hourLabel(Int(-y))) }
                    }
                }
            }
        }
    }

    private var hourMarks: [Int] {
        let step = span.last - span.first > 12 ? 3 : (span.last - span.first > 7 ? 2 : 1)
        return Array(stride(from: span.first, through: span.last, by: step))
    }

    private func column(_ day: FocusDay) -> String {
        day.day.start.formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func header(for column: String) -> String {
        guard let day = model.focusDays.first(where: { self.column($0) == column }), day.focusSeconds > 0 else {
            return column
        }
        return "\(column) · \(TimeFormat.duration(day.focusSeconds))"
    }

    private func text(_ block: FocusBlock) -> String {
        PeriodFormat.text(FocusPeriod(start: block.start, end: block.end), calendar: calendar, uses24Hour: uses24Hour)
    }

    private func startText(_ block: FocusBlock) -> String {
        PeriodFormat.time(block.start, calendar: calendar, uses24Hour: uses24Hour)
    }

    private func hourLabel(_ hour: Int) -> String {
        if uses24Hour { return String(format: "%02d:00", hour % 24 == 0 && hour > 0 ? 24 : hour) }
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour % 24 < 12 ? "am" : "pm")"
    }
}

/// This month: a grid of days, each with its total and focus periods.
private struct MonthGrid: View {
    let model: StatsViewModel
    let uses24Hour: Bool

    private var calendar: Calendar { .autoupdatingCurrent }

    var body: some View {
        let days = Dictionary(model.focusDays.map { ($0.day.start, $0) }, uniquingKeysWith: { a, _ in a })
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(weekdayNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            // Each row gets its own days by value: SwiftUI may rerun a row's
            // contents after the range changes, when the model has no rows left.
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(Array(model.monthWeeks.enumerated()), id: \.offset) { _, week in
                    GridRow {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                            if let date {
                                DayCell(date: date, day: days[date], uses24Hour: uses24Hour)
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
        }
    }

    private var weekdayNames: [String] {
        let names = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(names[first...] + names[..<first])
    }
}

private struct DayCell: View {
    let date: Date
    let day: FocusDay?
    let uses24Hour: Bool

    private static let headerHeight: CGFloat = 16
    private static let lineHeight: CGFloat = 13

    private var periods: [String] {
        (day?.periods ?? []).map { PeriodFormat.text($0, calendar: .autoupdatingCurrent, uses24Hour: uses24Hour) }
    }

    var body: some View {
        GeometryReader { geo in
            let fit = max(0, Int((geo.size.height - Self.headerHeight - 6) / Self.lineHeight))
            let all = periods
            // When they don't all fit, the last line that fits says how many are left.
            let shown = all.count <= fit ? all.count : max(0, fit - 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(date.formatted(.dateTime.day()))
                        .foregroundStyle(Calendar.autoupdatingCurrent.isDateInToday(date)
                                         ? AnyShapeStyle(Theme.focus) : AnyShapeStyle(.secondary))
                    Spacer(minLength: 0)
                    if let seconds = day?.focusSeconds, seconds > 0 {
                        Text(TimeFormat.duration(seconds)).fontWeight(.semibold).monospacedDigit()
                    }
                }
                .font(.system(size: 11))
                .frame(height: Self.headerHeight)
                ForEach(all.prefix(shown), id: \.self) { line in
                    Text(line).frame(height: Self.lineHeight)
                }
                if shown < all.count {
                    Text("+\(all.count - shown)").foregroundStyle(.secondary).frame(height: Self.lineHeight)
                }
            }
            .font(.system(size: 10))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = date.formatted(.dateTime.month(.abbreviated).day())
        guard let seconds = day?.focusSeconds, seconds > 0 else { return "\(name), no focus" }
        return ([name, TimeFormat.duration(seconds)] + periods).joined(separator: ", ")
    }
}
