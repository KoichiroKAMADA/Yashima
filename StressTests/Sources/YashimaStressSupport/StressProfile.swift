import Foundation

public struct StressProfile: Codable, Equatable, Sendable {
    public let name: String
    public let keyCount: Int
    public let concurrency: Int
    public let singleFlightFanout: Int
    public let minimumPayloadByteCount: Int
    public let maximumPayloadByteCount: Int
    public let timeoutSeconds: Int

    public init(
        name: String,
        keyCount: Int,
        concurrency: Int,
        singleFlightFanout: Int,
        minimumPayloadByteCount: Int,
        maximumPayloadByteCount: Int,
        timeoutSeconds: Int
    ) {
        self.name = name
        self.keyCount = keyCount
        self.concurrency = concurrency
        self.singleFlightFanout = singleFlightFanout
        self.minimumPayloadByteCount = minimumPayloadByteCount
        self.maximumPayloadByteCount = maximumPayloadByteCount
        self.timeoutSeconds = timeoutSeconds
    }

    public static let smoke = StressProfile(
        name: "smoke",
        keyCount: 120,
        concurrency: 24,
        singleFlightFanout: 64,
        minimumPayloadByteCount: 1 * 1024,
        maximumPayloadByteCount: 32 * 1024,
        timeoutSeconds: 60
    )

    public static let standard = StressProfile(
        name: "standard",
        keyCount: 1_000,
        concurrency: 64,
        singleFlightFanout: 256,
        minimumPayloadByteCount: 1 * 1024,
        maximumPayloadByteCount: 128 * 1024,
        timeoutSeconds: 5 * 60
    )

    public static let soak = StressProfile(
        name: "soak",
        keyCount: 5_000,
        concurrency: 128,
        singleFlightFanout: 512,
        minimumPayloadByteCount: 1 * 1024,
        maximumPayloadByteCount: 256 * 1024,
        timeoutSeconds: 30 * 60
    )

    public static let all: [StressProfile] = [.smoke, .standard, .soak]

    public static func named(_ name: String) -> StressProfile? {
        all.first { $0.name == name }
    }
}
