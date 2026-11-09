import AppKit

@main
enum ClaudePrewarmMain {
    static func main() {
        // Writing to a CLI that already exited must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState.shared
    private var statusItem: StatusItemController?
    private lazy var settingsWindow = SettingsWindowController(state: state)
    private lazy var onboardingWindow = OnboardingWindowController(state: state)
    private var hotKey: HotKey?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--disable-login-item") {
            let message = LoginItemService.setEnabled(false)
            print(message ?? "Login item for this copy is off.")
            exit(0)
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--probe") {
            Probe.run(warm: Array(CommandLine.arguments.dropFirst(index + 1)))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-screenshots"),
           index + 1 < CommandLine.arguments.count {
            ScreenshotRenderer.run(into: CommandLine.arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        #endif

        NSApp.setActivationPolicy(.accessory)
        let firstLaunch = SettingsStore.isFirstLaunch
        let controller = StatusItemController(state: state)
        controller.openSettings = { [weak self] page in self?.settingsWindow.show(page: page) }
        statusItem = controller
        state.start()
        updateHotKey()
        settingsObserver = NotificationCenter.default.addObserver(forName: .prewarmSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateHotKey() }
        }

        // Open a surface straight away; handy for support and for checking a build.
        let args = CommandLine.arguments
        if args.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.statusItem?.togglePanel() }
        }
        if let index = args.firstIndex(of: "--show-settings") {
            let page = index + 1 < args.count ? SettingsPage(rawValue: args[index + 1]) : nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.settingsWindow.show(page: page ?? .general) }
        }
        if args.contains("--show-welcome") {
            onboardingWindow.show()
        }

        if firstLaunch {
            onboardingWindow.onFinish = { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.statusItem?.togglePanel() }
            }
            onboardingWindow.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.stop()
    }

    /// Reopening the app from Finder or Spotlight opens settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsWindow.show(page: nil)
        return false
    }

    private func updateHotKey() {
        if state.settings.hotkeyEnabled {
            if hotKey == nil {
                hotKey = HotKey { [weak self] in
                    Task { @MainActor in self?.statusItem?.togglePanel() }
                }
            }
        } else {
            hotKey = nil
        }
    }
}
