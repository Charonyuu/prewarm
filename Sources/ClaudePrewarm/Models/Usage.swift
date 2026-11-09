import Foundation

enum WindowKind: String, Codable, Sendable {
    /// A rolling 5-hour window that starts with the first request.
    case session
    /// A weekly allowance across models.
    case weekly
    /// A limit on one model only.
    case model
}

/// One limit as a tool reports it.
struct UsageWindow: Identifiable, Equatable, Codable, Sendable {
    /// Stable across reads, e.g. "claude.session" or "agy.gemini-models.weekly".
    var id: String
    /// "Current session · 5 hours"
    var title: String
    /// "5-hour", "Week" — for compact places.
    var shortTitle: String
    /// agy groups its limits ("Gemini Models"); nil elsewhere.
    var group: String?
    var kind: WindowKind
    var usedPercent: Double?
    var resetsAt: Date?
    /// The tool's own wording when the reset time couldn't be parsed.
    var resetText: String?
    /// Length of the window, for pace.
    var duration: TimeInterval?
    /// A 5-hour window that hasn't been started yet.
    var notStarted: Bool = false

    var percentLabel: String {
        guard let usedPercent else { return "—" }
        return "\(Int(usedPercent.rounded()))%"
    }
}

/// One line of "what uses your limits" from `claude /usage`.
struct Insight: Equatable, Codable, Sendable {
    var percent: Int
    var text: String
}

/// Everything read from one tool in one go.
struct ProviderUsage: Equatable, Sendable {
    var fetchedAt: Date
    var plan: String?
    var windows: [UsageWindow]

    // Claude
    var insights24h: [Insight] = []
    var insights7d: [Insight] = []

    // Codex
    var freeResets: Int?
    var freeResetExpires: Date?
    var creditBalance: String?

    // Grok
    var prepaidBalance: Double?
    var onDemandEnabled: Bool?
    var periodStart: Date?
    var periodEnd: Date?

    var sessionWindows: [UsageWindow] { windows.filter { $0.kind == .session } }
    var hasSessionWindow: Bool { !sessionWindows.isEmpty }

    /// The limit closest to running out, ignoring single-model limits.
    var highestPercent: Double? {
        windows.filter { $0.kind != .model }.compactMap(\.usedPercent).max()
    }

    func window(_ id: String) -> UsageWindow? { windows.first { $0.id == id } }
}

/// Whether the CLI is usable.
enum ProviderStatus: Equatable, Sendable {
    case unknown
    case notInstalled
    case notSignedIn
    case ready
    case failed(String)
}

/// Live state for one tool.
struct ProviderRuntime: Equatable {
    var path: String?
    var version: String?
    var status: ProviderStatus = .unknown
    var usage: ProviderUsage?
    var isLoading = false
    var readError: String?
    var warming: Set<WarmTarget> = []
    var lastWarmAt: Date?
    var lastWarmError: String?

    var isInstalled: Bool { path != nil }
    var isWarming: Bool { !warming.isEmpty }
}
