import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, schedule, tools, notifications, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Schedule"
        case .tools: return "Tools"
        case .notifications: return "Notifications"
        case .history: return "History"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .schedule: return "clock.fill"
        case .tools: return "terminal.fill"
        case .notifications: return "bell.fill"
        case .history: return "chart.bar.fill"
        case .about: return "info.circle.fill"
        }
    }
}

/// Settings apply as you change them, the macOS way; there is no Save button.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Binding var page: SettingsPage

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch page {
                    case .general: GeneralPage()
                    case .schedule: SchedulePage()
                    case .tools: ToolsPage()
                    case .notifications: NotificationsPage()
                    case .history: HistoryPage()
                    case .about: AboutPage()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.window)
        }
        .frame(width: 760, height: 556)
        .background(Theme.window)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPage.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: 0x8E8E93)))
                        Text(item.title).font(.system(size: 13))
                            .foregroundStyle(page == item ? .white : Theme.title)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(page == item ? Theme.accent : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .frame(width: 196)
        .background(Theme.sidebar)
    }
}

// MARK: - Building blocks

struct PageTitle: View {
    let title: String
    var lead: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.title)
            if let lead {
                Text(lead).font(.system(size: 12.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label).padding(.leading, 2)
            }
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedLayout()) { content }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))
        }
    }
}

/// Puts a hairline between the rows of a group.
private struct DividedLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Rectangle().fill(Theme.line).frame(height: 1)
            }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let label: String
    var detail: String?
    var leading: AnyView?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            if let leading { leading }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 13)).foregroundStyle(Theme.title)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.label).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 10)
            control
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
    }
}

struct PillToggle: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(isOn ? .white : Theme.chipText)
                .background(Capsule().fill(isOn ? Theme.accent : Theme.chip))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

extension View {
    func settingsSwitch() -> some View {
        self.toggleStyle(PrewarmSwitchStyle()).labelsHidden()
    }
}

/// A small switch drawn in SwiftUI, green when on, matching the design in
/// every window state.
struct PrewarmSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Theme.good : Theme.track).frame(width: 32, height: 19)
                Circle().fill(.white).frame(width: 15, height: 15)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isOn)
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

private extension AppState {
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { value in self.edit { $0[keyPath: keyPath] = value } })
    }
}

/// 24-hour time field for one hour/minute pair.
struct TimeField: View {
    let hour: Int
    let minute: Int
    let set: (Int, Int) -> Void

    var body: some View {
        DatePicker("", selection: Binding(
            get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                set(c.hour ?? hour, c.minute ?? minute)
            }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.field)
        .labelsHidden()
        .environment(\.locale, Locale(identifier: "en_GB"))
        .fixedSize()
    }
}

// MARK: - General

private struct GeneralPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageTitle(title: "General")
        SettingsGroup(title: "Startup") {
            SettingsRow(label: "Launch at login") { Toggle("", isOn: state.binding(\.launchAtLogin)).settingsSwitch() }
        }
        SettingsGroup(title: "Menu bar") {
            SettingsRow(label: "Show", detail: "The number is the limit closest to running out, across every tool.") {
                Picker("", selection: state.binding(\.menuBarStyle)) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(label: "Open the menu with ⌥⌘P") { Toggle("", isOn: state.binding(\.hotkeyEnabled)).settingsSwitch() }
        }
        SettingsGroup(title: "Usage") {
            SettingsRow(label: "Check usage every") {
                Picker("", selection: state.binding(\.refreshMinutes)) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow(label: "Also check when the menu opens") { Toggle("", isOn: state.binding(\.refreshOnOpen)).settingsSwitch() }
            SettingsRow(label: "Tabs", detail: "Hide tools you don't use.") {
                HStack(spacing: 6) {
                    ForEach(Provider.allCases) { provider in
                        PillToggle(title: provider.name, isOn: state.settings.shows(provider)) {
                            state.setShown(provider, !state.settings.shows(provider))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Schedule

struct DayTiles: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DateCalculator.weekdayOrder, id: \.self) { weekday in
                let day = state.settings.day(weekday)
                VStack(spacing: 5) {
                    Button {
                        state.edit { s in
                            var d = s.day(weekday)
                            d.enabled.toggle()
                            s.days[weekday] = d
                        }
                    } label: {
                        Text(DateCalculator.weekdayShort(weekday))
                            .font(.system(size: 12.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        .foregroundStyle(day.enabled ? .white : Theme.label)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(day.enabled ? Theme.accent : Theme.chip))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(DateCalculator.weekdayShort(weekday)), \(day.enabled ? "starts \(day.timeLabel)" : "off")")
                    TimeField(hour: day.hour, minute: day.minute) { h, m in
                        state.edit { s in
                            var d = s.day(weekday)
                            d.hour = h
                            d.minute = m
                            d.enabled = true
                            s.days[weekday] = d
                        }
                    }
                    .opacity(day.enabled ? 1 : 0.45)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
    }
}

/// The next work day as four steps: warm, start, reset, next reset.
struct ScheduleTimeline: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let warm = state.nextWarmupAt {
            let start = DateCalculator.workStart(forWarm: warm, settings: state.settings)
            let reset = warm.addingTimeInterval(5 * 3600)
            let steps: [(String, String, Bool)] = [
                (DateCalculator.timeLabel(for: warm), "Warm-up", true),
                (DateCalculator.timeLabel(for: start), "You start", false),
                (DateCalculator.timeLabel(for: reset), "Window resets", true),
                (DateCalculator.timeLabel(for: reset.addingTimeInterval(5 * 3600)), "Next reset", false)
            ]
            VStack(alignment: .leading, spacing: 8) {
                Text(DateCalculator.relativeLabel(for: warm).components(separatedBy: " ").first ?? "")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.label)
                HStack(alignment: .top, spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Theme.track).frame(height: 2)
                                Circle()
                                    .fill(steps[i].2 ? Theme.brand : Theme.card)
                                    .overlay(Circle().strokeBorder(steps[i].2 ? Theme.brand : Theme.label, lineWidth: 2))
                                    .frame(width: 10, height: 10)
                            }
                            Text(steps[i].0).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.title)
                            Text(steps[i].1).font(.system(size: 11.5)).foregroundStyle(Theme.label)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
        } else {
            Text(state.settings.hasWorkDay ? "No warm-up scheduled." : "Turn on a day above to schedule warm-ups.")
                .font(.system(size: 12)).foregroundStyle(Theme.label).padding(12)
        }
    }
}

private struct SchedulePage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageTitle(title: "Schedule", lead: "Warm-ups run before you start, so each 5-hour window resets earlier in your day. Click a day to turn it on or off.")
        SettingsGroup(title: "Work days") {
            DayTiles()
            ScheduleTimeline()
        }
        SettingsGroup(title: "Warm-up") {
            SettingsRow(label: "Warm before I start") {
                Picker("", selection: state.binding(\.prewarmOffsetMinutes)) {
                    ForEach(AppSettings.offsetChoices, id: \.self) { Text(AppSettings.offsetLabel($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            SettingsRow(label: "If the Mac was asleep") {
                Picker("", selection: state.binding(\.wakeGraceMinutes)) {
                    ForEach(AppSettings.graceChoices, id: \.self) { Text(AppSettings.graceLabel($0)).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            if let next = state.nextWarmupAt {
                SettingsRow(label: "Next warm-up", detail: state.nextWarmupIsSkipped ? "Skipped. The one after runs as usual." : nil) {
                    HStack(spacing: 8) {
                        Text(DateCalculator.relativeLabel(for: next)).font(.system(size: 13, weight: .semibold))
                        if state.nextWarmupIsSkipped {
                            Button("Undo") { state.unskipNextWarm() }
                        } else {
                            Button("Skip it") { state.skipNextWarm() }
                        }
                    }
                }
            }
        }
        SettingsGroup(title: "What to warm") {
            SettingsRow(label: "Claude", leading: AnyView(ProviderGlyph(provider: .claude))) {
                Toggle("", isOn: state.binding(\.warmClaude)).settingsSwitch()
            }
            SettingsRow(label: "agy · Gemini models", leading: AnyView(ProviderGlyph(provider: .agy))) {
                Toggle("", isOn: state.binding(\.warmAgyGemini)).settingsSwitch()
            }
            SettingsRow(label: "agy · Claude and GPT models", leading: AnyView(ProviderGlyph(provider: .agy))) {
                Toggle("", isOn: state.binding(\.warmAgyOther)).settingsSwitch()
            }
            SettingsRow(label: "Codex", detail: codexDetail, leading: AnyView(ProviderGlyph(provider: .codex))) {
                Toggle("", isOn: state.binding(\.warmCodex)).settingsSwitch()
                    .disabled(state.runtime(.codex).usage?.hasSessionWindow != true)
            }
        }
    }

    private var codexDetail: String? {
        let usage = state.runtime(.codex).usage
        guard let usage else { return state.runtime(.codex).isInstalled ? "Waiting for Codex's limits" : "Not installed" }
        return usage.hasSessionWindow ? nil : "No 5-hour window on \(usage.plan ?? "your plan")"
    }
}

// MARK: - Tools

private struct ToolsPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageTitle(title: "Tools", lead: "Prewarm asks the command-line tools you're already signed in to. No API keys, nothing stored.")
        ForEach(Provider.allCases) { provider in
            ToolGroup(provider: provider)
        }
        HStack {
            Spacer()
            Button(state.detecting ? "Looking…" : "Look for tools again") { state.detectTools { state.refreshAll() } }
                .disabled(state.detecting)
        }
    }
}

private struct ToolGroup: View {
    @EnvironmentObject private var state: AppState
    let provider: Provider

    var body: some View {
        let r = state.runtime(provider)
        SettingsGroup {
            HStack(spacing: 10) {
                ProviderGlyph(provider: provider, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(provider.cliName).font(.system(size: 13, weight: .semibold))
                        statusLabel(r)
                    }
                    if let path = r.path {
                        Text(shortPath(path) + (r.version.map { " · \($0)" } ?? ""))
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(Theme.label)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 10)
                actions(r)
                Toggle("", isOn: Binding(get: { state.settings.shows(provider) }, set: { state.setShown(provider, $0) }))
                    .settingsSwitch()
                    .help("Show \(provider.name) in the menu")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            if let extra {
                HStack {
                    Text(extra.0).font(.system(size: 12.5)).foregroundStyle(Theme.label)
                    Spacer()
                    Text(extra.1).font(.system(size: 12.5))
                }
                .padding(.leading, 44)
                .padding(.trailing, 12)
                .padding(.vertical, 9)
            }
        }
    }

    private var extra: (String, String)? {
        switch provider {
        case .claude: return ("Warms with", "Haiku, the smallest model")
        case .agy: return ("Warms", groupsText)
        case .codex: return ("Limits from", "codex app-server")
        case .grok: return ("Limits from", "grok agent, billing")
        }
    }

    private var groupsText: String {
        let s = state.settings
        switch (s.warmAgyGemini, s.warmAgyOther) {
        case (true, true): return "Gemini, and Claude & GPT"
        case (true, false): return "Gemini only"
        case (false, true): return "Claude & GPT only"
        default: return "Nothing (see Schedule)"
        }
    }

    @ViewBuilder private func statusLabel(_ r: ProviderRuntime) -> some View {
        switch r.status {
        case .notInstalled:
            Text("Not installed").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label)
        case .notSignedIn:
            Text("Not signed in").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warningText)
        case .ready:
            Text("Signed in" + (r.usage?.plan.map { " · \($0)" } ?? ""))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.goodText)
        case .failed:
            Text("Couldn't read limits").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.warningText)
        case .unknown:
            Text(r.path == nil ? "Looking…" : "Checking…").font(.system(size: 12)).foregroundStyle(Theme.label)
        }
    }

    @ViewBuilder private func actions(_ r: ProviderRuntime) -> some View {
        switch r.status {
        case .notInstalled:
            Button("How to install") { state.open(provider.installURL) }
        case .notSignedIn:
            Button("Sign in") { state.openTerminal(running: provider.signInCommand) }
        default:
            EmptyView()
        }
    }

    private func shortPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        var p = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
        if let range = p.range(of: #"/\.nvm/versions/node/[^/]+"#, options: .regularExpression) {
            p.replaceSubrange(range, with: "/.nvm/…")
        }
        return p
    }
}

// MARK: - Notifications

private struct NotificationsPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageTitle(title: "Notifications")
        SettingsGroup(title: "Usage alerts") {
            SettingsRow(label: "Warn me when a limit reaches") {
                HStack(spacing: 6) {
                    ForEach(AppSettings.thresholdChoices, id: \.self) { value in
                        PillToggle(title: "\(value)%", isOn: state.settings.alertThresholds.contains(value)) {
                            state.edit { s in
                                if s.alertThresholds.contains(value) { s.alertThresholds.removeAll { $0 == value } }
                                else { s.alertThresholds.append(value); s.alertThresholds.sort() }
                            }
                        }
                    }
                }
            }
            SettingsRow(label: "Limits to watch") {
                Picker("", selection: state.binding(\.alertScope)) {
                    ForEach(AlertScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
        SettingsGroup(title: "Resets") {
            SettingsRow(label: "When a 5-hour window resets", detail: "Only if you used at least half of it.") {
                Toggle("", isOn: state.binding(\.notifySessionReset)).settingsSwitch()
            }
            SettingsRow(label: "When a weekly limit resets") {
                Toggle("", isOn: state.binding(\.notifyWeeklyReset)).settingsSwitch()
            }
        }
        SettingsGroup(title: "Warm-ups") {
            SettingsRow(label: "When a warm-up fails") { Toggle("", isOn: state.binding(\.notifyWarmFailure)).settingsSwitch() }
            SettingsRow(label: "When a scheduled warm-up works") { Toggle("", isOn: state.binding(\.notifyWarmSuccess)).settingsSwitch() }
        }
        SettingsGroup(title: "Quiet hours") {
            SettingsRow(label: "Hold alerts between", detail: "Held alerts arrive when quiet hours end.") {
                HStack(spacing: 6) {
                    TimeField(hour: state.settings.quietStart / 60, minute: state.settings.quietStart % 60) { h, m in
                        state.edit { $0.quietStart = h * 60 + m }
                    }
                    Text("and").font(.system(size: 12.5)).foregroundStyle(Theme.label)
                    TimeField(hour: state.settings.quietEnd / 60, minute: state.settings.quietEnd % 60) { h, m in
                        state.edit { $0.quietEnd = h * 60 + m }
                    }
                    Toggle("", isOn: state.binding(\.quietHoursEnabled)).settingsSwitch()
                }
            }
        }
        HStack {
            Button("Send a test notification") { state.sendTestNotification() }
            Spacer()
            Button("macOS notification settings…") {
                state.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
        }
    }
}

// MARK: - History

private struct HistoryPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        PageTitle(title: "History")
        SettingsGroup(title: "Highest use each day") {
            VStack(spacing: 8) {
                ForEach(state.visibleProviders) { provider in
                    HistoryRow(provider: provider, values: values(for: provider))
                }
                HStack(spacing: 10) {
                    Color.clear.frame(width: 92, height: 1)
                    HStack(spacing: 6) {
                        ForEach(days, id: \.self) { day in
                            Text(DateCalculator.weekdayShort(Calendar.current.component(.weekday, from: day)))
                                .font(.system(size: 10.5)).foregroundStyle(Theme.label)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    Color.clear.frame(width: 38, height: 1)
                }
            }
            .padding(12)
        }
        SettingsGroup(title: "Warm-ups") {
            if state.logs.isEmpty {
                Text("No warm-ups yet. The first scheduled one shows up here.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.label).padding(12)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                    GridRow {
                        ForEach(["When", "Tool", "How", "Result"], id: \.self) {
                            Text($0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.label)
                        }
                    }
                    .padding(.vertical, 7)
                    ForEach(state.logs.prefix(8)) { log in
                        Divider().gridCellColumns(4)
                        GridRow {
                            Text(DateCalculator.pastLabel(for: log.date))
                                .monospacedDigit()
                            Text(log.target.label)
                            Text(log.type.label)
                            Text(log.resultLabel)
                                .fontWeight(.semibold)
                                .foregroundStyle(log.success ? Theme.goodText : Theme.warningText)
                                .help(log.error ?? "")
                        }
                        .font(.system(size: 12.5))
                        .padding(.vertical, 7)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }
        }
        HStack {
            Text("Kept on this Mac only.").font(.system(size: 11.5)).foregroundStyle(Theme.label)
            Spacer()
            Button("Export CSV…") { exportCSV() }.disabled(state.logs.isEmpty)
            Button("Clear") { state.clearHistory() }.disabled(state.logs.isEmpty && state.history.isEmpty)
        }
    }

    private var days: [Date] {
        (0..<7).reversed().compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Clock.now) }
    }

    private func values(for provider: Provider) -> [Int?] {
        let record = state.history[provider.rawValue] ?? [:]
        return days.map { record[AppState.dayKey($0)] }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "prewarm-history.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let iso = ISO8601DateFormatter()
        var lines = ["date,tool,how,success,seconds,error"]
        for log in state.logs {
            let error = (log.error ?? "").replacingOccurrences(of: "\"", with: "'")
            lines.append("\(iso.string(from: log.date)),\(log.target.label),\(log.type.label),\(log.success),\(log.seconds.map { String(format: "%.1f", $0) } ?? ""),\"\(error)\"")
        }
        lines.append("")
        lines.append("day,tool,highest_percent")
        for (provider, days) in state.history.sorted(by: { $0.key < $1.key }) {
            for (day, value) in days.sorted(by: { $0.key < $1.key }) { lines.append("\(day),\(provider),\(value)") }
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct HistoryRow: View {
    let provider: Provider
    let values: [Int?]

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(spacing: 6) {
                ProviderGlyph(provider: provider, size: 13)
                Text(provider.name).font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 92, alignment: .leading)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { i in
                    let v = values[i] ?? 0
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 3, bottomLeading: 1, bottomTrailing: 1, topTrailing: 3))
                        .fill(values[i] == nil || v == 0 ? Theme.track : Theme.meterColor(Double(v)))
                        .frame(height: max(2, CGFloat(v) * 0.34))
                        .frame(maxWidth: .infinity)
                        .help(values[i].map { "\($0)%" } ?? "No data")
                }
            }
            .frame(height: 34, alignment: .bottom)
            Text(values.last.flatMap { $0 }.map { "\($0)%" } ?? "—")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    @EnvironmentObject private var state: AppState
    private let repo = URL(string: "https://github.com/Charonyuu/prewarm")!

    var body: some View {
        VStack(spacing: 8) {
            AppMark(size: 64)
            Text("Prewarm").font(.system(size: 20, weight: .bold))
            Text("Version \(ProviderServices.appVersion)").font(.system(size: 12)).foregroundStyle(Theme.label)
            Text("Starts your AI coding windows before you sit down, and keeps every limit in one menu.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                Button("Check for updates") { state.open(repo.appendingPathComponent("releases/latest")) }
                    .buttonStyle(AccentButtonStyle(fullWidth: false))
                Button("GitHub") { state.open(repo) }.buttonStyle(SecondaryButtonStyle(height: 34, fullWidth: false))
                Button("Report a problem") { state.open(repo.appendingPathComponent("issues/new")) }
                    .buttonStyle(SecondaryButtonStyle(height: 34, fullWidth: false))
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        SettingsGroup {
            SettingsRow(label: "Updating") { Text("Homebrew users: brew upgrade keeps it current").foregroundStyle(Theme.label) }
            SettingsRow(label: "Privacy") { Text("No account, no API keys, no telemetry").foregroundStyle(Theme.label) }
            SettingsRow(label: "License") { Text("MIT, open source").foregroundStyle(Theme.label) }
        }
        .font(.system(size: 13))
        Text("Not affiliated with Anthropic, OpenAI, xAI or Google. Product names belong to their owners.")
            .font(.system(size: 11.5))
            .foregroundStyle(Theme.label)
            .frame(maxWidth: .infinity)
    }
}
