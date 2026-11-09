import Foundation

enum BinaryFinder {
    /// A GUI app inherits a minimal PATH, so ask a login shell first and fall
    /// back to the usual install locations, including every nvm Node version.
    static func find(_ provider: Provider) -> String? {
        if let path = viaLoginShell(provider.binaryName), isExecutable(path) { return path }
        for candidate in provider.fallbackPaths {
            let expanded = (candidate as NSString).expandingTildeInPath
            if isExecutable(expanded) { return expanded }
        }
        let nvm = ("~/.nvm/versions/node" as NSString).expandingTildeInPath
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for version in versions.sorted(by: >) {
                let path = "\(nvm)/\(version)/bin/\(provider.binaryName)"
                if isExecutable(path) { return path }
            }
        }
        return nil
    }

    /// One login shell for all four, since each spawn costs a few hundred ms.
    static func findAll() -> [Provider: String] {
        var found: [Provider: String] = [:]
        let names = Provider.allCases.map(\.binaryName).joined(separator: " ")
        if let output = shell("for n in \(names); do command -v $n || echo -; done") {
            let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (index, provider) in Provider.allCases.enumerated() where index < lines.count {
                let path = lines[index].trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("/"), isExecutable(path) { found[provider] = path }
            }
        }
        for provider in Provider.allCases where found[provider] == nil {
            for candidate in provider.fallbackPaths {
                let expanded = (candidate as NSString).expandingTildeInPath
                if isExecutable(expanded) { found[provider] = expanded; break }
            }
        }
        let nvm = ("~/.nvm/versions/node" as NSString).expandingTildeInPath
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            for provider in Provider.allCases where found[provider] == nil {
                for version in versions.sorted(by: >) {
                    let path = "\(nvm)/\(version)/bin/\(provider.binaryName)"
                    if isExecutable(path) { found[provider] = path; break }
                }
            }
        }
        return found
    }

    private static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private static func viaLoginShell(_ name: String) -> String? {
        guard let output = shell("command -v \(name)") else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") ? path : nil
    }

    private static func shell(_ command: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        let output = String(decoding: data, as: UTF8.self)
        return output.isEmpty ? nil : output
    }
}
