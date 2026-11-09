import Foundation

/// How usage compares with time gone in the window.
enum Pace: Equatable {
    case behind
    case onPace
    case ahead(runsOutAt: Date)
    case reached(backAt: Date?)

    /// Pace is only shown for windows of a day or longer; for a 5-hour window
    /// the reset countdown says more.
    static func of(_ window: UsageWindow, now: Date = Clock.now) -> Pace? {
        guard let used = window.usedPercent, used >= 1 else { return nil }
        if used >= 99.5 { return .reached(backAt: window.resetsAt) }
        guard let reset = window.resetsAt, let duration = window.duration,
              duration >= 24 * 3600, reset > now
        else { return nil }

        let remaining = reset.timeIntervalSince(now)
        let elapsed = duration - remaining
        // Too early in the window for a fair read.
        guard elapsed > duration * 0.08 else { return nil }

        let elapsedPercent = elapsed / duration * 100
        if used > elapsedPercent + 5 {
            let rate = used / elapsed
            guard rate > 0 else { return .onPace }
            let runsOut = now.addingTimeInterval((100 - used) / rate)
            return runsOut < reset ? .ahead(runsOutAt: runsOut) : .onPace
        }
        if used < elapsedPercent - 5 { return .behind }
        return .onPace
    }

    var text: String {
        switch self {
        case .behind: return "Behind pace · lasts until the reset"
        case .onPace: return "On pace · lasts until the reset"
        case .ahead(let date): return "Ahead of pace · runs out around \(DateCalculator.compactLabel(for: date))"
        case .reached(let back):
            if let back { return "Limit reached · back \(DateCalculator.compactLabel(for: back))" }
            return "Limit reached"
        }
    }

    enum Tone { case good, warning, danger }

    var tone: Tone {
        switch self {
        case .behind, .onPace: return .good
        case .ahead: return .warning
        case .reached: return .danger
        }
    }
}
