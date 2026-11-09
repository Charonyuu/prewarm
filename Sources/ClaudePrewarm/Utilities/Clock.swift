import Foundation

/// The time labels are read against. Screenshots pin it so they read like a
/// normal morning whenever they are rendered; everything else uses the real time.
enum Clock {
    nonisolated(unsafe) static var override: Date?
    static var now: Date { override ?? Date() }

    static func isToday(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(date, inSameDayAs: now)
    }

    static func isTomorrow(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
        return calendar.isDate(date, inSameDayAs: tomorrow)
    }
}
