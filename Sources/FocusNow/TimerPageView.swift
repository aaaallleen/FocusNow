import FocusNowCore
import SwiftUI

/// Page 1 of the main window: the timer, filling the page whether or not a
/// session is running, with today's events under it. The cycle's lengths
/// live in Settings → Cycle.
struct TimerPageView: View {
    let engine: TimerEngine
    let settings: SettingsStore
    let calendarModel: CalendarModel
    let calendarPrefs: CalendarPreferences
    var onAction: (TimerControl) -> Void = { _ in }
    var onShowCalendarSettings: () -> Void = {}

    @State private var pendingEdits = PendingEdits()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let scale = TimerPageLayout.scale(for: size)
            let rowLimit = TimerPageLayout.rows(for: size)
            let eventsHeight = calendarPrefs.showOnTimerPage
                ? UpcomingEventsView.height(model: calendarModel, rowLimit: rowLimit, scale: scale) : nil
            let spacing = TimerPageLayout.spacing * scale
            let width = TimerPageLayout.columnWidth * scale
            VStack(spacing: spacing) {
                let diameter = TimerPageLayout.diameter(for: size, eventsHeight: eventsHeight)
                PhaseLabel(engine: engine, size: 13 * scale)
                TimerRing(engine: engine, diameter: diameter, editable: true)
                    // A bigger ring gets more room above and below.
                    .padding(.vertical, TimerPageLayout.ringGap(for: diameter, scale: scale) - spacing)
                TimerControlsRow(engine: engine, onAction: onAction)
                    .frame(maxWidth: width)
                TodayBar(engine: engine, settings: settings)
                    .frame(maxWidth: width)
                if let eventsHeight {
                    UpcomingEventsView(model: calendarModel, rowLimit: rowLimit, onSetUp: onShowCalendarSettings)
                        .frame(maxWidth: width)
                        .frame(height: eventsHeight, alignment: .top)
                }
            }
            // Everything under the ring is drawn at the page's zoom.
            .environment(\.timerScale, scale)
            // Phase changes crossfade (label, ring colour, controls), as in the popover.
            .animation(.easeInOut(duration: Theme.phaseFade), value: engine.phaseKey)
            .padding(.horizontal, 24)
            .frame(width: size.width, height: size.height)
        }
        .environment(\.pendingEdits, pendingEdits)
    }
}

extension EnvironmentValues {
    /// How much bigger than its default the Timer page is drawn: 1 at the
    /// default window and smaller, growing with bigger windows. The popover is 1.
    @Entry var timerScale: CGFloat = 1
}

/// How big the Timer page's ring is, and how many events fit under it.
///
/// The page zooms with the window from its default 760 × 560: the label, the
/// buttons, the Today bar, the event list and the spacing all grow by
/// `scale(for:)`, so a bigger window looks like the default one, larger.
@MainActor
enum TimerPageLayout {
    static let minimumDiameter: CGFloat = 120
    static let spacing: CGFloat = 22
    /// The buttons, Today bar and event list at the default size.
    static let columnWidth: CGFloat = 320
    /// The window content size the page is designed at (scale 1).
    static let designSize = CGSize(width: 760, height: 560)
    /// The phase label, both rows of controls, today's bar and the spacing
    /// between them (the second row is 27 pt plus a 6 pt gap), at scale 1.
    private static let reserved: CGFloat = 203

    /// 1 up to the default window size, then growing with the window; the
    /// smaller of the two directions decides, so the page always fits.
    static func scale(for size: CGSize) -> CGFloat {
        max(1, min(size.width / designSize.width, size.height / designSize.height))
    }

    /// The ring's diameter, leaving room for the event list when it's shown
    /// (`eventsHeight`), never under `minimumDiameter`.
    static func diameter(for size: CGSize, eventsHeight: CGFloat?) -> CGFloat {
        max(rawDiameter(for: size, eventsHeight: eventsHeight), minimumDiameter)
    }

    /// The most event rows (1–3) that keep the ring at least `minimumDiameter`.
    static func rows(for size: CGSize) -> Int {
        let scale = scale(for: size)
        return (1...UpcomingEvents.limit).reversed().first { rows in
            let height = UpcomingEventsView.height(lines: rows, hasMore: true, scale: scale)
            return rawDiameter(for: size, eventsHeight: height) >= minimumDiameter
        } ?? 1
    }

    /// Of the ring's diameter, the share kept free above it and below it.
    private static let ringGapShare: CGFloat = 0.12

    /// The room above and below the ring: the page's spacing for small rings,
    /// growing with bigger ones.
    static func ringGap(for diameter: CGFloat, scale: CGFloat) -> CGFloat {
        max(spacing * scale, diameter * ringGapShare)
    }

    /// `eventsHeight` is already at the page's scale.
    private static func rawDiameter(for size: CGSize, eventsHeight: CGFloat?) -> CGFloat {
        let scale = scale(for: size)
        let gap = spacing * scale
        let below = reserved * scale + (eventsHeight.map { $0 + gap } ?? 0)
        // The ring plus its two growing gaps (beyond `gap` each) must fit in
        // what's left. The gaps start growing once the ring passes gap / share.
        let available = size.height - below
        let fit = available <= gap / ringGapShare
            ? available
            : (available + 2 * gap) / (1 + 2 * ringGapShare)
        return min(min(size.width, size.height) * 0.7, fit)
    }
}
