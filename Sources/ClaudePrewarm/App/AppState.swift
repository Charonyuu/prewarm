import AppKit
import Combine
import Foundation

enum PanelTab: Hashable {
    case overview
    case provider(Provider)

    var key: String {
        switch self {
        case .overview: return "overview"
        case .provider(let p): return p.rawValue
        }
    }

    init(key: String?) {
        if let key, let p = Provider(rawValue: key) { self = .provider(p) } else { self = .overview }
    }
}

/// What the menu bar icon should say.
enum MenuBarStatus: Equatable {
    case ready
    case warming
    case nearLimit
    case problem
    case setup
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var providers: [Provider: ProviderRuntime] = [:]
    @Published private(set) var logs: [WarmLog]
    @Published private(set) var history: [String: [String: Int]]
    @Published private(set) var nextWarmupAt: Date?
    @Published private(set) var lastWarm: [WarmTarget: Date]
    @Published private(set) var detecting = false
    @Published var selectedTab: PanelTab {
        didSet { SettingsStore.selectedTab = selectedTab.key }
    }

    private let schedule = ScheduleService()
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private var alerts: [String: AlertRecord]
    /// Set by the preview renderer so nothing runs a real CLI.
    private(set) var isPreview = false

    /// A repeat warm inside this window is pointless.
    static let duplicateWarmWindow: TimeInterval = 10 * 60

    init() {
        settings = SettingsStore.loadSettings()
        logs = SettingsStore.loadLogs()
        history = SettingsStore.loadHistory()
        lastWarm = SettingsStore.loadLastWarm()
        alerts = SettingsStore.loadAlerts()
        selectedTab = PanelTab(key: SettingsStore.selectedTab)
        for provider in Provider.allCases { providers[provider] = ProviderRuntime() }
    }

    func runtime(_ provider: Provider) -> ProviderRuntime { providers[provider] ?? ProviderRuntime() }

    // MARK: - Lifecycle

    func start() {
        NotificationService.requestAuthorizationIfNeeded()
        syncLaunchAtLogin()
        registerSleepWakeObservers()
        rescheduleNextWarmup()
        detectTools { [weak self] in
            self?.rescheduleNextWarmup()
            self?.refreshAll()
        }
        startRefreshTimer()
    }

    func stop() {
        schedule.cancel()
        refreshTimer?.invalidate()
        refreshTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    /// Finds each CLI and its version, off the main thread.
    func detectTools(then done: (() -> Void)? = nil) {
        guard !isPreview, !detecting else { done?(); return }
        detecting = true
        Task.detached(priority: .userInitiated) {
            let paths = BinaryFinder.findAll()
            let versions = await withTaskGroup(of: (Provider, String?).self) { group -> [Provider: String] in
                for (provider, path) in paths {
                    group.addTask { (provider, ProviderServices.version(of: provider, path: path)) }
                }
                var found: [Provider: String] = [:]
                for await (provider, version) in group { found[provider] = version }
                return found
            }
            await MainActor.run {
                for provider in Provider.allCases {
                    var r = self.runtime(provider)
                    r.path = paths[provider]
                    r.version = versions[provider]
                    if r.path == nil {
                        r.status = .notInstalled
                        r.usage = nil
                    } else if r.status == .notInstalled || r.status == .unknown {
                        r.status = .unknown
                    }
                    self.providers[provider] = r
                }
                self.detecting = false
                done?()
            }
        }
    }

    // MARK: - Derived values

    var visibleProviders: [Provider] { Provider.allCases.filter { settings.shows($0) } }

    var anyInstalled: Bool { Provider.allCases.contains { runtime($0).isInstalled } }

    var isWarming: Bool { providers.values.contains { $0.isWarming } }

    /// Highest limit across shown tools, with the tool it belongs to.
    var highest: (provider: Provider, percent: Double)? {
        visibleProviders
            .compactMap { p in runtime(p).usage?.highestPercent.map { (p, $0) } }
            .max { $0.1 < $1.1 }
    }

    /// The 5-hour and weekly numbers for the "Bars" menu bar style.
    var barValues: (session: Double?, week: Double?) {
        guard let p = highest?.provider, let usage = runtime(p).usage else { return (nil, nil) }
        let session = usage.sessionWindows.compactMap(\.usedPercent).max()
        let week = usage.windows.filter { $0.kind == .weekly }.compactMap(\.usedPercent).max()
        return (session, week)
    }

    var menuBarStatus: MenuBarStatus {
        if detecting && !anyInstalled { return .ready }
        if !anyInstalled { return .setup }
        if isWarming { return .warming }
        if providers.values.contains(where: { $0.lastWarmError != nil }) { return .problem }
        if let highest, highest.percent >= 80 { return .nearLimit }
        return .ready
    }

    /// Targets the schedule would warm right now.
    var scheduledTargets: [WarmTarget] { WarmTarget.allCases.filter { settings.wantsWarm($0) && canWarm($0) } }

    func canWarm(_ target: WarmTarget) -> Bool {
        let r = runtime(target.provider)
        guard r.isInstalled, r.status != .notSignedIn, settings.shows(target.provider) else { return false }
        if target == .codex { return r.usage?.hasSessionWindow == true }
        return true
    }

    /// Why a target can't be warmed, for the menus.
    func warmBlocker(_ target: WarmTarget) -> String? {
        let r = runtime(target.provider)
        if !r.isInstalled { return "not installed" }
        if r.status == .notSignedIn { return "sign in first" }
        if target == .codex, r.usage?.hasSessionWindow != true { return "no 5-hour window" }
        if let last = lastWarm[target], Clock.now.timeIntervalSince(last) < Self.duplicateWarmWindow { return "warmed just now" }
        return nil
    }

    var nextWarmupLabel: String {
        guard settings.hasWorkDay else { return "No work days set" }
        guard let next = nextWarmupAt else { return "Not scheduled" }
        return DateCalculator.relativeLabel(for: next)
    }

    var nextWarmupIsSkipped: Bool {
        guard let skip = settings.skipWarmAt, let next = nextWarmupAt else { return false }
        return abs(skip.timeIntervalSince(next)) < 60
    }

    func lastWarmLabel(_ provider: Provider) -> String? {
        let dates = WarmTarget.allCases.filter { $0.provider == provider }.compactMap { lastWarm[$0] }
        guard let latest = dates.max(), Clock.isToday(latest) else { return nil }
        return "Warmed \(DateCalculator.timeLabel(for: latest))"
    }

    /// Where the 5-hour window started by the last warm ends.
    func windowEnd(for provider: Provider) -> Date? {
        if let session = runtime(provider).usage?.sessionWindows.first(where: { !$0.notStarted && $0.resetsAt != nil }),
           let reset = session.resetsAt, reset > Clock.now {
            return reset
        }
        let dates = WarmTarget.allCases.filter { $0.provider == provider }.compactMap { lastWarm[$0] }
        guard let latest = dates.max() else { return nil }
        let end = latest.addingTimeInterval(5 * 3600)
        return end > Clock.now ? end : nil
    }

    // MARK: - Settings

    func update(settings newValue: AppSettings) {
        guard newValue.isValid else { return }
        let old = settings
        settings = newValue
        SettingsStore.save(newValue)
        if old.launchAtLogin != newValue.launchAtLogin,
           let message = LoginItemService.setEnabled(newValue.launchAtLogin) {
            NSLog("Prewarm: %@", message)
        }
        if old.refreshMinutes != newValue.refreshMinutes { startRefreshTimer() }
        if old.shownProviders != newValue.shownProviders {
            if case .provider(let p) = selectedTab, !newValue.shows(p) { selectedTab = .overview }
            refreshAll()
        }
        rescheduleNextWarmup()
        NotificationCenter.default.post(name: .prewarmSettingsChanged, object: nil)
    }

    func edit(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        update(settings: copy)
    }

    func setShown(_ provider: Provider, _ shown: Bool) {
        edit { s in
            if shown {
                if !s.shownProviders.contains(provider) { s.shownProviders.append(provider) }
                s.shownProviders.sort { Provider.allCases.firstIndex(of: $0)! < Provider.allCases.firstIndex(of: $1)! }
            } else {
                s.shownProviders.removeAll { $0 == provider }
            }
        }
    }

    func skipNextWarm() {
        guard let next = nextWarmupAt else { return }
        edit { $0.skipWarmAt = next }
    }

    func unskipNextWarm() {
        edit { $0.skipWarmAt = nil }
    }

    private func syncLaunchAtLogin() {
        guard !isPreview, LoginItemService.isInstalledCopy else { return }
        // 2.0 renamed the bundle (Claude Prewarm.app → Prewarm.app). A login item
        // registered from the old path would start nothing, so register again
        // whenever the app now lives somewhere else.
        LoginItemService.refreshIfMoved(enabled: settings.launchAtLogin)
        let actual = LoginItemService.isEnabled
        guard actual != settings.launchAtLogin else { return }
        if settings.launchAtLogin {
            if LoginItemService.setEnabled(true) != nil {
                settings.launchAtLogin = false
                SettingsStore.save(settings)
            }
        } else {
            settings.launchAtLogin = actual
            SettingsStore.save(settings)
        }
    }

    // MARK: - Scheduling

    func rescheduleNextWarmup() {
        schedule.cancel()
        let next = schedule.calculateNextWarmup(settings: settings, from: Date())
        nextWarmupAt = next
        guard let next, !isPreview else { return }
        schedule.schedule(date: next) { [weak self] in
            Task { @MainActor in await self?.runScheduledWarm(scheduledFor: next) }
        }
    }

    private func runScheduledWarm(scheduledFor date: Date) async {
        if let skip = settings.skipWarmAt, abs(skip.timeIntervalSince(date)) < 60 {
            edit { $0.skipWarmAt = nil }
            return
        }
        await warm(scheduledTargets, type: .scheduled)
        rescheduleNextWarmup()
    }

    // MARK: - Warming

    func warmNow(_ targets: [WarmTarget]? = nil) async {
        let chosen = targets ?? scheduledTargets
        await warm(chosen.filter { canWarm($0) }, type: .manual)
        rescheduleNextWarmup()
    }

    private func warm(_ targets: [WarmTarget], type: WarmType) async {
        let now = Date()
        let due = targets.filter { target in
            guard let path = runtime(target.provider).path, !path.isEmpty else { return false }
            guard !runtime(target.provider).warming.contains(target) else { return false }
            if let last = lastWarm[target], now.timeIntervalSince(last) < Self.duplicateWarmWindow { return false }
            return true
        }
        guard !due.isEmpty else { return }

        for target in due {
            providers[target.provider]?.warming.insert(target)
            providers[target.provider]?.lastWarmError = nil
        }

        let jobs = due.map { ($0, runtime($0.provider).path ?? "") }
        let results: [(WarmTarget, Result<TimeInterval, Error>)] = await withTaskGroup(of: (WarmTarget, Result<TimeInterval, Error>).self) { group in
            for (target, path) in jobs {
                group.addTask {
                    do { return (target, .success(try ProviderServices.warm(target, path: path))) }
                    catch { return (target, .failure(error)) }
                }
            }
            var collected: [(WarmTarget, Result<TimeInterval, Error>)] = []
            for await item in group { collected.append(item) }
            return collected
        }

        var succeeded: [WarmTarget] = []
        var failed: [(WarmTarget, String)] = []
        for (target, result) in results {
            providers[target.provider]?.warming.remove(target)
            switch result {
            case .success(let seconds):
                lastWarm[target] = now
                succeeded.append(target)
                append(WarmLog(date: now, type: type, success: true, error: nil, target: target, seconds: seconds))
            case .failure(let error):
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                if (error as? CLIError)?.isSignIn == true { providers[target.provider]?.status = .notSignedIn }
                providers[target.provider]?.lastWarmError = message
                failed.append((target, message))
                append(WarmLog(date: now, type: type, success: false, error: message, target: target))
            }
        }
        SettingsStore.save(lastWarm: lastWarm)

        if settings.notifyWarmFailure, !failed.isEmpty {
            let names = failed.map { $0.0.label }.joined(separator: ", ")
            var body = failed.first?.1 ?? ""
            if !succeeded.isEmpty { body += " \(succeeded.map(\.label).joined(separator: ", ")) warmed fine." }
            postAlert(id: "warm.fail.\(Int(now.timeIntervalSince1970))",
                      title: "The \(DateCalculator.timeLabel(for: now)) warm-up didn't run for \(names)",
                      body: body)
        }
        if settings.notifyWarmSuccess, !succeeded.isEmpty, type != .manual {
            let ends = DateCalculator.timeLabel(for: now.addingTimeInterval(5 * 3600))
            postAlert(id: "warm.ok.\(Int(now.timeIntervalSince1970))",
                      title: "Warmed \(succeeded.map(\.label).joined(separator: ", "))",
                      body: "These windows end around \(ends).")
        }

        let touched = Set(due.map(\.provider))
        for provider in touched { refresh(provider) }
    }

    private func append(_ log: WarmLog) {
        logs.insert(log, at: 0)
        logs = Array(logs.prefix(60))
        SettingsStore.save(logs)
    }

    func clearHistory() {
        logs = []
        history = [:]
        SettingsStore.save(logs)
        SettingsStore.save(history: history)
    }

    // MARK: - Reading limits

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        guard !isPreview else { return }
        let timer = Timer(timeInterval: Double(settings.refreshMinutes) * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Called when the menu opens; skips tools read in the last minute.
    func refreshOnOpen() {
        guard settings.refreshOnOpen else { return }
        for provider in visibleProviders {
            let fetched = runtime(provider).usage?.fetchedAt ?? .distantPast
            if Date().timeIntervalSince(fetched) > 60 { refresh(provider) }
        }
    }

    func refreshAll() {
        for provider in visibleProviders { refresh(provider) }
    }

    func refresh(_ provider: Provider) {
        guard !isPreview else { return }
        let r = runtime(provider)
        guard let path = r.path, !r.isLoading else { return }
        providers[provider]?.isLoading = true
        Task.detached(priority: .utility) {
            let result: Result<ProviderUsage, Error>
            do { result = .success(try ProviderServices.readUsage(provider, path: path)) }
            catch { result = .failure(error) }
            await MainActor.run { self.apply(result, to: provider) }
        }
    }

    private func apply(_ result: Result<ProviderUsage, Error>, to provider: Provider) {
        var r = runtime(provider)
        r.isLoading = false
        switch result {
        case .success(var usage):
            let old = r.usage
            if provider == .agy { usage = reconcileAgy(usage, previous: old) }
            r.usage = usage
            r.status = .ready
            r.readError = nil
            providers[provider] = r
            recordHistory(provider, usage)
            evaluateAlerts(provider, old: old, new: usage)
        case .failure(let error):
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let cli = error as? CLIError {
                switch cli {
                case .notSignedIn: r.status = .notSignedIn
                case .notInstalled: r.status = .notInstalled; r.path = nil
                default: r.status = r.usage == nil ? .failed(message) : r.status
                }
            } else {
                r.status = r.usage == nil ? .failed(message) : r.status
            }
            r.readError = message
            providers[provider] = r
        }
    }

    /// agy reports an unstarted 5-hour window and one started a moment ago the
    /// same way. A recent warm-up of that group, or a reset time that held still
    /// between two reads, means it has started.
    private func reconcileAgy(_ usage: ProviderUsage, previous: ProviderUsage?) -> ProviderUsage {
        var usage = usage
        for index in usage.windows.indices where usage.windows[index].kind == .session && usage.windows[index].notStarted {
            let window = usage.windows[index]
            let target: WarmTarget = (window.group ?? "").lowercased().contains("gemini") ? .agyGemini : .agyOther
            if let last = lastWarm[target], usage.fetchedAt.timeIntervalSince(last) < 5 * 3600 {
                usage.windows[index].notStarted = false
                continue
            }
            if let previous, usage.fetchedAt.timeIntervalSince(previous.fetchedAt) > 30,
               let before = previous.window(window.id)?.resetsAt, let now = window.resetsAt,
               abs(before.timeIntervalSince(now)) < 5 {
                usage.windows[index].notStarted = false
            }
        }
        return usage
    }

    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    private func recordHistory(_ provider: Provider, _ usage: ProviderUsage) {
        guard let value = usage.highestPercent else { return }
        let key = Self.dayKey(usage.fetchedAt)
        var days = history[provider.rawValue] ?? [:]
        days[key] = max(days[key] ?? 0, Int(value.rounded()))
        let cutoff = Self.dayKey(Date().addingTimeInterval(-35 * 24 * 3600))
        days = days.filter { $0.key >= cutoff }
        history[provider.rawValue] = days
        SettingsStore.save(history: history)
    }

    // MARK: - Alerts

    private func postAlert(id: String, title: String, body: String) {
        let deliverAt = settings.quietEnds(after: Date())
        NotificationService.post(id: id, title: title, body: body, at: deliverAt)
    }

    private func watches(_ window: UsageWindow) -> Bool {
        switch settings.alertScope {
        case .both: return window.kind != .model
        case .session: return window.kind == .session
        case .weekly: return window.kind == .weekly
        }
    }

    private func displayName(_ provider: Provider, _ window: UsageWindow) -> String {
        if provider == .agy, let group = window.group {
            return group.lowercased().contains("gemini") ? "agy Gemini" : "agy Claude & GPT"
        }
        return provider.name
    }

    private func evaluateAlerts(_ provider: Provider, old: ProviderUsage?, new usage: ProviderUsage) {
        let thresholds = settings.alertThresholds.sorted()
        for window in usage.windows where watches(window) {
            guard let used = window.usedPercent else { continue }
            var record = alerts[window.id] ?? AlertRecord(level: 0, resetsAt: window.resetsAt)
            if let reset = window.resetsAt, let previous = record.resetsAt, abs(reset.timeIntervalSince(previous)) > 600 {
                record.level = 0
            }
            if window.notStarted { record.level = 0 }
            let crossed = thresholds.filter { Double($0) <= used }.max() ?? 0
            if used + 25 < Double(record.level) { record.level = crossed }

            if crossed > record.level {
                let name = displayName(provider, window)
                let title: String
                var body: String
                if window.kind == .session {
                    title = "\(name) is at \(crossed)% of this 5-hour window"
                    body = window.resetsAt.map {
                        "Resets at \(DateCalculator.timeLabel(for: $0)), in \(DateCalculator.durationLabel($0.timeIntervalSinceNow))."
                    } ?? ""
                } else {
                    title = "\(name) is at \(crossed)% this week"
                    body = window.resetsAt.map { "Resets \(DateCalculator.compactLabel(for: $0))." } ?? ""
                    if case .ahead(let date)? = Pace.of(window) {
                        body = "At this pace it runs out around \(DateCalculator.compactLabel(for: date)). " + body
                    }
                }
                postAlert(id: "limit.\(window.id).\(crossed)", title: title, body: body)
                record.level = crossed
            }
            record.resetsAt = window.resetsAt
            alerts[window.id] = record

            scheduleResetReminder(provider, window)
        }
        SettingsStore.save(alerts: alerts)
    }

    /// A reminder timed for the moment a well-used window resets.
    private func scheduleResetReminder(_ provider: Provider, _ window: UsageWindow) {
        let id = "reset.\(window.id)"
        let wanted: Bool
        switch window.kind {
        case .session: wanted = settings.notifySessionReset && (window.usedPercent ?? 0) >= 50
        case .weekly: wanted = settings.notifyWeeklyReset && (window.usedPercent ?? 0) >= 25
        case .model: wanted = false
        }
        guard wanted, let reset = window.resetsAt, reset > Date(), !settings.isQuiet(at: reset) else {
            NotificationService.cancel([id])
            return
        }
        let name = displayName(provider, window)
        if window.kind == .session {
            NotificationService.post(id: id, title: "\(name)'s window just reset",
                                     body: "A fresh 5-hour window starts with your next request.", at: reset)
        } else {
            NotificationService.post(id: id, title: "\(name)'s weekly limit just reset",
                                     body: "The week starts again at 0%.", at: reset)
        }
    }

    func sendTestNotification() {
        NotificationService.post(id: "test.\(Date().timeIntervalSince1970)",
                                 title: "Claude is at 80% of this 5-hour window",
                                 body: "This is a test. Real alerts look like this.")
    }

    // MARK: - Sign-in and links

    /// Opens Terminal on the tool's sign-in command.
    func openTerminal(running command: String) {
        let source = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard error != nil else { return }
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    // MARK: - Sleep / wake

    private func registerSleepWakeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let wake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleWake() }
        }
        observers.append(wake)
    }

    private func handleWake() async {
        let grace = Double(settings.wakeGraceMinutes) * 60
        if let missed = DateCalculator.missedWarmup(settings: settings, at: Date(), grace: grace) {
            let skipped = settings.skipWarmAt.map { abs($0.timeIntervalSince(missed)) < 60 } ?? false
            let targets = scheduledTargets.filter { (lastWarm[$0] ?? .distantPast) < missed }
            if !skipped, !targets.isEmpty {
                await warm(targets, type: .wakeRecovery)
            }
        }
        rescheduleNextWarmup()
        refreshAll()
    }

    // MARK: - Preview data

    #if DEBUG
    /// Fills the state with fixed numbers so screenshots never touch a real CLI.
    func loadPreview(_ apply: (inout [Provider: ProviderRuntime], inout [WarmTarget: Date], inout [WarmLog], inout [String: [String: Int]], inout Date?) -> Void) {
        isPreview = true
        var p = providers, w = lastWarm, l = logs, h = history, n = nextWarmupAt
        apply(&p, &w, &l, &h, &n)
        providers = p; lastWarm = w; logs = l; history = h; nextWarmupAt = n
    }

    func setPreviewSettings(_ s: AppSettings) { settings = s }
    #endif
}

extension AppState {
    static let shared = AppState()
}

extension Notification.Name {
    static let prewarmSettingsChanged = Notification.Name("prewarmSettingsChanged")
}
