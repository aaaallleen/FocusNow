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
            let rowLimit = TimerPageLayout.rows(for: size)
            let eventsHeight = calendarPrefs.showOnTimerPage
                ? UpcomingEventsView.height(model: calendarModel, rowLimit: rowLimit) : nil
            VStack(spacing: TimerPageLayout.spacing) {
                let diameter = TimerPageLayout.diameter(for: size, eventsHeight: eventsHeight)
                PhaseLabel(engine: engine, size: 13)
                TimerRing(engine: engine, diameter: diameter, editable: true)
                    // A bigger ring gets more room above and below.
                    .padding(.vertical, TimerPageLayout.ringGap(for: diameter) - TimerPageLayout.spacing)
                TimerControlsRow(engine: engine, onAction: onAction)
                    .frame(maxWidth: 320)
                TodayBar(engine: engine, settings: settings)
                    .frame(maxWidth: 320)
                if let eventsHeight {
                    UpcomingEventsView(model: calendarModel, rowLimit: rowLimit, onSetUp: onShowCalendarSettings)
                        .frame(maxWidth: 320)
                        .frame(height: eventsHeight, alignment: .top)
                }
            }
            // Phase changes crossfade (label, ring colour, controls), as in the popover.
            .animation(.easeInOut(duration: Theme.phaseFade), value: engine.phaseKey)
            .padding(.horizontal, 24)
            .frame(width: size.width, height: size.height)
        }
        .environment(\.pendingEdits, pendingEdits)
    }
}

/// How big the Timer page's ring is, and how many events fit under it.
@MainActor
enum TimerPageLayout {
    static let minimumDiameter: CGFloat = 120
    static let spacing: CGFloat = 22
    /// The phase label, both rows of controls, today's bar and the spacing
    /// between them (the second row is 27 pt plus a 6 pt gap).
    private static let reserved: CGFloat = 203

    /// The ring's diameter, leaving room for the event list when it's shown
    /// (`eventsHeight`), never under `minimumDiameter`.
    static func diameter(for size: CGSize, eventsHeight: CGFloat?) -> CGFloat {
        max(rawDiameter(for: size, eventsHeight: eventsHeight), minimumDiameter)
    }

    /// The most event rows (1–3) that keep the ring at least `minimumDiameter`.
    static func rows(for size: CGSize) -> Int {
        (1...UpcomingEvents.limit).reversed().first { rows in
            rawDiameter(for: size, eventsHeight: UpcomingEventsView.height(lines: rows, hasMore: true)) >= minimumDiameter
        } ?? 1
    }

    /// Of the ring's diameter, the share kept free above it and below it.
    private static let ringGapShare: CGFloat = 0.12

    /// The room above and below the ring: `spacing` for small rings, growing
    /// with bigger ones.
    static func ringGap(for diameter: CGFloat) -> CGFloat {
        max(spacing, diameter * ringGapShare)
    }

    private static func rawDiameter(for size: CGSize, eventsHeight: CGFloat?) -> CGFloat {
        let below = reserved + (eventsHeight.map { $0 + spacing } ?? 0)
        // The ring plus its two growing gaps (beyond `spacing` each) must fit
        // in what's left. The gaps start growing once the ring passes
        // spacing / share (about 183 pt).
        let available = size.height - below
        let fit = available <= spacing / ringGapShare
            ? available
            : (available + 2 * spacing) / (1 + 2 * ringGapShare)
        return min(min(size.width, size.height) * 0.7, fit)
    }
}
