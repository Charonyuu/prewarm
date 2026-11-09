import Foundation

/// Reads limits from, and warms, each CLI. Every call blocks, so callers run
/// them off the main thread.
enum ProviderServices {
    static let warmPrompt = "Reply only OK."

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    }

    // MARK: Version

    static func version(of provider: Provider, path: String) -> String? {
        guard let output = try? ProcessRunner.execute(
            executablePath: path, arguments: ["--version"], timeout: 15, tool: provider.cliName
        ) else { return nil }
        return VersionParser.parse(output.stdout + " " + output.stderr)
    }

    // MARK: Usage

    static func readUsage(_ provider: Provider, path: String) throws -> ProviderUsage {
        switch provider {
        case .claude: return try readClaude(path: path)
        case .codex: return try readCodex(path: path)
        case .grok: return try readGrok(path: path)
        case .agy: return try readAgy(path: path)
        }
    }

    private static func readClaude(path: String) throws -> ProviderUsage {
        let output = try ProcessRunner.execute(
            executablePath: path,
            arguments: ["-p", "/usage", "--no-session-persistence", "--strict-mcp-config"],
            timeout: 45,
            tool: "Claude Code"
        )
        if let usage = ClaudeUsageParser.parse(output.stdout) { return usage }
        if CLIError.looksLikeAuthFailure(output.stdout + output.stderr) { throw CLIError.notSignedIn("Claude Code") }
        if output.exitCode != 0 {
            throw CLIError.failed(tool: "Claude Code", exitCode: output.exitCode, message: String(output.combined.prefix(200)))
        }
        throw CLIError.unreadable("Claude Code")
    }

    private static func readCodex(path: String) throws -> ProviderUsage {
        let client = try JSONRPCClient(executablePath: path, arguments: ["app-server"], tool: "Codex")
        defer { client.close() }
        do {
            _ = try client.call("initialize", id: 1, params: [
                "clientInfo": ["name": "prewarm", "version": appVersion]
            ], timeout: 25)
            client.notify("initialized")
            let account = try? client.call("account/read", id: 2, timeout: 20)
            if let account, account["account"] == nil || account["account"] is NSNull,
               account["requiresOpenaiAuth"] as? Bool == true {
                throw CLIError.notSignedIn("Codex")
            }
            let limits = try client.call("account/rateLimits/read", id: 3, timeout: 25)
            guard let usage = CodexUsageParser.parse(limits: limits, account: account) else {
                throw CLIError.unreadable("Codex")
            }
            return usage
        } catch let error as JSONRPCClient.RPCError {
            if CLIError.looksLikeAuthFailure(error.message) { throw CLIError.notSignedIn("Codex") }
            throw CLIError.failed(tool: "Codex", exitCode: Int32(error.code), message: error.message)
        }
    }

    private static func readGrok(path: String) throws -> ProviderUsage {
        let client = try JSONRPCClient(executablePath: path, arguments: ["agent", "--no-leader", "stdio"], tool: "Grok Build")
        defer { client.close() }
        do {
            _ = try client.call("initialize", id: 1, params: [
                "protocolVersion": 1,
                "clientCapabilities": [String: Any](),
                "clientInfo": ["name": "prewarm", "version": appVersion]
            ], timeout: 40)
            let billing = try client.call("_x.ai/billing", id: 2, timeout: 40)
            guard let usage = GrokUsageParser.parse(billing) else { throw CLIError.unreadable("Grok Build") }
            return usage
        } catch let error as JSONRPCClient.RPCError {
            if CLIError.looksLikeAuthFailure(error.message) { throw CLIError.notSignedIn("Grok Build") }
            throw CLIError.failed(tool: "Grok Build", exitCode: Int32(error.code), message: error.message)
        }
    }

    private static func readAgy(path: String) throws -> ProviderUsage {
        let output = try ProcessRunner.execute(
            executablePath: path,
            arguments: ["-p", "/usage", "--print-timeout", "40s"],
            timeout: 60,
            tool: "agy"
        )
        if let usage = AgyUsageParser.parse(output.stdout) { return usage }
        if CLIError.looksLikeAuthFailure(output.stdout + output.stderr) { throw CLIError.notSignedIn("agy") }
        if output.exitCode != 0 {
            throw CLIError.failed(tool: "agy", exitCode: output.exitCode, message: String(output.combined.prefix(200)))
        }
        throw CLIError.unreadable("agy")
    }

    // MARK: Warm

    /// Sends one tiny request. Returns how long it took.
    static func warm(_ target: WarmTarget, path: String) throws -> TimeInterval {
        let started = Date()
        let tool = target.provider.cliName
        let arguments: [String]
        var timeout: TimeInterval = 45

        switch target {
        case .claude:
            arguments = [
                "-p", warmPrompt,
                "--model", "haiku",
                "--effort", "low",
                "--no-session-persistence",
                "--strict-mcp-config",
                "--disable-slash-commands"
            ]
        case .codex:
            var args = ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
                        "-c", "model_reasoning_effort=\"low\""]
            if let model = smallCodexModel() { args += ["-m", model] }
            arguments = args + [warmPrompt]
            timeout = 90
        case .agyGemini, .agyOther:
            var args = ["-p", warmPrompt, "--print-timeout", "60s", "--disable-slash-commands"]
            if let model = agyModel(for: target, path: path) { args += ["--model", model] }
            arguments = args
            timeout = 80
        }

        let output = try ProcessRunner.execute(executablePath: path, arguments: arguments, timeout: timeout, tool: tool)
        guard output.exitCode == 0 else {
            if CLIError.looksLikeAuthFailure(output.stdout + output.stderr) { throw CLIError.notSignedIn(tool) }
            throw CLIError.failed(tool: tool, exitCode: output.exitCode, message: String(output.combined.prefix(200)))
        }
        return Date().timeIntervalSince(started)
    }

    /// The cheapest model Codex lists, read from its own model cache.
    static func smallCodexModel() -> String? {
        let url = URL(fileURLWithPath: ("~/.codex/models_cache.json" as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return nil }
        func find(_ word: String) -> String? {
            models.first { ($0["description"] as? String ?? "").lowercased().contains(word) }?["slug"] as? String
        }
        return find("easier tasks") ?? find("affordable")
    }

    private static let agyModels = Atomic<[String]?>(nil)

    /// agy keeps two 5-hour windows; warm each with its smallest model.
    static func agyModel(for target: WarmTarget, path: String) -> String? {
        var models = agyModels.value
        if models == nil {
            let output = try? ProcessRunner.execute(executablePath: path, arguments: ["models"], timeout: 30, tool: "agy")
            models = (output?.stdout ?? "")
                .components(separatedBy: .newlines)
                .compactMap { $0.components(separatedBy: "\t").first?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("Fetching") }
            agyModels.value = models
        }
        guard let models else { return nil }
        switch target {
        case .agyGemini:
            return models.first { $0.contains("flash") && $0.hasSuffix("-low") }
                ?? models.first { $0.contains("gemini") && $0.hasSuffix("-low") }
                ?? models.first { $0.contains("gemini") }
        case .agyOther:
            return models.first { $0.contains("gpt-oss") }
                ?? models.first { $0.contains("sonnet") && $0.hasSuffix("-low") }
                ?? models.first { $0.contains("claude") }
        default:
            return nil
        }
    }
}
