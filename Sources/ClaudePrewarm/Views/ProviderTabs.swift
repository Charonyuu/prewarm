import SwiftUI

/// One tool's tab. Setup problems come first; otherwise warm-up, limits and extras.
struct ProviderTab: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        let r = state.runtime(provider)
        VStack(alignment: .leading, spacing: 12) {
            ProviderHeader(provider: provider)
            switch r.status {
            case .notInstalled:
                InstallCard(provider: provider)
            case .notSignedIn:
                SignInCard(provider: provider)
            default:
                content(r)
            }
        }
    }

    @ViewBuilder private func content(_ r: ProviderRuntime) -> some View {
        switch provider {
        case .claude:
            WarmCard(provider: .claude, targets: [.claude])
            LimitsCard(provider: .claude)
            InsightsCard()
        case .codex:
            LimitsCard(provider: .codex)
            if let usage = r.usage, usage.freeResets != nil || usage.creditBalance != nil {
                CodexResetsCard(usage: usage)
            }
            if r.usage?.hasSessionWindow == true {
                WarmCard(provider: .codex, targets: [.codex])
            } else if let usage = r.usage {
                Card(title: "Warm-up") {
                    NoteText(text: "\(usage.plan ?? "Your plan") has a weekly limit only, so there is no 5-hour window to start early. If your plan gets one, warm-up switches on here.")
                }
            }
        case .grok:
            LimitsCard(provider: .grok)
            if let usage = r.usage { GrokBillingCard(usage: usage) }
            Card(title: "Warm-up") {
                NoteText(text: "Grok counts weekly credits, so there is no 5-hour window to start early.")
            }
        case .agy:
            WarmCard(provider: .agy, targets: [.agyGemini, .agyOther])
            AgyGroups()
        }
    }
}

private struct ProviderHeader: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        let r = state.runtime(provider)
        HStack(spacing: 10) {
            ProviderGlyph(provider: provider, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(provider == .agy ? "agy" : provider.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.title)
                    if let plan = r.usage?.plan { Chip(text: plan) }
                }
                Text(subtitle(r)).font(.system(size: 11.5)).foregroundStyle(Theme.label).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func subtitle(_ r: ProviderRuntime) -> String {
        var parts: [String] = []
        if let version = r.version { parts.append("\(provider.cliName) \(version)") } else { parts.append(provider.cliName) }
        if r.isLoading {
            parts.append("checking…")
        } else if let fetched = r.usage?.fetchedAt {
            parts.append("updated \(DateCalculator.agoLabel(fetched))")
        } else if r.status == .notInstalled {
            parts.append("not found")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Setup cards

private struct InstallCard: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        Card(title: "Not installed") {
            NoteText(text: "\(provider.cliName) isn't on this Mac. Install it and sign in, and this tab fills in by itself.")
            Button {
                state.open(provider.installURL)
            } label: {
                HStack(spacing: 7) { Image(systemName: "arrow.down.circle"); Text("How to install \(provider.cliName)") }
            }
            .buttonStyle(AccentButtonStyle())
            HStack(spacing: 8) {
                Button("Check again") { state.detectTools { state.refresh(provider) } }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Hide this tab") { state.setShown(provider, false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct SignInCard: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        Card(title: "Not signed in") {
            NoteText(text: "\(provider.cliName) is installed but has no account yet. Sign in once in Terminal and Prewarm picks it up the next time this menu opens.")
            Button {
                state.openTerminal(running: provider.signInCommand)
            } label: {
                HStack(spacing: 7) { Image(systemName: "terminal"); Text("Sign in to \(provider.name)") }
            }
            .buttonStyle(AccentButtonStyle())
            HStack(spacing: 4) {
                Text("Opens Terminal and runs")
                Text(provider.signInCommand).font(.system(size: 11.5, design: .monospaced))
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.label)
            HStack(spacing: 8) {
                Button("I've signed in") { state.refresh(provider) }.buttonStyle(SecondaryButtonStyle())
                Button("Hide this tab") { state.setShown(provider, false) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

// MARK: - Warm-up

private struct WarmCard: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider
    let targets: [WarmTarget]

    var body: some View {
        let r = state.runtime(provider)
        let warming = targets.contains { r.warming.contains($0) }
        let scheduled = targets.filter { state.settings.wantsWarm($0) }
        Card(title: "Warm-up") {
            KeyValueRow(label: "Next warm-up", value: nextValue(scheduled))
            if provider == .agy, !scheduled.isEmpty {
                KeyValueRow(label: "Groups", value: scheduled.count == 2 ? "Gemini, Claude & GPT" : scheduled[0] == .agyGemini ? "Gemini" : "Claude & GPT")
            }
            if let end = state.windowEnd(for: provider) {
                KeyValueRow(label: "This window ends around", value: DateCalculator.timeLabel(for: end))
            }
            if let error = r.lastWarmError {
                MessageBox(text: error + " It tries again at the next warm-up, or warm now.")
            }
            Button {
                Task { await state.warmNow(targets) }
            } label: {
                HStack(spacing: 7) {
                    if warming {
                        Spinner(color: .white)
                        Text("Warming \(provider.name)…")
                    } else {
                        Image(systemName: "play.fill").font(.system(size: 10))
                        Text(r.lastWarmError != nil ? "Try again now" : "Warm \(provider.name) now")
                    }
                }
            }
            .buttonStyle(AccentButtonStyle())
            .disabled(warming || !targets.contains { state.canWarm($0) } || targets.allSatisfy { state.warmBlocker($0) != nil })
            if !warming, let blocker = targets.compactMap({ state.warmBlocker($0) }).first, targets.allSatisfy({ state.warmBlocker($0) != nil }) {
                Text("Can't warm right now: \(blocker).").font(.system(size: 11.5)).foregroundStyle(Theme.label)
            }
        }
    }

    private func nextValue(_ scheduled: [WarmTarget]) -> String {
        guard !scheduled.isEmpty else { return "Off" }
        return state.nextWarmupLabel + (state.nextWarmupIsSkipped ? " (skipped)" : "")
    }
}

// MARK: - Limits

private struct LimitsCard: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        let r = state.runtime(provider)
        Card(title: provider == .grok ? "This week" : "Limits") {
            if let usage = r.usage {
                ForEach(usage.windows.filter { provider == .claude || $0.kind != .model }) { window in
                    MeterView(window: window, loading: r.isLoading)
                }
                if let error = r.readError {
                    Text("Last check failed: \(error)").font(.system(size: 11.5)).foregroundStyle(Theme.warningText)
                }
            } else if case .failed(let message) = r.status {
                MessageBox(text: message, tone: .warning)
                Button("Try again") { state.refresh(provider) }.buttonStyle(SecondaryButtonStyle())
            } else {
                MeterView(window: UsageWindow(id: "loading", title: "Reading limits…", shortTitle: "", kind: .weekly), loading: true)
            }
        }
    }
}

private struct InsightsCard: View {
    @EnvironmentObject private var state: AppState
    @State private var range = 0

    var body: some View {
        if let usage = state.runtime(.claude).usage, !usage.insights24h.isEmpty || !usage.insights7d.isEmpty {
            let list = range == 0 ? usage.insights24h : usage.insights7d
            Card(title: "What uses your limits",
                 trailing: AnyView(PillSegment(options: [(0, "24h"), (1, "7d")], selection: $range))) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(list.prefix(4).enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(item.percent)%").fontWeight(.semibold).frame(width: 36, alignment: .trailing)
                            Text(item.text).foregroundStyle(Theme.title).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 12.5))
                    }
                    if list.isEmpty { NoteText(text: "Nothing to show for this range yet.") }
                }
            }
        }
    }
}

private struct CodexResetsCard: View {
    @EnvironmentObject private var state: AppState
    let usage: ProviderUsage

    var body: some View {
        Card(title: "Free resets") {
            if let count = usage.freeResets {
                KeyValueRow(label: "Full resets available", value: "\(count)")
            }
            if let expires = usage.freeResetExpires {
                KeyValueRow(label: "First one expires", value: DateCalculator.dayLabel(for: expires))
            }
            if let balance = usage.creditBalance {
                KeyValueRow(label: "Credit balance", value: balance)
            }
            if (usage.freeResets ?? 0) > 0 {
                Button("Open Codex to use a reset") { state.openTerminal(running: "codex") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct GrokBillingCard: View {
    @EnvironmentObject private var state: AppState
    let usage: ProviderUsage

    var body: some View {
        Card(title: "Billing") {
            if let plan = usage.plan { KeyValueRow(label: "Plan", value: plan) }
            if let start = usage.periodStart, let end = usage.periodEnd {
                KeyValueRow(label: "Period", value: "\(short(start)) – \(short(end))")
            }
            if let prepaid = usage.prepaidBalance {
                KeyValueRow(label: "Prepaid balance", value: String(format: "$%.2f", prepaid))
            }
            if let onDemand = usage.onDemandEnabled {
                KeyValueRow(label: "On-demand usage", value: onDemand ? "On" : "Off")
            }
            Button("Manage billing on grok.com") {
                state.open(URL(string: "https://grok.com/?_s=usage")!)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func short(_ date: Date) -> String {
        DateCalculator.dayLabel(for: date).split(separator: " ").dropFirst().joined(separator: " ")
    }
}

private struct AgyGroups: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let r = state.runtime(.agy)
        if let usage = r.usage {
            ForEach(AgyUsageParser.groups(usage), id: \.self) { group in
                Card(title: group.lowercased().contains("gemini") ? "Gemini models" : group.lowercased().contains("claude") ? "Claude and GPT models" : group) {
                    ForEach(usage.windows.filter { $0.group == group }.sorted { $0.kind == .session && $1.kind != .session }) { window in
                        MeterView(window: window, loading: r.isLoading)
                    }
                }
            }
            let singles = usage.windows.filter { $0.kind == .model }
            if !singles.isEmpty {
                Card(title: "Single models") {
                    ForEach(singles) { window in
                        MeterView(window: window, thin: true, showPace: false)
                    }
                }
            }
        } else if case .failed(let message) = r.status {
            Card(title: "Limits") {
                MessageBox(text: message, tone: .warning)
                Button("Try again") { state.refresh(.agy) }.buttonStyle(SecondaryButtonStyle())
            }
        } else {
            Card(title: "Limits") {
                MeterView(window: UsageWindow(id: "loading", title: "Reading limits…", shortTitle: "", kind: .weekly), loading: true)
            }
        }
    }
}
