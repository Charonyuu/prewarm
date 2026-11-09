import AppKit
import Combine
import SwiftUI

/// The menu bar item: left click opens the panel, right click shows a menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let state: AppState
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: MenuPanelController
    private var cancellables: Set<AnyCancellable> = []
    private var pulseTimer: Timer?
    private var pulse: CGFloat = 1
    private var appearanceObservation: NSKeyValueObservation?
    var openSettings: (SettingsPage?) -> Void = { _ in }

    init(state: AppState) {
        self.state = state
        self.panel = MenuPanelController(state: state)
        super.init()
        panel.openSettings = { [weak self] in self?.openSettings(nil) }

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.redraw() }
            }
        }

        state.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.redraw() }
            .store(in: &cancellables)
        redraw()
    }

    var isPanelShown: Bool { panel.isShown }

    func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(below: button)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            panel.close()
            showMenu(from: sender)
        } else {
            panel.toggle(below: sender)
        }
    }

    // MARK: Icon

    private func redraw() {
        guard let button = statusItem.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let status = state.menuBarStatus
        let style = state.settings.menuBarStyle
        let bars = state.barValues
        let input = MenuBarIcon.Input(
            status: status,
            style: style,
            percent: state.highest.map { Int($0.percent.rounded()) },
            session: bars.session,
            week: bars.week,
            dark: dark,
            pulse: pulse
        )
        button.image = MenuBarIcon.image(input)
        if style == .iconPercent, let percent = input.percent, status != .setup {
            button.attributedTitle = NSAttributedString(string: " \(percent)%", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium),
                .baselineOffset: 0.5
            ])
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }
        button.toolTip = tooltip
        updatePulse(status == .warming)
    }

    private var tooltip: String {
        var parts = ["Prewarm"]
        if let highest = state.highest {
            parts.append("\(highest.provider.name) at \(Int(highest.percent.rounded()))%")
        }
        if state.settings.hasWorkDay, state.nextWarmupAt != nil {
            parts.append("Next warm-up \(state.nextWarmupLabel)")
        }
        return parts.joined(separator: " · ")
    }

    private func updatePulse(_ on: Bool) {
        if on, pulseTimer == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    let t = Date().timeIntervalSinceReferenceDate
                    self.pulse = CGFloat(0.5 + 0.5 * sin(t * 4))
                    self.redraw()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            pulseTimer = timer
        } else if !on, pulseTimer != nil {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulse = 1
        }
    }

    // MARK: Right-click menu

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let targets = state.scheduledTargets
        let names = Array(NSOrderedSet(array: targets.map(\.provider.name))) as? [String] ?? []
        let warm = NSMenuItem(title: names.isEmpty ? "Warm now" : "Warm now (\(names.joined(separator: ", ")))",
                              action: #selector(warmNow), keyEquivalent: "")
        warm.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        warm.isEnabled = !targets.isEmpty && !state.isWarming
        menu.addItem(warm)

        let refresh = NSMenuItem(title: "Refresh usage", action: #selector(refreshUsage), keyEquivalent: "r")
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(refresh)
        menu.addItem(.separator())

        if let next = state.nextWarmupAt {
            let label = DateCalculator.relativeLabel(for: next)
            let skipped = state.nextWarmupIsSkipped
            let skipItem = skipped
                ? NSMenuItem(title: "Don't skip \(label)", action: #selector(unskip), keyEquivalent: "")
                : NSMenuItem(title: "Skip the \(label) warm-up", action: #selector(skip), keyEquivalent: "")
            skipItem.image = NSImage(systemSymbolName: skipped ? "arrow.uturn.backward" : "pause", accessibilityDescription: nil)
            menu.addItem(skipItem)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Prewarm", action: #selector(showAbout), keyEquivalent: "")
        about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)

        for item in menu.items { item.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func warmNow() { Task { await state.warmNow() } }
    @objc private func refreshUsage() { state.detectTools { [state] in state.refreshAll() } }
    @objc private func skip() { state.skipNextWarm() }
    @objc private func unskip() { state.unskipNextWarm() }
    @objc private func showSettings() { openSettings(nil) }
    @objc private func showAbout() { openSettings(.about) }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// A borderless panel that hangs under the status item, like a menu bar extra.
@MainActor
final class MenuPanelController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var panel: NSPanel?
    private var hosting: NSHostingController<AnyView>?
    private var monitors: [Any] = []
    private var sizeObservation: NSKeyValueObservation?
    private weak var anchor: NSView?
    var openSettings: () -> Void = {}

    init(state: AppState) {
        self.state = state
    }

    var isShown: Bool { panel?.isVisible == true }

    func toggle(below button: NSView) {
        if isShown { close() } else { show(below: button) }
    }

    func show(below button: NSView) {
        anchor = button
        let panel = self.panel ?? makePanel()
        self.panel = panel
        state.refreshOnOpen()
        position()
        panel.makeKeyAndOrderFront(nil)
        (button as? NSButton)?.highlight(true)
        installMonitors()
    }

    func close() {
        panel?.orderOut(nil)
        (anchor as? NSButton)?.highlight(false)
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    private func makePanel() -> NSPanel {
        let root = MenuPanelView(
            openSettings: { [weak self] in
                self?.close()
                self?.openSettings()
            },
            quit: { NSApp.terminate(nil) }
        )
        .environmentObject(state)
        let hosting = NSHostingController(rootView: AnyView(root))
        hosting.sizingOptions = [.preferredContentSize]
        self.hosting = hosting

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        panel.isReleasedWhenClosed = false

        sizeObservation = hosting.observe(\.preferredContentSize) { [weak self] _, _ in
            Task { @MainActor in self?.position() }
        }
        return panel
    }

    /// Top edge stays under the icon; the panel grows downward.
    private func position() {
        guard let panel, let hosting, let button = anchor, let window = button.window else { return }
        var size = hosting.preferredContentSize
        if size.width < 10 { size = hosting.view.fittingSize }
        let buttonRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var x = buttonRect.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let top = buttonRect.minY - 6
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private func installMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in self?.close() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.close()
                return nil
            }
            return event
        }) {
            monitors.append(local)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // A popover or menu inside the panel takes key focus; only close when
        // focus went somewhere else entirely.
        guard let panel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isShown else { return }
            let keyWindow = NSApp.keyWindow
            if keyWindow == nil || (keyWindow !== panel && keyWindow?.parent !== panel && !(keyWindow?.className.contains("Popover") ?? false)) {
                if keyWindow != nil { self.close() }
            }
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
