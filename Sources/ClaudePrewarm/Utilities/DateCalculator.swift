import Foundation

enum DateCalculator {
    /// Weekdays in UI order, Monday first. Values are Calendar weekday numbers.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func weekdayShort(_ weekday: Int) -> String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][(weekday - 1 + 7) % 7]
    }

    /// The work start on `day`'s date, if that weekday is a work day.
    static func workStart(on day: Date, settings: AppSettings, calendar: Calendar = .current) -> Date? {
        let weekday = calendar.component(.weekday, from: day)
        let schedule = settings.day(weekday)
        guard schedule.enabled else { return nil }
        return calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: day)
    }

    /// Next warm time strictly after `now`. A warm time that already passed is
    /// skipped, never back-filled. Looks one day back so an offset that crosses
    /// midnight (work at 01:00, warm at 21:00 the day before) is found.
    static func nextWarmup(settings: AppSettings, from now: Date, calendar: Calendar = .current) -> Date? {
        guard settings.isValid, settings.hasWorkDay else { return nil }
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let start = workStart(on: day, settings: settings, calendar: calendar)
            else { continue }
            let warm = start.addingTimeInterval(-Double(settings.prewarmOffsetMinutes) * 60)
            if warm > now { return warm }
        }
        return nil
    }

    /// The most recent warm time at or before `now`, if it is within `grace`.
    static func missedWarmup(settings: AppSettings, at now: Date, grace: TimeInterval, calendar: Calendar = .current) -> Date? {
        guard grace > 0, settings.isValid, settings.hasWorkDay else { return nil }
        var best: Date?
        for dayOffset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
                  let start = workStart(on: day, settings: settings, calendar: calendar)
            else { continue }
            let warm = start.addingTimeInterval(-Double(settings.prewarmOffsetMinutes) * 60)
            if warm <= now, now.timeIntervalSince(warm) <= grace, warm > (best ?? .distantPast) {
                best = warm
            }
        }
        return best
    }

    /// The work start a warm at `warm` is for.
    static func workStart(forWarm warm: Date, settings: AppSettings) -> Date {
        warm.addingTimeInterval(Double(settings.prewarmOffsetMinutes) * 60)
    }

    /// "Today 07:00" / "Tomorrow 07:00" / "Mon 07:00".
    static func relativeLabel(for date: Date, calendar: Calendar = .current) -> String {
        let time = timeLabel(for: date, calendar: calendar)
        if Clock.isToday(date, calendar: calendar) { return "Today \(time)" }
        if Clock.isTomorrow(date, calendar: calendar) { return "Tomorrow \(time)" }
        return "\(weekdayShort(calendar.component(.weekday, from: date))) \(time)"
    }

    /// "19:10" today, "Tomorrow 05:00", within a week "Sun 05:00", else "Nov 16 05:00".
    static func compactLabel(for date: Date, now: Date = Clock.now, calendar: Calendar = .current) -> String {
        let time = timeLabel(for: date, calendar: calendar)
        if Clock.isToday(date, calendar: calendar) { return time }
        if Clock.isTomorrow(date, calendar: calendar) { return "Tomorrow \(time)" }
        if date.timeIntervalSince(now) < 6 * 24 * 3600 && date > now {
            return "\(weekdayShort(calendar.component(.weekday, from: date))) \(time)"
        }
        return "\(dayLabel(for: date, calendar: calendar)) \(time)"
    }

    /// For past events: "Today 07:00", "Yesterday 07:00", "Fri 07:00", "Nov 3 07:00".
    static func pastLabel(for date: Date, calendar: Calendar = .current) -> String {
        let time = timeLabel(for: date, calendar: calendar)
        if Clock.isToday(date, calendar: calendar) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Clock.now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday \(time)" }
        if Clock.now.timeIntervalSince(date) < 6 * 24 * 3600 {
            return "\(weekdayShort(calendar.component(.weekday, from: date))) \(time)"
        }
        return "\(dayLabel(for: date, calendar: calendar).split(separator: " ").dropFirst().joined(separator: " ")) \(time)"
    }

    /// "Mon Nov 16"
    static func dayLabel(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: date)
    }

    static func timeLabel(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// "2h 19m", "3d 8h", "12m", "under a minute".
    static func durationLabel(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval) / 60)
        if total < 1 { return "under a minute" }
        let days = total / (24 * 60)
        let hours = (total % (24 * 60)) / 60
        let minutes = total % 60
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// "just now", "4 min ago", "2 h ago".
    static func agoLabel(_ date: Date, now: Date = Clock.now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        return "\(Int(seconds / 3600)) h ago"
    }
}
