import Foundation

/// An event's start and end as the Timer page's list writes them: "1:30 – 3:47 PM",
/// or "13:30–15:47", in the system's time-range style. Times only: an event
/// that runs across midnight shows its times without dates.
public enum EventTimeText {
    public static func range(_ event: CalendarEvent, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let text = formatter.string(from: event.start, to: event.end)
        // Across midnight some locales add the dates back; times alone, then.
        if calendar.isDate(event.start, inSameDayAs: event.end) || !mentionsDate(text, event, calendar, locale) {
            return text
        }
        return time(event.start, calendar, locale) + "–" + time(event.end, calendar, locale)
    }

    /// "1:30 PM to 3:47 PM", for VoiceOver.
    public static func spoken(_ event: CalendarEvent, calendar: Calendar, locale: Locale) -> String {
        time(event.start, calendar, locale) + " to " + time(event.end, calendar, locale)
    }

    private static func time(_ date: Date, _ calendar: Calendar, _ locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func mentionsDate(_ text: String, _ event: CalendarEvent, _ calendar: Calendar, _ locale: Locale) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return text.contains(formatter.string(from: event.start)) || text.contains(formatter.string(from: event.end))
            || text.contains("/")
    }
}
