import AppKit
import SwiftUI

/// Plain AppKit windows, so nothing opens by itself at launch the way a
/// SwiftUI `Window` scene would in a menu-bar-only app.
@MainActor
class HostedWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private let frameName: String

    init(frameName: String) {
        self.frameName = frameName
    }

    func makeContent() -> AnyView { AnyView(EmptyView()) }
    func windowTitle() -> String { "Prewarm" }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.setActivationPolicy(.regular)
        // macOS 14 activation is cooperative and can be refused when another app
        // is in front, so put the window on top ourselves as well.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu-bar-only app once no window of ours is left.
        DispatchQueue.main.async {
            let open = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
            if !open { NSApp.setActivationPolicy(.accessory) }
        }
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: makeContent())
        let window = NSWindow(contentViewController: hosting)
        window.title = windowTitle()
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.backgroundColor = NSColor(Theme.window)

        let restored = window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        if !restored { center(window) }
        return window
    }

    /// `NSWindow.center()` sits a third of the way down, under the menu panel.
    /// Put it in the actual middle of the active screen instead.
    private func center(_ window: NSWindow) {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
    }
}

@MainActor
final class SettingsWindowController: HostedWindowController {
    private let state: AppState
    private let model = PageModel()

    final class PageModel: ObservableObject {
        @Published var page: SettingsPage = .general
    }

    init(state: AppState) {
        self.state = state
        super.init(frameName: "ClaudePrewarmSettingsWindow2")
    }

    override func makeContent() -> AnyView {
        AnyView(SettingsHost(model: model).environmentObject(state))
    }

    func show(page: SettingsPage?) {
        if let page { model.page = page }
        if let window { window.title = model.page.title }
        state.detectTools { [state] in state.refreshAll() }
        show()
    }

    private struct SettingsHost: View {
        @ObservedObject var model: PageModel
        var body: some View {
            SettingsView(page: $model.page)
                .padding(.top, 28) // room for the transparent title bar
                .background(Theme.window)
                .onChange(of: model.page) { _, page in
                    NSApp.windows.first { $0.frameAutosaveName == "ClaudePrewarmSettingsWindow2" }?.title = page.title
                }
        }
    }
}

@MainActor
final class OnboardingWindowController: HostedWindowController {
    private let state: AppState
    private let model = StepModel()
    var onFinish: () -> Void = {}

    final class StepModel: ObservableObject {
        @Published var step = 1
    }

    init(state: AppState) {
        self.state = state
        super.init(frameName: "ClaudePrewarmWelcomeWindow")
    }

    override func windowTitle() -> String { "Welcome" }

    override func makeContent() -> AnyView {
        AnyView(OnboardingHost(model: model) { [weak self] in
            SettingsStore.onboardingDone = true
            self?.close()
            self?.onFinish()
        }
        .environmentObject(state))
    }

    override func windowWillClose(_ notification: Notification) {
        SettingsStore.onboardingDone = true
        super.windowWillClose(notification)
    }

    private struct OnboardingHost: View {
        @ObservedObject var model: StepModel
        let finish: () -> Void
        var body: some View {
            OnboardingView(step: $model.step, finish: finish)
                .padding(.top, 28)
                .background(Theme.window)
        }
    }
}
