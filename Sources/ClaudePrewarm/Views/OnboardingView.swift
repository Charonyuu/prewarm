import SwiftUI

/// First launch: welcome, tools found, work hours, done.
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @Binding var step: Int
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch step {
            case 1: welcome
            case 2: tools
            case 3: hours
            default: done
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(1...4, id: \.self) { i in
                        Capsule().fill(i == step ? Theme.brand : Theme.track).frame(width: i == step ? 18 : 7, height: 7)
                    }
                }
                .accessibilityLabel("Step \(step) of 4")
                Spacer()
                if step > 1 {
                    Button("Back") { step -= 1 }.buttonStyle(SecondaryButtonStyle(height: 34, fullWidth: false))
                }
                Button(step == 1 ? "Get started" : step == 4 ? "Open the menu" : "Continue") {
                    if step == 4 { finish() } else { step += 1 }
                }
                .buttonStyle(AccentButtonStyle(fullWidth: false))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 560, height: 416)
        .background(Theme.window)
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            VStack(spacing: 10) {
                AppMark(size: 64)
                Text("Welcome to Prewarm").font(.system(size: 22, weight: .bold))
                Text("Start your 5-hour windows before you sit down, and keep every AI coding limit in one menu.")
                    .font(.system(size: 13)).foregroundStyle(Theme.label)
                    .multilineTextAlignment(.center).frame(maxWidth: 400)
            }
            .frame(maxWidth: .infinity)
            SettingsGroup {
                feature("clock", "Warms Claude and agy before work, so windows reset earlier")
                feature("chart.bar", "Shows Claude, Codex, Grok and agy limits side by side")
                feature("lock", "Uses the CLIs already signed in on this Mac. No API keys")
            }
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brand).frame(width: 18)
            Text(text).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Found on this Mac").font(.system(size: 20, weight: .bold))
                Text("Prewarm reads limits from these tools. Missing one? Add it later; the menu checks again each time it opens.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup {
                ForEach(Provider.allCases) { provider in
                    let r = state.runtime(provider)
                    HStack(spacing: 10) {
                        ProviderGlyph(provider: provider, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.cliName).font(.system(size: 13, weight: .semibold))
                            Text(detail(r)).font(.system(size: 11.5)).foregroundStyle(Theme.label)
                        }
                        Spacer()
                        statusView(provider, r)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 46)
                }
            }
        }
        .onAppear { if !state.anyInstalled { state.detectTools { state.refreshAll() } } }
    }

    private func detail(_ r: ProviderRuntime) -> String {
        var parts: [String] = []
        if let v = r.version { parts.append(v) }
        if let plan = r.usage?.plan { parts.append(plan) }
        if r.path == nil, r.status == .notInstalled { parts.append("not installed") }
        return parts.isEmpty ? (state.detecting ? "Looking…" : " ") : parts.joined(separator: " · ")
    }

    @ViewBuilder private func statusView(_ provider: Provider, _ r: ProviderRuntime) -> some View {
        switch r.status {
        case .ready:
            Label("Signed in", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.goodText)
        case .notSignedIn:
            HStack(spacing: 8) {
                Text("Not signed in").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warningText)
                Button("Sign in") { state.openTerminal(running: provider.signInCommand) }
                    .buttonStyle(SecondaryButtonStyle(height: 26, fullWidth: false))
            }
        case .notInstalled:
            Button("How to install") { state.open(provider.installURL) }
                .buttonStyle(SecondaryButtonStyle(height: 26, fullWidth: false))
        case .failed:
            Text("Couldn't read").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warningText)
        case .unknown:
            if r.isLoading || state.detecting { Spinner(color: Theme.label) } else { Text("—").foregroundStyle(Theme.label) }
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("When do you usually start?").font(.system(size: 20, weight: .bold))
                Text("Click a day to turn it on or off. Each day can start at a different time.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.label)
            }
            SettingsGroup {
                DayTiles()
                SettingsRow(label: "Warm before I start") {
                    Picker("", selection: Binding(get: { state.settings.prewarmOffsetMinutes },
                                                  set: { v in state.edit { $0.prewarmOffsetMinutes = v } })) {
                        ForEach(AppSettings.offsetChoices, id: \.self) { Text(AppSettings.offsetLabel($0)).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
            }
            SettingsGroup { ScheduleTimeline() }
        }
    }

    private var done: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Spacer()
                    HStack(spacing: 4) {
                        GlyphShape(kind: .bolt).fill(Theme.title).frame(width: 13, height: 13)
                        Text("38%").font(.system(size: 12.5, weight: .medium))
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.title.opacity(0.14)))
                    Text(DateCalculator.timeLabel(for: Clock.now)).font(.system(size: 12.5, weight: .medium))
                }
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(Theme.chip)
                HStack {
                    Spacer()
                    Image(systemName: "arrow.up").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.brand)
                        .padding(.trailing, 74)
                }
                .frame(height: 54)
                .background(Theme.track.opacity(0.5))
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
            Text("It lives in your menu bar").font(.system(size: 20, weight: .bold))
            Text(firstWarmText).font(.system(size: 13)).foregroundStyle(Theme.label)
            SettingsGroup {
                SettingsRow(label: "Launch at login") {
                    Toggle("", isOn: Binding(get: { state.settings.launchAtLogin }, set: { v in state.edit { $0.launchAtLogin = v } }))
                        .settingsSwitch()
                }
                SettingsRow(label: "Warn me at 80% and 95%") {
                    Toggle("", isOn: Binding(
                        get: { !state.settings.alertThresholds.isEmpty },
                        set: { v in state.edit { $0.alertThresholds = v ? [80, 95] : [] } }
                    ))
                    .settingsSwitch()
                }
            }
        }
    }

    private var firstWarmText: String {
        guard let next = state.nextWarmupAt else { return "No warm-ups scheduled yet; set days in Settings." }
        let names = Array(Set(state.scheduledTargets.map(\.provider.name))).sorted()
        return "First warm-up: \(DateCalculator.relativeLabel(for: next))" + (names.isEmpty ? "" : " · \(names.joined(separator: " and "))")
    }
}
