#if DEBUG
import Foundation

/// `ClaudePrewarm --probe [warm-target…]` reads every installed CLI the same way
/// the app does and prints what came back. Warm targets are only run when named.
enum Probe {
    static func run(warm: [String]) {
        let paths = BinaryFinder.findAll()
        for provider in Provider.allCases {
            guard let path = paths[provider] else { print("\(provider.name): not installed"); continue }
            let version = ProviderServices.version(of: provider, path: path) ?? "?"
            let started = Date()
            do {
                let usage = try ProviderServices.readUsage(provider, path: path)
                let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
                print("\(provider.name) \(version) at \(path) — read in \(seconds)s, plan \(usage.plan ?? "-")")
                for w in usage.windows {
                    let reset = w.resetsAt.map { DateCalculator.compactLabel(for: $0) } ?? (w.resetText ?? "-")
                    let pace = Pace.of(w).map { " · \($0.text)" } ?? ""
                    print("   [\(w.kind.rawValue)] \(w.group.map { "\($0) / " } ?? "")\(w.title): \(w.percentLabel)\(w.notStarted ? " (not started)" : "") resets \(reset)\(pace)")
                }
                if !usage.insights24h.isEmpty { print("   insights 24h: \(usage.insights24h.map { "\($0.percent)% \($0.text)" })") }
                if let n = usage.freeResets { print("   free resets: \(n), first expires \(usage.freeResetExpires.map { DateCalculator.dayLabel(for: $0) } ?? "-"), credits \(usage.creditBalance ?? "-")") }
                if let p = usage.prepaidBalance { print("   prepaid $\(p), on-demand \(usage.onDemandEnabled ?? false)") }
                print("   session window: \(usage.hasSessionWindow)")
            } catch {
                print("\(provider.name) \(version): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
        }
        for name in warm {
            guard let target = WarmTarget(rawValue: name), let path = paths[target.provider] else { print("skip \(name)"); continue }
            if target == .codex || target == .agyGemini || target == .agyOther {
                print("model for \(name): \(target == .codex ? (ProviderServices.smallCodexModel() ?? "default") : (ProviderServices.agyModel(for: target, path: path) ?? "default"))")
            }
            do {
                let seconds = try ProviderServices.warm(target, path: path)
                print("warm \(name): ok in \(String(format: "%.1f", seconds))s")
            } catch {
                print("warm \(name): \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
        }
    }
}
#endif
