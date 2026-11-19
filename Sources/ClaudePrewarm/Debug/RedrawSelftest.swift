#if DEBUG
import AppKit

/// `ClaudePrewarm --redraw-selftest`: the menu bar icon must stay still when
/// nothing changes. Counts redraws idle, after a light/dark switch and after
/// warming ends; exits 1 if any phase keeps redrawing.
@MainActor
enum RedrawSelftest {
    static func run(state: AppState) {
        let controller = StatusItemController(state: state)
        var failed = false

        func phase(_ name: String, seconds: TimeInterval, max: Int, _ setup: () -> Void = {}) {
            setup()
            let before = controller.redrawCount
            RunLoop.main.run(until: Date().addingTimeInterval(seconds))
            let n = controller.redrawCount - before
            let ok = n <= max
            if !ok { failed = true }
            print("\(ok ? "ok  " : "FAIL") \(name): \(n) redraws in \(seconds)s (max \(max))")
        }

        RunLoop.main.run(until: Date().addingTimeInterval(1)) // settle
        phase("idle", seconds: 3, max: 1)
        phase("switch to dark", seconds: 2, max: 3) { controller.debugButton?.appearance = NSAppearance(named: .darkAqua) }
        phase("dark idle", seconds: 2, max: 1)
        phase("switch to light", seconds: 2, max: 3) { controller.debugButton?.appearance = NSAppearance(named: .aqua) }
        phase("warming pulses", seconds: 1, max: 30) { state.debugSetWarming(true) }
        phase("after warming", seconds: 2, max: 3) { state.debugSetWarming(false) }
        if controller.debugPulsing { failed = true; print("FAIL pulse timer still running") }
        print(failed ? "redraw selftest FAILED" : "redraw selftest passed")
        exit(failed ? 1 : 0)
    }
}
#endif
