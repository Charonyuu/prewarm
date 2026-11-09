import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    print((condition ? "PASS " : "FAIL ") + name + (condition ? "" : "  \(detail)"))
    if !condition { failures += 1 }
}

var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
func date(_ s: String) -> Date {
    let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"; return f.date(from: s)!
}
func label(_ d: Date?) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
}
func next(_ s: AppSettings, _ from: String) -> String {
    label(DateCalculator.nextWarmup(settings: s, from: date(from), calendar: cal))
}

// MARK: Schedule

let monFri = AppSettings.default   // Mon–Fri 09:00, 120 min
check("today upcoming", next(monFri, "2026-09-16 06:00") == "2026-09-16 07:00", next(monFri, "2026-09-16 06:00"))
check("past today skips to next day", next(monFri, "2026-09-16 14:00") == "2026-09-17 07:00", next(monFri, "2026-09-16 14:00"))
check("weekend skipped", next(monFri, "2026-09-18 14:00") == "2026-09-21 07:00", next(monFri, "2026-09-18 14:00"))
check("saturday -> monday", next(monFri, "2026-09-19 10:00") == "2026-09-21 07:00", next(monFri, "2026-09-19 10:00"))

var perDay = AppSettings.default
perDay.days[5] = DaySchedule(enabled: true, hour: 10, minute: 30)   // Thursday later
check("per-day start time", next(perDay, "2026-09-16 14:00") == "2026-09-17 08:30", next(perDay, "2026-09-16 14:00"))

var nightShift = AppSettings.default
for d in 1...7 { nightShift.days[d]?.hour = 1 }
nightShift.prewarmOffsetMinutes = 240
check("offset crosses midnight", next(nightShift, "2026-09-16 12:00") == "2026-09-16 21:00", next(nightShift, "2026-09-16 12:00"))

var sundayOnly = AppSettings.default
for d in 1...7 { sundayOnly.days[d]?.enabled = d == 1 }
check("single day repeats weekly", next(sundayOnly, "2026-09-21 08:00") == "2026-09-27 07:00", next(sundayOnly, "2026-09-21 08:00"))

var noDays = AppSettings.default
for d in 1...7 { noDays.days[d]?.enabled = false }
check("no work day -> nil", DateCalculator.nextWarmup(settings: noDays, from: date("2026-09-16 06:00"), calendar: cal) == nil)
check("no work days is still valid (watch-only)", noDays.isValid)

check("missed warm within grace",
      label(DateCalculator.missedWarmup(settings: monFri, at: date("2026-09-16 07:45"), grace: 3600, calendar: cal)) == "2026-09-16 07:00")
check("missed warm past grace", DateCalculator.missedWarmup(settings: monFri, at: date("2026-09-16 08:30"), grace: 3600, calendar: cal) == nil)
check("missed warm off at grace 0", DateCalculator.missedWarmup(settings: monFri, at: date("2026-09-16 07:10"), grace: 0, calendar: cal) == nil)
check("no missed warm on weekend", DateCalculator.missedWarmup(settings: monFri, at: date("2026-09-19 07:10"), grace: 3600, calendar: cal) == nil)
check("weekday order", DateCalculator.weekdayOrder.map(DateCalculator.weekdayShort).joined(separator: ",") == "Mon,Tue,Wed,Thu,Fri,Sat,Sun")

// MARK: Settings migration

let v1 = #"{"enabledWeekdays":[2,4,6],"workHour":8,"workMinute":30,"prewarmOffsetMinutes":60,"launchAtLogin":false}"#
if let migrated = try? JSONDecoder().decode(AppSettings.self, from: Data(v1.utf8)) {
    check("1.x days migrate", migrated.days[2]?.enabled == true && migrated.days[3]?.enabled == false && migrated.days[6]?.enabled == true)
    check("1.x time migrates", migrated.days[4]?.hour == 8 && migrated.days[4]?.minute == 30)
    check("1.x offset kept", migrated.prewarmOffsetMinutes == 60 && migrated.launchAtLogin == false)
    check("new fields default", migrated.warmClaude && migrated.shownProviders == Provider.allCases && migrated.alertThresholds == [80, 95])
} else {
    check("1.x settings decode", false)
}
let roundTrip = try? JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(perDay))
check("settings round-trip", roundTrip == perDay)

var quiet = AppSettings.default
quiet.quietHoursEnabled = true
check("quiet at 23:00", quiet.isQuiet(at: date("2026-09-16 23:00"), calendar: cal))
check("quiet at 07:59", quiet.isQuiet(at: date("2026-09-16 07:59"), calendar: cal))
check("not quiet at 12:00", !quiet.isQuiet(at: date("2026-09-16 12:00"), calendar: cal))
check("quiet ends 08:00 next day", label(quiet.quietEnds(after: date("2026-09-16 23:00"), calendar: cal)) == "2026-09-17 08:00")

// MARK: Claude /usage

let claudeOut = """
You are currently using your subscription to power your Claude Code usage

Current session: 37% used · resets Sep 20 at 7:10pm (Asia/Taipei)
Current week (all models): 81% used · resets Sep 21 at 5am (Asia/Taipei)
Current week (Fable): 4% used · resets Sep 21 at 5am (Asia/Taipei)

What's contributing to your limits usage?
Approximate, based on local sessions on this machine — does not include other devices or claude.ai.

Last 24h · 9410 requests · 30 sessions
  91% of your usage was at >150k context
  87% of your usage came from subagent-heavy sessions
  Top skills: /caveman 1%

Last 7d · 20835 requests · 161 sessions
  88% of your usage was at >150k context
  Top subagents: general-purpose 14%
"""
let claude = ClaudeUsageParser.parse(claudeOut, now: date("2026-09-20 16:40"), calendar: cal)
check("claude parsed", claude != nil)
check("claude session 37", claude?.window("claude.session")?.usedPercent == 37)
check("claude session reset", label(claude?.window("claude.session")?.resetsAt) == "2026-09-20 19:10", label(claude?.window("claude.session")?.resetsAt))
check("claude week 81 weekly", claude?.window("claude.week.all-models")?.usedPercent == 81 && claude?.window("claude.week.all-models")?.kind == .weekly)
check("claude Fable is a model limit", claude?.window("claude.week.fable")?.kind == .model)
check("claude insights 24h", claude?.insights24h == [Insight(percent: 91, text: "at >150k context"), Insight(percent: 87, text: "from subagent-heavy sessions")],
      String(describing: claude?.insights24h))
check("claude insights 7d", claude?.insights7d.count == 1)
let noSession = ClaudeUsageParser.parse("Current week (all models): 67% used · resets Nov 9 at 4:59am (Asia/Taipei)", now: date("2026-11-08 20:00"), calendar: cal)
check("no session line = not started", noSession?.window("claude.session")?.notStarted == true)
check("reset 4:59am", label(noSession?.window("claude.week.all-models")?.resetsAt) == "2026-11-09 04:59")
check("year rolls forward", label(ClaudeUsageParser.parseReset("Jan 2 at 5am", now: date("2026-12-31 23:00"), calendar: cal)) == "2027-01-02 05:00")
check("garbage rejected", ClaudeUsageParser.parse("no limits here at all") == nil)

// MARK: Codex app-server

let codexJSON = """
{"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":45,"windowDurationMins":10080,"resetsAt":1794396675},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"},"rateLimitResetCredits":{"availableCount":2,"credits":[{"status":"available","expiresAt":1796068420},{"status":"available","expiresAt":1796164080}]}}
"""
let codexPlus = """
{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1794180000},"secondary":{"usedPercent":30,"windowDurationMins":10080,"resetsAt":1794600000},"planType":"plus"}}
"""
func json(_ s: String) -> [String: Any] { (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:] }
let codex = CodexUsageParser.parse(limits: json(codexJSON), account: nil)
check("codex weekly only", codex?.windows.count == 1 && codex?.windows.first?.kind == .weekly && codex?.hasSessionWindow == false)
check("codex plan name", codex?.plan == "Pro Lite")
check("codex free resets", codex?.freeResets == 2 && codex?.freeResetExpires == Date(timeIntervalSince1970: 1796068420))
let plus = CodexUsageParser.parse(limits: json(codexPlus), account: nil)
check("codex plus has 5-hour", plus?.hasSessionWindow == true && plus?.windows.first?.kind == .session && plus?.windows.first?.duration == 18000)

// MARK: Grok billing

let grokJSON = """
{"config":{"creditUsagePercent":29.0,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-11-05T03:41:12.218+00:00","end":"2026-11-12T03:41:12.218+00:00"},"prepaidBalance":{"val":1250},"isUnifiedBillingUser":true},"subscription_tier":"SuperGrok"}
"""
let grok = GrokUsageParser.parse(json(grokJSON))
check("grok 29%", grok?.windows.first?.usedPercent == 29)
check("grok weekly, 7 days", grok?.windows.first?.duration == 7 * 24 * 3600, String(describing: grok?.windows.first?.duration))
check("grok plan", grok?.plan == "SuperGrok")
check("grok prepaid cents", grok?.prepaidBalance == 12.5)

// MARK: agy /usage

let agyNow = ISO8601DateFormatter().date(from: "2026-11-08T19:02:01Z")!
let agyOut = """
Gemini Models\tWeekly Limit Remaining\t100%\t2026-11-14T10:52:24Z
Gemini Models\tFive Hour Limit Remaining\t100%\t2026-11-09T00:02:01Z
Claude and GPT models\tWeekly Limit Remaining\t40%\t2026-11-15T19:02:01Z
Claude and GPT models\tFive Hour Limit Remaining\t75%\t2026-11-08T22:00:00Z
Gemini 4 Argon\tGemini 4 Argon Weekly Limit\t99%\t2026-11-14T10:51:33Z
"""
let agy = AgyUsageParser.parse(agyOut, now: agyNow)
check("agy 5 rows", agy?.windows.count == 5)
check("agy gemini 5h not started", agy?.window("agy.gemini-models.session")?.notStarted == true)
check("agy claude 5h used 25", agy?.window("agy.claude-and-gpt-models.session")?.usedPercent == 25)
check("agy claude week used 60", agy?.window("agy.claude-and-gpt-models.week")?.usedPercent == 60)
check("agy single model", agy?.window("agy.gemini-4-argon.week")?.kind == .model)
check("agy groups", agy.map(AgyUsageParser.groups) == ["Gemini Models", "Claude and GPT models"])

// MARK: Pace

let weekStart = date("2026-11-02 12:00")
func week(_ used: Double, at now: String) -> Pace? {
    Pace.of(UsageWindow(id: "w", title: "w", shortTitle: "w", kind: .weekly, usedPercent: used,
                        resetsAt: weekStart.addingTimeInterval(7 * 24 * 3600), duration: 7 * 24 * 3600), now: date(now))
}
check("pace behind", week(20, at: "2026-11-06 12:00") == .behind)
check("pace on", week(57, at: "2026-11-06 12:00") == .onPace)
if case .ahead(let runsOut)? = week(80, at: "2026-11-06 12:00") {
    check("pace ahead runs out before reset", runsOut < weekStart.addingTimeInterval(7 * 24 * 3600))
} else {
    check("pace ahead", false, String(describing: week(80, at: "2026-11-06 12:00")))
}
check("pace reached", week(100, at: "2026-11-06 12:00") == .reached(backAt: weekStart.addingTimeInterval(7 * 24 * 3600)))
check("no pace early in window", week(5, at: "2026-11-02 14:00") == nil)

// MARK: Versions

check("versions", VersionParser.parse("2.1.282 (Claude Code)") == "2.1.282"
      && VersionParser.parse("codex-cli 0.166.0") == "0.166.0"
      && VersionParser.parse("grok 1.0.70 (f50904eaee6c)") == "1.0.70"
      && VersionParser.parse("1.5.3") == "1.5.3")

print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURES")
print("For a live read of every installed CLI: ./.build/debug/ClaudePrewarm --probe")
exit(failures == 0 ? 0 : 1)
