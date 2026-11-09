#if DEBUG
import AppKit
import SwiftUI

/// `ClaudePrewarm --render-screenshots <dir>` renders the real views with fixed
/// numbers into PNGs for the README and the website. Nothing runs a CLI.
@MainActor
enum ScreenshotRenderer {
    static func run(into directory: String) {
        SettingsStore.defaults = UserDefaults(suiteName: "com.charonyuu.ClaudePrewarm.preview") ?? .standard
        SettingsStore.defaults.removePersistentDomain(forName: "com.charonyuu.ClaudePrewarm.preview")
        let url = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        // A weekday morning, so labels read the same whenever this runs.
        var day = Date()
        while [1, 7].contains(Calendar.current.component(.weekday, from: day)) {
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? day
        }
        Clock.override = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: day)

        let state = AppState()
        fill(state)

        func panel(_ tab: PanelTab) -> AnyView {
            state.selectedTab = tab
            return AnyView(MenuPanelView(openSettings: {}, quit: {}).environmentObject(state))
        }

        let shots: [(String, () -> AnyView, Bool)] = [
            ("panel-overview-light", { panel(.overview) }, false),
            ("panel-overview-dark", { panel(.overview) }, true),
            ("panel-claude-light", { panel(.provider(.claude)) }, false),
            ("panel-claude-dark", { panel(.provider(.claude)) }, true),
            ("panel-codex-light", { panel(.provider(.codex)) }, false),
            ("panel-grok-light", { panel(.provider(.grok)) }, false),
            ("panel-agy-light", { panel(.provider(.agy)) }, false),
        ] + SettingsPage.allCases.map { page in
            ("settings-\(page.rawValue)-light", { AnyView(SettingsShot(page: page).environmentObject(state)) }, false)
        } + [
            ("settings-schedule-dark", { AnyView(SettingsShot(page: .schedule).environmentObject(state)) }, true),
        ] + (1...4).map { step in
            ("onboarding-\(step)-light", { AnyView(OnboardingShot(step: step).environmentObject(state)) }, false)
        }

        for (name, make, dark) in shots {
            render(make(), dark: dark, to: url.appendingPathComponent("\(name).png"))
        }
        state.selectedTab = .overview
        render(AnyView(ShareCard().environmentObject(state)), dark: false, to: url.appendingPathComponent("og.png"))
        print("Rendered \(shots.count + 1) images into \(url.path)")
    }

    private static func render(_ view: AnyView, dark: Bool, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        window.orderOut(nil)
    }

    private struct SettingsShot: View {
        let page: SettingsPage
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) {
                        Circle().fill($0).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .overlay(Text(page.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.title))
                .padding(.horizontal, 14)
                .frame(height: 30)
                SettingsView(page: .constant(page))
            }
            .background(Theme.window)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
    }

    private struct OnboardingShot: View {
        let step: Int
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) {
                        Circle().fill($0).frame(width: 12, height: 12)
                    }
                    Spacer()
                }
                .overlay(Text("Welcome").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.title))
                .padding(.horizontal, 14)
                .frame(height: 30)
                OnboardingView(step: .constant(step), finish: {})
            }
            .background(Theme.window)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
        }
    }

    /// 1200×630 share image: name, line, and the real panel.
    private struct ShareCard: View {
        var body: some View {
            HStack(alignment: .center, spacing: 56) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        AppMark(size: 48)
                        Text("Prewarm").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.title)
                    }
                    Text("Start your 5-hour windows\nbefore you sit down.")
                        .font(.system(size: 50, weight: .heavy))
                        .foregroundStyle(Theme.title)
                        .lineSpacing(4)
                    Text("Claude · Codex · Grok · agy limits in one menu bar app.")
                        .font(.system(size: 22)).foregroundStyle(Theme.label)
                }
                MenuPanelView(openSettings: {}, quit: {})
                    .scaleEffect(0.78, anchor: .center)
                    .frame(width: 270, height: 560)
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
            }
            .padding(.horizontal, 72)
            .frame(width: 1200, height: 630)
            .background(LinearGradient(colors: [Color(hex: 0xFFEBDC), Color(hex: 0xFBFAF8)], startPoint: .top, endPoint: .bottom))
            .environment(\.colorScheme, .light)
        }
    }

    // MARK: - Numbers

    private static func fill(_ state: AppState) {
        let now = Clock.now
        let h: TimeInterval = 3600
        let d: TimeInterval = 24 * h
        let warmedAt = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(-2 * h)
        let sessionReset = warmedAt.addingTimeInterval(5 * h)

        var settings = AppSettings.default
        settings.alertThresholds = [80, 95]
        settings.days[5] = DaySchedule(enabled: true, hour: 10, minute: 0)
        state.setPreviewSettings(settings)

        state.loadPreview { providers, lastWarm, logs, history, next in
            providers[.claude] = ProviderRuntime(
                path: "\(NSHomeDirectory())/.local/bin/claude", version: "2.1.282", status: .ready,
                usage: ProviderUsage(
                    fetchedAt: now, plan: nil,
                    windows: [
                        UsageWindow(id: "claude.session", title: "Current session · 5 hours", shortTitle: "5-hour", kind: .session,
                                    usedPercent: 38, resetsAt: sessionReset, duration: 5 * h),
                        UsageWindow(id: "claude.week.all-models", title: "This week · all models", shortTitle: "Week", kind: .weekly,
                                    usedPercent: 31, resetsAt: now.addingTimeInterval(4 * d + 19 * h), duration: 7 * d),
                        UsageWindow(id: "claude.week.fable", title: "This week · Fable", shortTitle: "Fable", kind: .model,
                                    usedPercent: 0, resetsAt: now.addingTimeInterval(4 * d + 19 * h), duration: 7 * d)
                    ],
                    insights24h: [
                        Insight(percent: 91, text: "at >150k context"),
                        Insight(percent: 87, text: "from subagent-heavy sessions"),
                        Insight(percent: 56, text: "while 4+ sessions ran in parallel")
                    ],
                    insights7d: [
                        Insight(percent: 88, text: "at >150k context"),
                        Insight(percent: 73, text: "from subagent-heavy sessions"),
                        Insight(percent: 58, text: "from sessions active for 8+ hours")
                    ]
                )
            )
            var codexUsage = ProviderUsage(
                fetchedAt: now, plan: "Pro Lite",
                windows: [UsageWindow(id: "codex.week", title: "This week", shortTitle: "Week", kind: .weekly,
                                      usedPercent: 45, resetsAt: now.addingTimeInterval(2 * d + 10 * h), duration: 7 * d)]
            )
            codexUsage.freeResets = 2
            codexUsage.freeResetExpires = now.addingTimeInterval(22 * d)
            codexUsage.creditBalance = "0"
            providers[.codex] = ProviderRuntime(path: "\(NSHomeDirectory())/.nvm/versions/node/v20/bin/codex",
                                                version: "0.166.0", status: .ready, usage: codexUsage)

            var grokUsage = ProviderUsage(
                fetchedAt: now, plan: "SuperGrok",
                windows: [UsageWindow(id: "grok.credits", title: "This week · credits", shortTitle: "Week", kind: .weekly,
                                      usedPercent: 29, resetsAt: now.addingTimeInterval(3 * d + 2 * h), duration: 7 * d)]
            )
            grokUsage.prepaidBalance = 0
            grokUsage.onDemandEnabled = false
            grokUsage.periodStart = now.addingTimeInterval(-4 * d + 2 * h)
            grokUsage.periodEnd = now.addingTimeInterval(3 * d + 2 * h)
            providers[.grok] = ProviderRuntime(path: "\(NSHomeDirectory())/.grok/bin/grok", version: "1.0.70", status: .ready, usage: grokUsage)

            providers[.agy] = ProviderRuntime(
                path: "\(NSHomeDirectory())/.local/bin/agy", version: "1.5.3", status: .ready,
                usage: ProviderUsage(fetchedAt: now, plan: nil, windows: [
                    UsageWindow(id: "agy.gemini-models.week", title: "This week", shortTitle: "Gemini week", group: "Gemini Models",
                                kind: .weekly, usedPercent: 4, resetsAt: now.addingTimeInterval(5 * d + 9 * h), duration: 7 * d),
                    UsageWindow(id: "agy.gemini-models.session", title: "5 hours", shortTitle: "Gemini 5h", group: "Gemini Models",
                                kind: .session, usedPercent: 6, resetsAt: sessionReset, duration: 5 * h),
                    UsageWindow(id: "agy.claude-and-gpt-models.week", title: "This week", shortTitle: "Claude/GPT week", group: "Claude and GPT models",
                                kind: .weekly, usedPercent: 2, resetsAt: now.addingTimeInterval(6 * d + 17 * h), duration: 7 * d),
                    UsageWindow(id: "agy.claude-and-gpt-models.session", title: "5 hours", shortTitle: "Claude/GPT 5h", group: "Claude and GPT models",
                                kind: .session, usedPercent: 1, resetsAt: sessionReset, duration: 5 * h),
                    UsageWindow(id: "agy.gemini-4-argon.week", title: "Gemini 4 Argon · week", shortTitle: "Gemini 4 Argon",
                                kind: .model, usedPercent: 1, resetsAt: now.addingTimeInterval(5 * d + 9 * h), duration: 7 * d)
                ])
            )

            lastWarm[.claude] = warmedAt
            lastWarm[.agyGemini] = warmedAt
            lastWarm[.agyOther] = warmedAt

            let cal = Calendar.current
            func day(_ offset: Int, _ hour: Int, _ minute: Int) -> Date {
                let base = cal.date(byAdding: .day, value: offset, to: now) ?? now
                return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
            }
            logs = [
                WarmLog(date: warmedAt, type: .scheduled, success: true, error: nil, target: .claude, seconds: 3.1),
                WarmLog(date: warmedAt, type: .scheduled, success: true, error: nil, target: .agyGemini, seconds: 4.6),
                WarmLog(date: warmedAt, type: .scheduled, success: true, error: nil, target: .agyOther, seconds: 5.2),
                WarmLog(date: day(-3, 7, 0), type: .scheduled, success: true, error: nil, target: .claude, seconds: 2.8),
                WarmLog(date: day(-4, 10, 12), type: .manual, success: true, error: nil, target: .claude, seconds: 3.4),
                WarmLog(date: day(-5, 7, 41), type: .wakeRecovery, success: false, error: "Claude Code timed out after 45 seconds.", target: .claude)
            ]

            func series(_ values: [Int]) -> [String: Int] {
                var out: [String: Int] = [:]
                for (i, v) in values.enumerated() {
                    out[AppState.dayKey(cal.date(byAdding: .day, value: i - 6, to: now) ?? now)] = v
                }
                return out
            }
            history = [
                "claude": series([62, 88, 71, 54, 0, 12, 38]),
                "codex": series([18, 24, 31, 37, 39, 41, 45]),
                "grok": series([0, 0, 6, 14, 20, 26, 29]),
                "agy": series([0, 4, 0, 9, 0, 0, 6])
            ]
            next = DateCalculator.nextWarmup(settings: settings, from: now)
        }
    }
}
#endif
