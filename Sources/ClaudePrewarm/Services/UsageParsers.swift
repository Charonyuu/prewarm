import Foundation

private let fiveHours: TimeInterval = 5 * 3600
private let oneWeek: TimeInterval = 7 * 24 * 3600

private func slug(_ text: String) -> String {
    text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        .split(separator: "-").joined(separator: "-")
}

// MARK: - Claude: `claude -p /usage`

enum ClaudeUsageParser {
    /// Reads lines such as:
    ///   Current session: 37% used · resets Sep 20 at 7:10pm (Asia/Taipei)
    ///   Current week (all models): 67% used · resets Nov 9 at 4:59am (Asia/Taipei)
    ///   Current week (Fable): 0% used · resets Nov 9 at 5am (Asia/Taipei)
    /// plus the "What's contributing" block.
    static func parse(_ output: String, now: Date = Date(), calendar: Calendar = .current) -> ProviderUsage? {
        var windows: [UsageWindow] = []
        var sawSession = false

        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let m = match(#"^Current session:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s*([^\n(]+))?"#, line) {
                sawSession = true
                let reset = m[2].flatMap { parseReset($0, now: now, calendar: calendar) }
                windows.append(UsageWindow(
                    id: "claude.session", title: "Current session · 5 hours", shortTitle: "5-hour",
                    kind: .session, usedPercent: Double(m[1] ?? ""), resetsAt: reset,
                    resetText: reset == nil ? m[2]?.trimmingCharacters(in: .whitespaces) : nil,
                    duration: fiveHours
                ))
            } else if let m = match(#"^Current week(?:\s*\(([^)]+)\))?:\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s*([^\n(]+))?"#, line) {
                let name = m[1]?.trimmingCharacters(in: .whitespaces) ?? "all models"
                let isAll = name.lowercased() == "all models"
                let reset = m[3].flatMap { parseReset($0, now: now, calendar: calendar) }
                windows.append(UsageWindow(
                    id: "claude.week.\(slug(name))",
                    title: "This week · \(name)",
                    shortTitle: isAll ? "Week" : name,
                    kind: isAll ? .weekly : .model,
                    usedPercent: Double(m[2] ?? ""),
                    resetsAt: reset,
                    resetText: reset == nil ? m[3]?.trimmingCharacters(in: .whitespaces) : nil,
                    duration: oneWeek
                ))
            }
        }
        guard !windows.isEmpty else { return nil }

        if !sawSession {
            windows.insert(UsageWindow(
                id: "claude.session", title: "Current session · 5 hours", shortTitle: "5-hour",
                kind: .session, usedPercent: 0, resetsAt: nil, resetText: nil,
                duration: fiveHours, notStarted: true
            ), at: 0)
        }
        // All-models week before single-model weeks.
        windows.sort { order($0) < order($1) }

        return ProviderUsage(
            fetchedAt: now,
            plan: nil,
            windows: windows,
            insights24h: insights(in: output, header: "Last 24h"),
            insights7d: insights(in: output, header: "Last 7d")
        )
    }

    private static func order(_ window: UsageWindow) -> Int {
        switch window.kind {
        case .session: return 0
        case .weekly: return 1
        case .model: return 2
        }
    }

    /// "  91% of your usage was at >150k context" under a "Last 24h ·" header.
    static func insights(in output: String, header: String) -> [Insight] {
        var result: [Insight] = []
        var inside = false
        for rawLine in output.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(header) { inside = true; continue }
            guard inside else { continue }
            if line.hasPrefix("Last ") { break }
            if let m = match(#"^(\d+)% of your usage (.+)$"#, line), let percent = Int(m[1] ?? "") {
                var text = m[2] ?? ""
                for prefix in ["was ", "came "] where text.hasPrefix(prefix) {
                    text.removeFirst(prefix.count)
                }
                result.append(Insight(percent: percent, text: text))
            } else if !result.isEmpty && !line.isEmpty {
                break
            }
        }
        return result
    }

    /// "Sep 20 at 7:10pm" / "Nov 9 at 5am". The year is absent, so it is inferred.
    static func parseReset(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        let formats = ["MMM d 'at' h:mma", "MMM d 'at' ha", "MMM d h:mma", "MMM d ha", "h:mma", "ha"]
        let year = calendar.component(.year, from: now)

        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
            if format.hasPrefix("h") {
                // Time only: today, or tomorrow if that already passed.
                formatter.dateFormat = format
                guard let time = formatter.date(from: cleaned) else { continue }
                let comps = calendar.dateComponents([.hour, .minute], from: time)
                guard var date = calendar.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: now) else { continue }
                if date < now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
                return date
            }
            formatter.dateFormat = "yyyy " + format
            guard let parsed = formatter.date(from: "\(year) \(cleaned)") else { continue }
            // A reset is always near: if the inferred year lands far in the past, roll it forward.
            if parsed < now.addingTimeInterval(-2 * 24 * 3600),
               let next = calendar.date(byAdding: .year, value: 1, to: parsed) {
                return next
            }
            return parsed
        }
        return nil
    }
}

// MARK: - Codex: `codex app-server` › account/rateLimits/read

enum CodexUsageParser {
    static func planName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let known = [
            "prolite": "Pro Lite", "pro": "Pro", "plus": "Plus", "free": "Free", "team": "Team",
            "business": "Business", "enterprise": "Enterprise", "edu": "Edu", "go": "Go"
        ]
        if let name = known[raw.lowercased()] { return name }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

    static func parse(limits: [String: Any], account: [String: Any]?, now: Date = Date()) -> ProviderUsage? {
        guard let rate = limits["rateLimits"] as? [String: Any] else { return nil }
        var windows: [UsageWindow] = []

        for key in ["primary", "secondary"] {
            guard let w = rate[key] as? [String: Any] else { continue }
            if let window = window(from: w, idPrefix: "codex", now: now) { windows.append(window) }
        }

        // Extra per-model limits, if the server reports any.
        if let byId = limits["rateLimitsByLimitId"] as? [String: Any] {
            for (limitId, value) in byId.sorted(by: { $0.key < $1.key }) where limitId != (rate["limitId"] as? String ?? "codex") {
                guard let entry = value as? [String: Any] else { continue }
                let name = (entry["limitName"] as? String) ?? limitId
                for key in ["primary", "secondary"] {
                    guard let w = entry[key] as? [String: Any],
                          var window = window(from: w, idPrefix: "codex.\(slug(limitId))", now: now) else { continue }
                    window.kind = .model
                    window.title = "\(name) · \(window.shortTitle.lowercased())"
                    window.shortTitle = name
                    windows.append(window)
                }
            }
        }
        func rank(_ w: UsageWindow) -> Int { w.kind == .session ? 0 : w.kind == .weekly ? 1 : 2 }
        windows.sort { rank($0) != rank($1) ? rank($0) < rank($1) : ($0.duration ?? 0) < ($1.duration ?? 0) }

        var usage = ProviderUsage(
            fetchedAt: now,
            plan: planName((rate["planType"] as? String) ?? ((account?["account"] as? [String: Any])?["planType"] as? String)),
            windows: windows
        )
        if let resetInfo = limits["rateLimitResetCredits"] as? [String: Any] {
            usage.freeResets = resetInfo["availableCount"] as? Int
            let expiries = (resetInfo["credits"] as? [[String: Any]] ?? [])
                .filter { ($0["status"] as? String ?? "available") == "available" }
                .compactMap { ($0["expiresAt"] as? NSNumber)?.doubleValue }
            if let first = expiries.min() { usage.freeResetExpires = Date(timeIntervalSince1970: first) }
        }
        if let credits = rate["credits"] as? [String: Any] {
            if credits["unlimited"] as? Bool == true {
                usage.creditBalance = "Unlimited"
            } else if let balance = credits["balance"] as? String {
                usage.creditBalance = balance
            }
        }
        return usage
    }

    private static func window(from w: [String: Any], idPrefix: String, now: Date) -> UsageWindow? {
        guard let used = (w["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
        let minutes = (w["windowDurationMins"] as? NSNumber)?.doubleValue
        let reset = (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let duration = minutes.map { $0 * 60 }
        let isSession = (minutes ?? 0) > 0 && (minutes ?? 0) <= 6 * 60
        let isWeek = (minutes ?? 0) >= 6 * 24 * 60
        let hours = Int(((minutes ?? 0) / 60).rounded())
        return UsageWindow(
            id: "\(idPrefix).\(isSession ? "session" : isWeek ? "week" : "w\(Int(minutes ?? 0))")",
            title: isSession ? "Current session · \(hours) hours" : isWeek ? "This week" : "\(hours)-hour window",
            shortTitle: isSession ? "\(hours)-hour" : isWeek ? "Week" : "\(hours)h",
            kind: isSession ? .session : .weekly,
            usedPercent: used,
            resetsAt: reset,
            duration: duration
        )
    }
}

// MARK: - Grok: `grok agent stdio` › _x.ai/billing

enum GrokUsageParser {
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    static func parse(_ result: [String: Any], now: Date = Date()) -> ProviderUsage? {
        guard let config = result["config"] as? [String: Any] else { return nil }
        let percent = (config["creditUsagePercent"] as? NSNumber)?.doubleValue
        let period = config["currentPeriod"] as? [String: Any]
        let start = date(period?["start"]) ?? date(config["billingPeriodStart"])
        let end = date(period?["end"]) ?? date(config["billingPeriodEnd"])
        let type = (period?["type"] as? String ?? "").uppercased()
        let weekly = type.contains("WEEK") || ((end?.timeIntervalSince(start ?? .distantPast) ?? 0) < 8 * 24 * 3600)

        var windows: [UsageWindow] = []
        if percent != nil || end != nil {
            windows.append(UsageWindow(
                id: "grok.credits",
                title: weekly ? "This week · credits" : "This month · credits",
                shortTitle: weekly ? "Week" : "Month",
                kind: .weekly,
                usedPercent: percent,
                resetsAt: end,
                duration: (start != nil && end != nil) ? end!.timeIntervalSince(start!) : nil
            ))
        }
        guard !windows.isEmpty else { return nil }

        var usage = ProviderUsage(
            fetchedAt: now,
            plan: (result["subscription_tier"] as? String) ?? (config["subscriptionTier"] as? String),
            windows: windows
        )
        usage.periodStart = start
        usage.periodEnd = end
        if let balance = config["prepaidBalance"] as? [String: Any], let val = balance["val"] {
            // xAI amounts are whole cents.
            let cents = (val as? NSNumber)?.doubleValue ?? Double(val as? String ?? "") ?? 0
            usage.prepaidBalance = cents / 100
        }
        if let onDemand = config["onDemandEnabled"] as? Bool ?? config["on_demand_enabled"] as? Bool {
            usage.onDemandEnabled = onDemand
        } else if let cap = config["onDemandCap"] {
            usage.onDemandEnabled = !((cap as? [String: Any])?["val"] as? NSNumber == 0)
        } else {
            usage.onDemandEnabled = false
        }
        return usage
    }
}

// MARK: - agy: `agy -p /usage`

enum AgyUsageParser {
    /// Tab-separated rows: group, label, remaining %, reset time.
    ///   Gemini Models	Five Hour Limit Remaining	100%	2026-11-09T00:02:01Z
    ///   Gemini 4 Argon	Gemini 4 Argon Weekly Limit	99%	2026-11-14T10:51:33Z
    static func parse(_ output: String, now: Date = Date()) -> ProviderUsage? {
        var windows: [UsageWindow] = []
        let iso = ISO8601DateFormatter()

        for line in output.components(separatedBy: .newlines) {
            let cols = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 3, cols[2].hasSuffix("%"),
                  let remaining = Double(cols[2].dropLast()) else { continue }
            let group = cols[0]
            let label = cols[1].lowercased()
            let reset = cols.count >= 4 ? iso.date(from: cols[3]) : nil
            let isSession = label.contains("five hour") || label.contains("5 hour") || label.contains("5-hour")
            let isGroup = group.lowercased().hasSuffix("models")
            let short = group.lowercased().contains("gemini") ? "Gemini" : group.lowercased().contains("claude") ? "Claude/GPT" : group

            var window = UsageWindow(
                id: "agy.\(slug(group)).\(isSession ? "session" : "week")",
                title: isSession ? "5 hours" : "This week",
                shortTitle: isGroup ? "\(short) \(isSession ? "5h" : "week")" : group,
                group: isGroup ? group : nil,
                kind: isGroup ? (isSession ? .session : .weekly) : .model,
                usedPercent: max(0, min(100, 100 - remaining)),
                resetsAt: reset,
                duration: isSession ? fiveHours : oneWeek
            )
            if !isGroup { window.title = "\(group) · \(isSession ? "5 hours" : "week")" }
            // An unstarted 5-hour window reports a reset exactly five hours out.
            // A window started a minute ago looks the same, so AppState checks
            // that against its own warm-ups and the previous read.
            if isSession, remaining >= 100, let reset, abs(reset.timeIntervalSince(now) - fiveHours) < 180 {
                window.notStarted = true
            }
            windows.append(window)
        }
        guard !windows.isEmpty else { return nil }
        return ProviderUsage(fetchedAt: now, plan: nil, windows: windows)
    }

    /// Groups in the order the CLI printed them.
    static func groups(_ usage: ProviderUsage) -> [String] {
        var seen: [String] = []
        for w in usage.windows { if let g = w.group, !seen.contains(g) { seen.append(g) } }
        return seen
    }
}

// MARK: - Versions

enum VersionParser {
    /// "2.1.282 (Claude Code)", "codex-cli 0.166.0", "grok 1.0.70 (f50904e)", "1.5.3".
    static func parse(_ output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\d+\.\d+(?:\.\d+)?"#),
              let m = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(m.range, in: output) else { return nil }
        return String(output[range])
    }
}

/// Regex helper: capture groups by index; nil for groups that didn't take part.
func match(_ pattern: String, _ text: String) -> [Int: String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    var groups: [Int: String] = [:]
    for index in 0..<m.numberOfRanges {
        if let range = Range(m.range(at: index), in: text) { groups[index] = String(text[range]) }
    }
    return groups
}
