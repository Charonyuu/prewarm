import Foundation

/// A line-delimited JSON-RPC session with a CLI over stdio. Used for
/// `codex app-server` and Grok's `grok agent stdio` (ACP).
final class JSONRPCClient: @unchecked Sendable {
    struct RPCError: Error { let code: Int; let message: String }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let condition = NSCondition()
    private var buffer = Data()
    private var responses: [Int: [String: Any]] = [:]
    private var closed = false
    private let tool: String

    init(executablePath: String, arguments: [String], tool: String) throws {
        self.tool = tool
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw CLIError.notInstalled(tool)
        }
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = ProcessRunner.scratchDirectory()
        process.environment = ProcessRunner.childEnvironment(for: executablePath)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.receive(data)
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw CLIError.launchFailed(error.localizedDescription)
        }
    }

    deinit { close() }

    private func receive(_ data: Data) {
        condition.lock()
        defer { condition.broadcast(); condition.unlock() }
        if data.isEmpty {
            closed = true
            output.fileHandleForReading.readabilityHandler = nil
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int,
                  object["result"] != nil || object["error"] != nil
            else { continue }
            responses[id] = object
        }
    }

    func notify(_ method: String, params: [String: Any] = [:]) {
        write(["jsonrpc": "2.0", "method": method, "params": params])
    }

    /// Sends a request and waits for its response.
    func call(_ method: String, id: Int, params: [String: Any] = [:], timeout: TimeInterval) throws -> [String: Any] {
        write(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while responses[id] == nil {
            if closed { throw CLIError.unreadable(tool) }
            if !condition.wait(until: deadline) {
                throw CLIError.timedOut(tool: tool, seconds: Int(timeout))
            }
        }
        let response = responses.removeValue(forKey: id) ?? [:]
        if let error = response["error"] as? [String: Any] {
            throw RPCError(code: error["code"] as? Int ?? 0, message: error["message"] as? String ?? "")
        }
        return response["result"] as? [String: Any] ?? [:]
    }

    private func write(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    func close() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
