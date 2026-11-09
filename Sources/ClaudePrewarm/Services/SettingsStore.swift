import Foundation

/// UserDefaults-backed persistence. No database, no files of our own.
enum SettingsStore {
    private enum Key {
        static let settings = "appSettings"
        static let lastWarmupAt = "lastWarmupAt"           // 1.x, Claude only
        static let lastWarmByTarget = "lastWarmByTarget"
        static let logs = "warmLogs"
        static let history = "usageHistory"
        static let alerts = "alertState"
        static let onboardingDone = "onboardingDone"
        static let selectedTab = "selectedTab"
    }

    static var defaults = UserDefaults.standard

    /// True only on the very first launch of any version.
    static var isFirstLaunch: Bool {
        defaults.data(forKey: Key.settings) == nil && !defaults.bool(forKey: Key.onboardingDone)
    }

    static var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    static func loadSettings() -> AppSettings {
        guard let data = defaults.data(forKey: Key.settings),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data),
              decoded.isValid
        else { return .default }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
    }

    static func loadLastWarm() -> [WarmTarget: Date] {
        var result: [WarmTarget: Date] = [:]
        if let raw = defaults.dictionary(forKey: Key.lastWarmByTarget) as? [String: Date] {
            for (key, date) in raw { if let target = WarmTarget(rawValue: key) { result[target] = date } }
        } else if let legacy = defaults.object(forKey: Key.lastWarmupAt) as? Date {
            result[.claude] = legacy
        }
        return result
    }

    static func save(lastWarm: [WarmTarget: Date]) {
        defaults.set(Dictionary(uniqueKeysWithValues: lastWarm.map { ($0.key.rawValue, $0.value) }), forKey: Key.lastWarmByTarget)
    }

    static func loadLogs() -> [WarmLog] {
        guard let data = defaults.data(forKey: Key.logs),
              let decoded = try? JSONDecoder().decode([WarmLog].self, from: data)
        else { return [] }
        return decoded
    }

    static func save(_ logs: [WarmLog]) {
        guard let data = try? JSONEncoder().encode(Array(logs.prefix(60))) else { return }
        defaults.set(data, forKey: Key.logs)
    }

    /// provider → "yyyy-MM-dd" → highest percent seen that day.
    static func loadHistory() -> [String: [String: Int]] {
        defaults.dictionary(forKey: Key.history) as? [String: [String: Int]] ?? [:]
    }

    static func save(history: [String: [String: Int]]) {
        defaults.set(history, forKey: Key.history)
    }

    static func loadAlerts() -> [String: AlertRecord] {
        guard let data = defaults.data(forKey: Key.alerts),
              let decoded = try? JSONDecoder().decode([String: AlertRecord].self, from: data)
        else { return [:] }
        return decoded
    }

    static func save(alerts: [String: AlertRecord]) {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        defaults.set(data, forKey: Key.alerts)
    }

    static var selectedTab: String? {
        get { defaults.string(forKey: Key.selectedTab) }
        set { defaults.set(newValue, forKey: Key.selectedTab) }
    }
}

/// The highest alert already sent for one window, so each threshold fires once per window.
struct AlertRecord: Codable, Equatable {
    var level: Int
    var resetsAt: Date?
}
