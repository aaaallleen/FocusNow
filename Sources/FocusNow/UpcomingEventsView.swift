import FocusNowCore
import SwiftUI

/// Today's remaining events under the timer: "Now  Standup  until 10:30",
/// then what's next, up to `rowLimit` rows and "+N more".
struct UpcomingEventsView: View {
    let model: CalendarModel
    let rowLimit: Int
    var onSetUp: () -> Void = {}

    @Environment(\.timerScale) private var scale

    static let rowIdentifier = "upcoming-row"
    private static let rowHeight: CGFloat = 18
    private static let moreHeight: CGFloat = 16
    private static let spacing: CGFloat = 4
    /// The hairline above the list and the space under it.
    private static let top: CGFloat = 9

    /// The height the list takes for `lines` rows (or one line of message) and
    /// maybe "+N more", at the page's `scale`. The page reserves it so nothing
    /// overlaps the ring.
    static func height(lines: Int, hasMore: Bool, scale: CGFloat = 1) -> CGFloat {
        (top + CGFloat(max(1, lines)) * (rowHeight + spacing) + (hasMore ? moreHeight + spacing : 0)) * scale
    }

    static func height(model: CalendarModel, rowLimit: Int, scale: CGFloat = 1) -> CGFloat {
        guard model.access.canRead else { return height(lines: 1, hasMore: false, scale: scale) }
        let list = model.upcoming.trimmed(to: rowLimit)
        return height(lines: list.rows.count, hasMore: list.moreCount > 0, scale: scale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing * scale) {
            Divider().padding(.bottom, Self.spacing * scale)
            if !model.access.canRead {
                Button("Show your calendar here", action: onSetUp)
                    .buttonStyle(.link)
                    .frame(height: Self.rowHeight * scale)
            } else {
                let list = model.upcoming.trimmed(to: rowLimit)
                if list.rows.isEmpty {
                    Text("Nothing else on your calendar today")
                        .foregroundStyle(.secondary)
                        .frame(height: Self.rowHeight * scale)
                }
                ForEach(list.rows, id: \.event.id) { row in
                    EventRow(row: row).frame(height: Self.rowHeight * scale)
                }
                if list.moreCount > 0 {
                    Text("+\(list.moreCount) more")
                        .foregroundStyle(.secondary)
                        .frame(height: Self.moreHeight * scale)
                }
            }
        }
        .font(.system(size: 12 * scale))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EventRow: View {
    let row: UpcomingRow

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme
    @Environment(\.timerScale) private var scale

    private var title: String { row.event.title.isEmpty ? "No title" : row.event.title }
    /// "1:30 – 3:47 PM", in the system's style and 12/24-hour setting.
    private var range: String {
        EventTimeText.range(row.event, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
    }
    private var spoken: String {
        EventTimeText.spoken(row.event, calendar: .autoupdatingCurrent, locale: .autoupdatingCurrent)
    }

    var body: some View {
        HStack(spacing: 6 * scale) {
            Circle().fill(Color(row.event.color)).frame(width: 7 * scale, height: 7 * scale)
            Text(range)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 118 * scale, alignment: .leading)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8 * scale)
            if row.isNow {
                Text("Now")
                    .fontWeight(.semibold)
                    .foregroundStyle(ThemeColors(palette, scheme: scheme).focus)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spoken), \(title)" + (row.isNow ? ", now" : ""))
        .accessibilityIdentifier(UpcomingEventsView.rowIdentifier)
    }
}
