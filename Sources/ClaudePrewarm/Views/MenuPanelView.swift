import SwiftUI

/// The panel under the menu bar icon: header, tool tabs, the selected tab, footer.
struct MenuPanelView: View {
    @EnvironmentObject private var state: AppState
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader()
            TabStrip()
            Group {
                switch state.selectedTab {
                case .overview: OverviewTab()
                case .provider(let provider): ProviderTab(provider: provider)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            footer
        }
        .frame(width: 340)
        .background(Theme.window)
        .focusEffectDisabled()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
    }

    private var footer: some View {
        HStack(spacing: 0) {
            MenuRowButton(icon: "gearshape", title: "Settings…", shortcut: "⌘,", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            MenuRowButton(icon: "power", title: "Quit", shortcut: "⌘Q", action: quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .padding(.top, 12)
    }
}

// MARK: - Header

private struct PanelHeader: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            AppMark(size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Prewarm")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.title)
                HStack(spacing: 6) {
                    StatusDot(color: status.color)
                    Text(status.text).lineLimit(1)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.label)
            }
            Spacer(minLength: 0)
            Button {
                state.detectTools { state.refreshAll() }
            } label: {
                Group {
                    if loading {
                        Spinner(color: Theme.label, size: 12)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                    }
                }
                .foregroundStyle(Theme.label)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Check usage now")
            .accessibilityLabel("Refresh usage")
            .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var loading: Bool {
        state.detecting || state.providers.values.contains { $0.isLoading }
    }

    private var status: (text: String, color: Color) {
        let warming = WarmTarget.allCases.filter { state.runtime($0.provider).warming.contains($0) }
        if !warming.isEmpty {
            let names = Array(Set(warming.map(\.provider.name))).sorted()
            return ("Warming \(names.joined(separator: " and "))…", Theme.brand)
        }
        if state.providers.values.contains(where: { $0.lastWarmError != nil }) {
            return ("Last warm-up failed", Theme.danger)
        }
        if !state.anyInstalled && !state.detecting { return ("No tools found yet", Theme.warning) }
        if state.nextWarmupIsSkipped, let next = state.nextWarmupAt {
            return ("\(DateCalculator.relativeLabel(for: next)) warm-up skipped", Theme.warning)
        }
        if state.settings.hasWorkDay, !state.scheduledTargets.isEmpty {
            return ("Next warm-up \(state.nextWarmupLabel)", Theme.good)
        }
        return ("Watching your limits", Theme.good)
    }
}

// MARK: - Tabs

private struct TabStrip: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let tabs: [PanelTab] = [.overview] + state.visibleProviders.map { .provider($0) }
        HStack(spacing: 3) {
            ForEach(tabs, id: \.self) { tab in
                TabButton(tab: tab, selected: state.selectedTab == tab) {
                    state.selectedTab = tab
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
        .padding(.horizontal, 10)
    }
}

private struct TabButton: View {
    @EnvironmentObject private var state: AppState
    let tab: PanelTab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                glyph
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Theme.title : Theme.label)
                    .lineLimit(1)
                meter
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .padding(.bottom, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.tabOn : .clear)
                    .shadow(color: .black.opacity(selected ? 0.10 : 0), radius: 1, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var label: String {
        if case .provider(let p) = tab { return p.name }
        return "Overview"
    }

    @ViewBuilder private var glyph: some View {
        switch tab {
        case .overview:
            GlyphShape(kind: .overview)
                .stroke(selected ? Theme.title : Theme.label, lineWidth: 1.5)
                .frame(width: 16, height: 16)
        case .provider(let p):
            ProviderGlyph(provider: p)
        }
    }

    @ViewBuilder private var meter: some View {
        if case .provider(let p) = tab, let percent = state.runtime(p).usage?.highestPercent {
            MeterBar(percent: max(percent, 2), height: 3).frame(width: 26)
        } else {
            Color.clear.frame(width: 26, height: 3)
        }
    }

    private var accessibility: String {
        if case .provider(let p) = tab, let percent = state.runtime(p).usage?.highestPercent {
            return "\(p.name), \(Int(percent))% used"
        }
        return label
    }
}

// MARK: - Overview

struct OverviewTab: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            ForEach(state.visibleProviders) { provider in
                OverviewCard(provider: provider)
            }
            if state.visibleProviders.isEmpty {
                Card { NoteText(text: "Every tab is hidden. Turn tools back on in Settings › General.") }
            }
            WarmBar()
        }
    }
}

private struct OverviewCard: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        let r = state.runtime(provider)
        Button {
            state.selectedTab = .provider(provider)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    ProviderGlyph(provider: provider)
                    Text(provider.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.title)
                    if let plan = r.usage?.plan { Chip(text: plan) }
                    Spacer(minLength: 6)
                    meta(r)
                }
                content(r)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func meta(_ r: ProviderRuntime) -> some View {
        Group {
            if r.isWarming {
                HStack(spacing: 5) { Spinner(size: 11); Text("Warming…") }
            } else if r.status == .notInstalled {
                Text("Not installed")
            } else if r.status == .notSignedIn {
                Text("Sign in needed").foregroundStyle(Theme.warningText)
            } else if r.lastWarmError != nil {
                HStack(spacing: 5) { StatusDot(color: Theme.danger); Text("Warm-up failed") }
            } else if let warmed = state.lastWarmLabel(provider) {
                HStack(spacing: 5) { StatusDot(color: Theme.good); Text(warmed) }
            } else if let usage = r.usage, !usage.hasSessionWindow {
                Text(provider == .grok ? "weekly credits" : "weekly only")
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Theme.label)
    }

    @ViewBuilder private func content(_ r: ProviderRuntime) -> some View {
        if r.status == .notInstalled {
            NoteText(text: "Not on this Mac. Hide this tool in Settings › General.")
        } else if r.status == .notSignedIn {
            NoteText(text: "Open the \(provider.name) tab to sign in.")
        } else if let usage = r.usage {
            let cells = cellsFor(usage)
            HStack(alignment: .top, spacing: 12) {
                ForEach(cells.indices, id: \.self) { index in
                    cells[index].frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if case .failed(let message) = r.status {
            NoteText(text: message)
        } else {
            HStack(spacing: 12) {
                MiniMeter(title: "Checking…", value: nil, detail: " ")
                MiniMeter(title: " ", value: nil, detail: " ")
            }
        }
    }

    private func cellsFor(_ usage: ProviderUsage) -> [AnyView] {
        var windows: [UsageWindow]
        if provider == .agy {
            windows = usage.sessionWindows
            if windows.isEmpty { windows = usage.windows.filter { $0.kind == .weekly } }
        } else {
            windows = [usage.sessionWindows.first, usage.windows.first { $0.kind == .weekly }].compactMap { $0 }
        }
        var cells = windows.prefix(2).map { AnyView(MiniMeter(window: $0)) }
        if cells.count < 2 {
            if provider == .codex, let resets = usage.freeResets {
                cells.append(AnyView(MiniStat(title: "Free resets", value: "\(resets)",
                    detail: usage.freeResetExpires.map { "first expires \(DateCalculator.dayLabel(for: $0).split(separator: " ").dropFirst().joined(separator: " "))" } ?? " ")))
            } else if provider == .grok, let prepaid = usage.prepaidBalance {
                cells.append(AnyView(MiniStat(title: "Prepaid", value: String(format: "$%.2f", prepaid),
                    detail: usage.onDemandEnabled == true ? "on-demand on" : "on-demand off")))
            }
        }
        return cells
    }
}

private struct MiniMeter: View {
    var title: String
    var value: Double?
    var detail: String
    var notStarted = false

    init(title: String, value: Double?, detail: String) {
        self.title = title
        self.value = value
        self.detail = detail
    }

    init(window: UsageWindow) {
        title = window.shortTitle
        value = window.usedPercent
        notStarted = window.notStarted
        if window.notStarted {
            detail = "not started"
        } else if let reset = window.resetsAt {
            detail = "resets \(DateCalculator.compactLabel(for: reset))"
        } else {
            detail = window.resetText.map { "resets \($0)" } ?? " "
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(Theme.label).lineLimit(1)
                Spacer(minLength: 4)
                Text(notStarted ? "0%" : value.map { "\(Int($0.rounded()))%" } ?? "—")
                    .fontWeight(.semibold).foregroundStyle(Theme.title)
            }
            .font(.system(size: 11.5))
            MeterBar(percent: notStarted ? 0 : value.map { max($0, 1) }, height: 4)
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.label).lineLimit(1)
        }
    }
}

private struct MiniStat: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).foregroundStyle(Theme.label)
                Spacer(minLength: 4)
                Text(value).fontWeight(.semibold).foregroundStyle(Theme.title)
            }
            .font(.system(size: 11.5))
            Spacer().frame(height: 4)
            Text(detail).font(.system(size: 11)).foregroundStyle(Theme.label).lineLimit(1)
        }
    }
}

// MARK: - Warm bar

struct WarmBar: View {
    @EnvironmentObject private var state: AppState
    @State private var showMenu = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(nextLabel).font(.system(size: 11)).foregroundStyle(Theme.label).lineLimit(1)
                Text(nextText).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.title).lineLimit(1)
            }
            Spacer(minLength: 6)
            if state.isWarming {
                Button {} label: { HStack(spacing: 7) { Spinner(color: .white); Text("Warming…") } }
                    .buttonStyle(AccentButtonStyle(fullWidth: false))
                    .disabled(true)
            } else {
                HStack(spacing: 1) {
                    Button {
                        Task { await state.warmNow() }
                    } label: {
                        HStack(spacing: 6) { Image(systemName: "play.fill").font(.system(size: 10)); Text("Warm now") }
                            .fixedSize()
                    }
                    .buttonStyle(AccentButtonStyle(fullWidth: false, corners: .init(topLeading: 9, bottomLeading: 9, bottomTrailing: 0, topTrailing: 0)))
                    .disabled(state.scheduledTargets.isEmpty)

                    Button { showMenu.toggle() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).frame(width: 14)
                    }
                    .buttonStyle(AccentButtonStyle(fullWidth: false, corners: .init(topLeading: 0, bottomLeading: 0, bottomTrailing: 9, topTrailing: 9)))
                    .accessibilityLabel("Choose what to warm")
                    .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                        WarmMenu { showMenu = false }.environmentObject(state)
                    }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.line))
    }

    private var nextLabel: String {
        "Next warm-up"
    }

    private var nextText: String {
        guard state.settings.hasWorkDay, state.nextWarmupAt != nil else { return "None scheduled" }
        return state.nextWarmupLabel + (state.nextWarmupIsSkipped ? " (skipped)" : "")
    }
}

struct WarmMenu: View {
    @EnvironmentObject private var state: AppState
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WARM NOW")
                .font(.system(size: 11, weight: .semibold)).tracking(0.4)
                .foregroundStyle(Theme.label)
                .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
            ForEach(WarmTarget.allCases) { target in
                let blocker = state.warmBlocker(target)
                Button {
                    close()
                    Task { await state.warmNow([target]) }
                } label: {
                    HStack(spacing: 9) {
                        ProviderGlyph(provider: target.provider)
                        Text(target.label).foregroundStyle(Theme.title)
                        Spacer(minLength: 12)
                        Text(blocker ?? "5-hour window").font(.system(size: 11.5)).foregroundStyle(Theme.label)
                    }
                    .font(.system(size: 13))
                    .padding(.vertical, 6).padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(blocker != nil)
                .opacity(blocker != nil ? 0.5 : 1)
            }
            Divider().padding(.vertical, 3)
            Button {
                close()
                Task { await state.warmNow() }
            } label: {
                HStack {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Warm everything scheduled")
                    Spacer()
                }
            }
            .buttonStyle(AccentButtonStyle(height: 30))
            .disabled(state.scheduledTargets.isEmpty)
        }
        .padding(8)
        .frame(width: 280)
    }
}
