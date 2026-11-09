import Foundation

/// A work day: whether it counts, and when you start.
struct DaySchedule: Codable, Equatable, Sendable {
    var enabled: Bool
    var hour: Int
    var minute: Int

    var timeLabel: String { String(format: "%02d:%02d", hour, minute) }
}

enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case icon
    case iconPercent
    case bars

    var label: String {
        switch self {
        case .icon: return "Icon"
        case .iconPercent: return "Icon and %"
        case .bars: return "Bars"
        }
    }
}

enum AlertScope: String, Codable, CaseIterable, Sendable {
    case session
    case weekly
    case both

    var label: String {
        switch self {
        case .session: return "5-hour"
        case .weekly: return "Weekly"
        case .both: return "Both"
        }
    }
}

/// User-configurable settings, persisted in UserDefaults.
struct AppSettings: Codable, Equatable, Sendable {
    /// Calendar weekday (1 = Sunday … 7 = Saturday) → that day's schedule.
    var days: [Int: DaySchedule]
    var prewarmOffsetMinutes: Int
    var launchAtLogin: Bool
    /// A missed warm still runs after wake if it is at most this late. 0 turns it off.
    var wakeGraceMinutes: Int

    var warmClaude: Bool
    var warmCodex: Bool
    var warmAgyGemini: Bool
    var warmAgyOther: Bool

    var shownProviders: [Provider]
    var menuBarStyle: MenuBarStyle
    var refreshMinutes: Int
    var refreshOnOpen: Bool
    var hotkeyEnabled: Bool

    var alertThresholds: [Int]
    var alertScope: AlertScope
    var notifySessionReset: Bool
    var notifyWeeklyReset: Bool
    var notifyWarmFailure: Bool
    var notifyWarmSuccess: Bool
    var quietHoursEnabled: Bool
    /// Minutes after midnight.
    var quietStart: Int
    var quietEnd: Int

    /// A scheduled warm at exactly this time is skipped (right-click › Skip).
    var skipWarmAt: Date?

    static let offsetChoices = [30, 60, 90, 120, 180, 240]
    static let refreshChoices = [5, 10, 15, 30]
    static let graceChoices = [0, 30, 60, 120]
    static let thresholdChoices = [70, 80, 90, 95]

    static let `default` = AppSettings(
        days: Dictionary(uniqueKeysWithValues: (1...7).map { weekday in
            (weekday, DaySchedule(enabled: (2...6).contains(weekday), hour: 9, minute: 0))
        }),
        prewarmOffsetMinutes: 120,
        launchAtLogin: true,
        wakeGraceMinutes: 60,
        warmClaude: true,
        warmCodex: true,
        warmAgyGemini: true,
        warmAgyOther: true,
        shownProviders: Provider.allCases,
        menuBarStyle: .iconPercent,
        refreshMinutes: 10,
        refreshOnOpen: true,
        hotkeyEnabled: true,
        alertThresholds: [80, 95],
        alertScope: .both,
        notifySessionReset: true,
        notifyWeeklyReset: false,
        notifyWarmFailure: true,
        notifyWarmSuccess: false,
        quietHoursEnabled: false,
        quietStart: 22 * 60,
        quietEnd: 8 * 60,
        skipWarmAt: nil
    )

    static func offsetLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return String(format: "%.1f hours", Double(minutes) / 60)
    }

    static func graceLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return "Skip it"
        case 30: return "Warm on wake, up to 30 min late"
        case 60: return "Warm on wake, up to 1 hour late"
        default: return "Warm on wake, up to \(minutes / 60) hours late"
        }
    }

    func day(_ weekday: Int) -> DaySchedule {
        days[weekday] ?? DaySchedule(enabled: false, hour: 9, minute: 0)
    }

    var hasWorkDay: Bool { days.values.contains { $0.enabled } }

    var isValid: Bool {
        days.values.allSatisfy { (0...23).contains($0.hour) && (0...59).contains($0.minute) }
            && prewarmOffsetMinutes > 0 && prewarmOffsetMinutes <= 12 * 60
            && refreshMinutes > 0
    }

    func shows(_ provider: Provider) -> Bool { shownProviders.contains(provider) }

    func wantsWarm(_ target: WarmTarget) -> Bool {
        switch target {
        case .claude: return warmClaude
        case .codex: return warmCodex
        case .agyGemini: return warmAgyGemini
        case .agyOther: return warmAgyOther
        }
    }

    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled, quietStart != quietEnd else { return false }
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if quietStart < quietEnd { return minute >= quietStart && minute < quietEnd }
        return minute >= quietStart || minute < quietEnd
    }

    /// When the current quiet period ends, if `date` is inside one.
    func quietEnds(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isQuiet(at: date, calendar: calendar) else { return nil }
        var end = calendar.date(bySettingHour: quietEnd / 60, minute: quietEnd % 60, second: 0, of: date) ?? date
        if end <= date { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return end
    }
}

extension AppSettings {
    private enum CodingKeys: String, CodingKey {
        case days, prewarmOffsetMinutes, launchAtLogin, wakeGraceMinutes
        case warmClaude, warmCodex, warmAgyGemini, warmAgyOther
        case shownProviders, menuBarStyle, refreshMinutes, refreshOnOpen, hotkeyEnabled
        case alertThresholds, alertScope, notifySessionReset, notifyWeeklyReset
        case notifyWarmFailure, notifyWarmSuccess, quietHoursEnabled, quietStart, quietEnd
        case skipWarmAt
        // 1.x
        case enabledWeekdays, workHour, workMinute
    }

    /// Every field is optional on the way in, so settings saved by 1.x (or by a
    /// later version with more fields) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default

        if let days = try c.decodeIfPresent([Int: DaySchedule].self, forKey: .days) {
            self.days = days
        } else if let weekdays = try c.decodeIfPresent(Set<Int>.self, forKey: .enabledWeekdays) {
            let hour = try c.decodeIfPresent(Int.self, forKey: .workHour) ?? 9
            let minute = try c.decodeIfPresent(Int.self, forKey: .workMinute) ?? 0
            self.days = Dictionary(uniqueKeysWithValues: (1...7).map {
                ($0, DaySchedule(enabled: weekdays.contains($0), hour: hour, minute: minute))
            })
        } else {
            self.days = d.days
        }

        prewarmOffsetMinutes = try c.decodeIfPresent(Int.self, forKey: .prewarmOffsetMinutes) ?? d.prewarmOffsetMinutes
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        wakeGraceMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeGraceMinutes) ?? d.wakeGraceMinutes
        warmClaude = try c.decodeIfPresent(Bool.self, forKey: .warmClaude) ?? d.warmClaude
        warmCodex = try c.decodeIfPresent(Bool.self, forKey: .warmCodex) ?? d.warmCodex
        warmAgyGemini = try c.decodeIfPresent(Bool.self, forKey: .warmAgyGemini) ?? d.warmAgyGemini
        warmAgyOther = try c.decodeIfPresent(Bool.self, forKey: .warmAgyOther) ?? d.warmAgyOther
        shownProviders = try c.decodeIfPresent([Provider].self, forKey: .shownProviders) ?? d.shownProviders
        menuBarStyle = try c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle) ?? d.menuBarStyle
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        refreshOnOpen = try c.decodeIfPresent(Bool.self, forKey: .refreshOnOpen) ?? d.refreshOnOpen
        hotkeyEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled) ?? d.hotkeyEnabled
        alertThresholds = try c.decodeIfPresent([Int].self, forKey: .alertThresholds) ?? d.alertThresholds
        alertScope = try c.decodeIfPresent(AlertScope.self, forKey: .alertScope) ?? d.alertScope
        notifySessionReset = try c.decodeIfPresent(Bool.self, forKey: .notifySessionReset) ?? d.notifySessionReset
        notifyWeeklyReset = try c.decodeIfPresent(Bool.self, forKey: .notifyWeeklyReset) ?? d.notifyWeeklyReset
        notifyWarmFailure = try c.decodeIfPresent(Bool.self, forKey: .notifyWarmFailure) ?? d.notifyWarmFailure
        notifyWarmSuccess = try c.decodeIfPresent(Bool.self, forKey: .notifyWarmSuccess) ?? d.notifyWarmSuccess
        quietHoursEnabled = try c.decodeIfPresent(Bool.self, forKey: .quietHoursEnabled) ?? d.quietHoursEnabled
        quietStart = try c.decodeIfPresent(Int.self, forKey: .quietStart) ?? d.quietStart
        quietEnd = try c.decodeIfPresent(Int.self, forKey: .quietEnd) ?? d.quietEnd
        skipWarmAt = try c.decodeIfPresent(Date.self, forKey: .skipWarmAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(days, forKey: .days)
        try c.encode(prewarmOffsetMinutes, forKey: .prewarmOffsetMinutes)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(wakeGraceMinutes, forKey: .wakeGraceMinutes)
        try c.encode(warmClaude, forKey: .warmClaude)
        try c.encode(warmCodex, forKey: .warmCodex)
        try c.encode(warmAgyGemini, forKey: .warmAgyGemini)
        try c.encode(warmAgyOther, forKey: .warmAgyOther)
        try c.encode(shownProviders, forKey: .shownProviders)
        try c.encode(menuBarStyle, forKey: .menuBarStyle)
        try c.encode(refreshMinutes, forKey: .refreshMinutes)
        try c.encode(refreshOnOpen, forKey: .refreshOnOpen)
        try c.encode(hotkeyEnabled, forKey: .hotkeyEnabled)
        try c.encode(alertThresholds, forKey: .alertThresholds)
        try c.encode(alertScope, forKey: .alertScope)
        try c.encode(notifySessionReset, forKey: .notifySessionReset)
        try c.encode(notifyWeeklyReset, forKey: .notifyWeeklyReset)
        try c.encode(notifyWarmFailure, forKey: .notifyWarmFailure)
        try c.encode(notifyWarmSuccess, forKey: .notifyWarmSuccess)
        try c.encode(quietHoursEnabled, forKey: .quietHoursEnabled)
        try c.encode(quietStart, forKey: .quietStart)
        try c.encode(quietEnd, forKey: .quietEnd)
        try c.encodeIfPresent(skipWarmAt, forKey: .skipWarmAt)
    }
}
