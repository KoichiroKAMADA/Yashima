import Foundation

public struct StressReport: Codable, Equatable, Sendable {
    public let profile: String
    public let seed: Int
    public let success: Bool
    public let durationSeconds: Double
    public let scenarios: [StressScenarioReport]

    public init(
        profile: String,
        seed: Int,
        success: Bool,
        durationSeconds: Double,
        scenarios: [StressScenarioReport]
    ) {
        self.profile = profile
        self.seed = seed
        self.success = success
        self.durationSeconds = durationSeconds
        self.scenarios = scenarios
    }

    public func renderedText() -> String {
        var lines: [String] = []
        lines.append("Yashima stress report")
        lines.append("profile: \(profile)")
        lines.append("seed: \(seed)")
        lines.append("result: \(success ? "passed" : "failed")")
        lines.append(String(format: "duration: %.3fs", durationSeconds))
        lines.append("")

        for scenario in scenarios {
            lines.append("[\(scenario.status.rawValue)] \(scenario.name)")
            lines.append(String(format: "  duration: %.3fs", scenario.durationSeconds))
            lines.append("  operations: \(scenario.operations)")
            lines.append("  generated: \(scenario.generatedCount), memory: \(scenario.memoryHitCount), storage: \(scenario.storageHitCount)")
            if scenario.regeneratedCount > 0 || scenario.removedCount > 0 || scenario.cancelledCount > 0 {
                lines.append("  regenerated: \(scenario.regeneratedCount), removed: \(scenario.removedCount), cancelled: \(scenario.cancelledCount)")
            }
            if let message = scenario.message {
                lines.append("  message: \(message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public func renderedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        return String(decoding: data, as: UTF8.self)
    }
}

public struct StressScenarioReport: Codable, Equatable, Sendable {
    public let name: String
    public let status: StressScenarioStatus
    public let durationSeconds: Double
    public let operations: Int
    public let generatedCount: Int
    public let memoryHitCount: Int
    public let storageHitCount: Int
    public let regeneratedCount: Int
    public let removedCount: Int
    public let cancelledCount: Int
    public let message: String?

    public init(
        name: String,
        status: StressScenarioStatus,
        durationSeconds: Double,
        operations: Int,
        generatedCount: Int,
        memoryHitCount: Int,
        storageHitCount: Int,
        regeneratedCount: Int,
        removedCount: Int,
        cancelledCount: Int,
        message: String?
    ) {
        self.name = name
        self.status = status
        self.durationSeconds = durationSeconds
        self.operations = operations
        self.generatedCount = generatedCount
        self.memoryHitCount = memoryHitCount
        self.storageHitCount = storageHitCount
        self.regeneratedCount = regeneratedCount
        self.removedCount = removedCount
        self.cancelledCount = cancelledCount
        self.message = message.map(Redactor.sanitize)
    }
}

public enum StressScenarioStatus: String, Codable, Equatable, Sendable {
    case passed
    case failed
}

public struct StressScenarioSummary: Equatable, Sendable {
    public var operations: Int
    public var generatedCount: Int
    public var memoryHitCount: Int
    public var storageHitCount: Int
    public var regeneratedCount: Int
    public var removedCount: Int
    public var cancelledCount: Int
    public var message: String?

    public init(
        operations: Int = 0,
        generatedCount: Int = 0,
        memoryHitCount: Int = 0,
        storageHitCount: Int = 0,
        regeneratedCount: Int = 0,
        removedCount: Int = 0,
        cancelledCount: Int = 0,
        message: String? = nil
    ) {
        self.operations = operations
        self.generatedCount = generatedCount
        self.memoryHitCount = memoryHitCount
        self.storageHitCount = storageHitCount
        self.regeneratedCount = regeneratedCount
        self.removedCount = removedCount
        self.cancelledCount = cancelledCount
        self.message = message
    }
}

public enum Redactor {
    public static func sanitize(_ message: String) -> String {
        var sanitized = message
        sanitized = replacing(pattern: #"file://[^\s,\)"]+"#, in: sanitized, with: "<file-url>")
        sanitized = replacing(pattern: #"(/Users|/private/tmp|/tmp)/[^\s,\)"]+"#, in: sanitized, with: "<path>")
        sanitized = replacing(pattern: #"NSFilePath = [^;\n,}]+"#, in: sanitized, with: "NSFilePath = <path>")
        return sanitized
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: replacement
        )
    }
}
