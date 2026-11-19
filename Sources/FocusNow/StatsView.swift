import Charts
import FocusNowCore
import SwiftUI

/// The stats window: five totals that double as the range picker, a chart of
/// the selected period, and the sessions in the selected bar (or today).
struct StatsView: View {
    let model: StatsViewModel
    @Bindable var preferences: CalendarPreferences

    static let displaySwitchIdentifier = "stats-display"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            tiles
            header
            if preferences.statsDisplay.showsCalendar(for: model.range) {
                FocusCalendarView(model: model, uses24Hour: FocusCalendarView.systemUses24Hour)
                    .frame(maxHeight: .infinity)
            } else {
                chart
                    .frame(minHeight: 170, maxHeight: 220)
                sessionList
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            ForEach(StatsRange.allCases, id: \.self) { range in
                Button { model.range = range } label: { tile(for: range) }
                    .buttonStyle(TileButtonStyle(selected: model.range == range))
            }
        }
    }

    private func tile(for range: StatsRange) -> some View {
        let value = model.tiles[range] ?? .init(focusSeconds: 0, sessionCount: 0)
        let secondary = range == .day
            ? "of \(TimeFormat.duration(model.todayGoalSeconds)) goal"
            : "\(value.sessionCount) \(value.sessionCount == 1 ? "session" : "sessions")"
        return VStack(alignment: .leading, spacing: 2) {
            Text(range.title).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(TimeFormat.duration(value.focusSeconds))
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(secondary).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            if model.canPageBack || model.canPageForward {
                HStack(spacing: 2) {
                    Button { model.pageBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.canPageBack)
                        .accessibilityLabel("Previous period")
                    Button { model.pageForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canPageForward)
                        .accessibilityLabel("Next period")
                }
                .buttonStyle(PressableButtonStyle(compact: true))
            }
            Text(periodTitle).font(.system(size: 13, weight: .medium)).monospacedDigit()
            Spacer()
            if model.range != .day {
                Text(summaryText).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
            if StatsDisplay.offersCalendar(for: model.range) {
                Picker("Stats view", selection: $preferences.statsDisplay) {
                    Text("Chart").tag(StatsDisplay.chart)
                    Text("Calendar").tag(StatsDisplay.calendar)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier(Self.displaySwitchIdentifier)
            }
        }
    }

    private var summaryText: String {
        let s = model.summary
        let average = "Daily average \(TimeFormat.duration(s.dailyAverageSeconds))"
        guard model.range == .week || model.range == .month else { return average }
        return "\(average) · Goal met \(s.goalMetDays) of \(s.elapsedDays) \(s.elapsedDays == 1 ? "day" : "days")"
    }

    private var periodTitle: String {
        let i = model.interval
        let last = i.end.addingTimeInterval(-1)
        switch model.range {
        case .day: return i.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week: return DateIntervalFormatter.weekTitle.string(from: i.start, to: last)
        case .month: return i.start.formatted(.dateTime.month(.wide).year())
        case .year: return i.start.formatted(.dateTime.year())
        case .allTime: return "Since " + i.start.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    // MARK: Chart

    private var barUnit: Calendar.Component {
        guard let first = model.buckets.first else { return .day }
        let length = first.interval.duration
        if length <= 3700 { return .hour }
        if length <= 90_000 { return .day }
        if length <= 32 * 86_400 { return .month }
        return .year
    }

    private var chart: some View {
        let unit = barUnit
        let now = Date()
        let goal = model.buckets.last?.goalSeconds
        return Chart {
            ForEach(model.buckets) { bucket in
                BarMark(
                    x: .value("Period", bucket.interval.start, unit: unit),
                    y: .value("Hours", Double(bucket.focusSeconds) / 3600))
                .foregroundStyle(Theme.focus.opacity(barOpacity(bucket, now: now)))
                .cornerRadius(3)
            }
            if let goal {
                RuleMark(y: .value("Goal", Double(goal) / 3600))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("\(TimeFormat.duration(goal)) goal").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let h = value.as(Double.self) { Text(hourLabel(h)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: unit == .hour ? 3 : (unit == .day && model.range == .month ? 5 : 1))) { _ in
                AxisValueLabel(format: axisFormat(unit), centered: true)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in select(at: location, proxy: proxy, geo: geo) }
            }
        }
        .animation(nil, value: model.interval)
    }

    private func barOpacity(_ bucket: StatsBucket, now: Date) -> Double {
        if let selected = model.selectedBucketID { return bucket.id == selected ? 1 : 0.35 }
        return bucket.interval.contains(now) ? 1 : 0.6
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plot = proxy.plotFrame else { return }
        let x = location.x - geo[plot].origin.x
        guard let date: Date = proxy.value(atX: x),
              let bucket = model.buckets.first(where: { $0.interval.start <= date && date < $0.interval.end }) else {
            model.selectedBucketID = nil
            return
        }
        model.selectedBucketID = model.selectedBucketID == bucket.id ? nil : bucket.id
    }

    private func hourLabel(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }

    private func axisFormat(_ unit: Calendar.Component) -> Date.FormatStyle {
        switch unit {
        case .hour: .dateTime.hour()
        case .day: model.range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day()
        case .month: .dateTime.month(.abbreviated)
        default: .dateTime.year()
        }
    }

    // MARK: Sessions

    private var listTitle: String {
        let i = model.listInterval
        let length = i.duration
        if length <= 3700 { return i.start.formatted(.dateTime.weekday(.wide).hour()) }
        if length <= 90_000 { return i.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
        if length <= 32 * 86_400 { return i.start.formatted(.dateTime.month(.wide).year()) }
        return i.start.formatted(.dateTime.year())
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions · \(listTitle)").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.listedSessions.isEmpty {
                Text("No focus sessions")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.listedSessions.reversed()) { session in
                            SessionRow(session: session, showsDate: model.listInterval.duration > 90_000)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SessionRow: View {
    let session: SessionRecord
    let showsDate: Bool

    var body: some View {
        HStack {
            Text(showsDate
                 ? session.startedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                 : session.startedAt.formatted(.dateTime.hour().minute()))
                .monospacedDigit()
            Spacer()
            Text(detail).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.system(size: 13))
        .padding(.vertical, 7)
    }

    private var detail: String {
        let length = TimeFormat.duration(session.activeSeconds) + " focus"
        return session.outcome == .endedEarly ? length + " · ended early" : length
    }
}

/// A stats tile: a card that shows a focus-coloured border when selected.
private struct TileButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.focus : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? Theme.pressScale : 1)
            .animation(.easeOut(duration: Theme.pressDuration), value: configuration.isPressed)
    }
}

extension StatsRange {
    var title: String {
        switch self {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        case .year: "This year"
        case .allTime: "All time"
        }
    }
}

extension DateIntervalFormatter {
    @MainActor static let weekTitle: DateIntervalFormatter = {
        let f = DateIntervalFormatter()
        f.dateTemplate = "MMMd"
        return f
    }()
}
