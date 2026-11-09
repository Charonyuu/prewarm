import Foundation

struct ProcessOutput {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var combined: String { stderr.isEmpty ? stdout : stderr }
}

enum CLIError: LocalizedError, Equatable {
    case notInstalled(String)
    case launchFailed(String)
    case timedOut(tool: String, seconds: Int)
    case notSignedIn(String)
    case failed(tool: String, exitCode: Int32, message: String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let tool):
            return "\(tool) isn't installed on this Mac."
        case .launchFailed(let message):
            return "The CLI could not be started. \(message)"
        case .timedOut(let tool, let seconds):
            return "\(tool) timed out after \(seconds) seconds."
        case .notSignedIn(let tool):
            return "\(tool) isn't signed in."
        case .failed(let tool, let exitCode, let message):
            let detail = message.isEmpty ? "" : " \(message)"
            return "\(tool) exited with code \(exitCode).\(detail)"
        case .unreadable(let tool):
            return "\(tool)'s limits could not be read."
        }
    }

    var isSignIn: Bool { if case .notSignedIn = self { return true } else { return false } }

    static func looksLikeAuthFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return ["not logged in", "log in", "login", "sign in", "signed in", "authenticat", "unauthorized",
                "oauth", "credentials", "401", "api key"]
            .contains { lowered.contains($0) }
    }
}

/// Launches a CLI the same way for every call: an empty working directory,
/// a PATH a GUI app would otherwise lack, and a hard timeout.
enum ProcessRunner {
    static func execute(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        tool: String = "The CLI"
    ) throws -> ProcessOutput {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CLIError.notInstalled(tool)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = scratchDirectory()
        process.environment = childEnvironment(for: executablePath)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CLIError.launchFailed(error.localizedDescription)
        }

        let timedOut = Atomic(false)
        let deadline = DispatchWorkItem {
            if process.isRunning {
                timedOut.value = true
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

        // Read both pipes concurrently so a chatty stderr can't block stdout.
        let errData = Atomic(Data())
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
            errDone.signal()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        process.waitUntilExit()
        deadline.cancel()

        if timedOut.value { throw CLIError.timedOut(tool: tool, seconds: Int(timeout)) }

        return ProcessOutput(
            stdout: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errData.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: process.terminationStatus
        )
    }

    /// An empty directory, so a CLI never picks up a project's files or CLAUDE.md.
    static func scratchDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Prewarm", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A GUI app's PATH is minimal. Put the binary's own folder first (Codex is a
    /// Node script and needs the `node` beside it), then the usual locations.
    static func childEnvironment(for executablePath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let ownDir = (executablePath as NSString).deletingLastPathComponent
        let resolvedDir = ((try? FileManager.default.destinationOfSymbolicLink(atPath: executablePath)) as NSString?)
            .map { link -> String in
                let target = link.isAbsolutePath ? link as String : (ownDir as NSString).appendingPathComponent(link as String)
                return (target as NSString).deletingLastPathComponent
            }
        var parts = [ownDir]
        if let resolvedDir { parts.append(resolvedDir) }
        parts += [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        if let existing = env["PATH"] { parts.append(existing) }
        env["PATH"] = parts.joined(separator: ":")
        env["HOME"] = home
        env["CLAUDE_CODE_NONINTERACTIVE"] = "1"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        return env
    }
}

/// Minimal lock-protected box, so a timeout handler and the caller can share a value.
final class Atomic<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
