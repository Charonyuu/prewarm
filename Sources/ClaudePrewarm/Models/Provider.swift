import Foundation

/// The command-line tools Prewarm reads limits from.
enum Provider: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case grok
    case agy

    var id: String { rawValue }

    /// Short name used on tabs and cards.
    var name: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .grok: return "Grok"
        case .agy: return "agy"
        }
    }

    /// The CLI's own product name.
    var cliName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .grok: return "Grok Build"
        case .agy: return "Antigravity CLI"
        }
    }

    var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .grok: return "grok"
        case .agy: return "agy"
        }
    }

    /// Where the official install instructions live.
    var installURL: URL {
        switch self {
        case .claude: return URL(string: "https://docs.claude.com/en/docs/claude-code/setup")!
        case .codex: return URL(string: "https://developers.openai.com/codex/cli")!
        case .grok: return URL(string: "https://x.ai/cli")!
        case .agy: return URL(string: "https://antigravity.google/docs")!
        }
    }

    /// What to run in Terminal to sign in.
    var signInCommand: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex login"
        case .grok: return "grok login"
        case .agy: return "agy"
        }
    }

    /// Install locations to try when a login shell can't find the binary.
    var fallbackPaths: [String] {
        let name = binaryName
        var paths = [
            "~/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "~/.bun/bin/\(name)",
            "~/.npm-global/bin/\(name)",
            "~/.volta/bin/\(name)"
        ]
        switch self {
        case .claude:
            paths += ["~/.claude/local/claude", "~/.claude/local/bin/claude"]
        case .grok:
            paths += ["~/.grok/bin/grok"]
        default:
            break
        }
        return paths
    }

    /// Whether this tool has a 5-hour window that a warm-up can start early.
    /// Codex depends on the plan, so it is decided from the limits it reports.
    var mayHaveSessionWindow: Bool { self != .grok }
}

/// One thing a warm-up can start. agy keeps two separate 5-hour windows.
enum WarmTarget: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case agyGemini
    case agyOther

    var id: String { rawValue }

    var provider: Provider {
        switch self {
        case .claude: return .claude
        case .codex: return .codex
        case .agyGemini, .agyOther: return .agy
        }
    }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .agyGemini: return "agy · Gemini"
        case .agyOther: return "agy · Claude & GPT"
        }
    }
}
