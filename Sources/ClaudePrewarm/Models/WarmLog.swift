import Foundation

enum WarmType: String, Codable, Sendable {
    case scheduled
    case manual
    case wakeRecovery

    var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .manual: return "Warm now"
        case .wakeRecovery: return "After wake"
        }
    }
}

struct WarmLog: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    let date: Date
    let type: WarmType
    let success: Bool
    let error: String?
    var target: WarmTarget = .claude
    var seconds: Double?

    init(date: Date, type: WarmType, success: Bool, error: String?, target: WarmTarget = .claude, seconds: Double? = nil) {
        self.date = date
        self.type = type
        self.success = success
        self.error = error
        self.target = target
        self.seconds = seconds
    }

    private enum CodingKeys: String, CodingKey { case id, date, type, success, error, target, seconds }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        type = try c.decodeIfPresent(WarmType.self, forKey: .type) ?? .scheduled
        success = try c.decode(Bool.self, forKey: .success)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        target = try c.decodeIfPresent(WarmTarget.self, forKey: .target) ?? .claude
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds)
    }

    /// One short line for the history table.
    var resultLabel: String {
        if success {
            if let seconds { return String(format: "Done in %.1f s", seconds) }
            return "Done"
        }
        guard let error, !error.isEmpty else { return "Failed" }
        let lowered = error.lowercased()
        if lowered.contains("timed out") { return "Timed out" }
        if lowered.contains("sign") { return "Not signed in" }
        if lowered.contains("not found") || lowered.contains("not installed") { return "Not installed" }
        return "Failed"
    }
}
