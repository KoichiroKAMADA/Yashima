import Foundation
import Yashima

@main
struct YashimaBenchmarks {
    static func main() async throws {
        let configuration = BenchmarkConfiguration(arguments: CommandLine.arguments)
        let runner = BenchmarkRunner(configuration: configuration)
        try await runner.run()
    }
}

struct BenchmarkConfiguration: Sendable {
    var iterations = 200
    var payloadByteCount = 64 * 1024

    init(arguments: [String]) {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--iterations":
                if index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                    iterations = max(1, value)
                    index += 1
                }
            case "--payload-bytes":
                if index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                    payloadByteCount = max(1, value)
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
    }
}

struct BenchmarkRunner {
    let configuration: BenchmarkConfiguration

    func run() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("YashimaBenchmarks-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )

        let payload = deterministicPayload(byteCount: configuration.payloadByteCount)
        let cache = YCache(storageDirectory: root)
        let key = CacheKey(namespace: "benchmarks", identity: "payload")

        _ = try await cache.data(for: key) {
            payload
        }

        let memoryHit = try await measure("memory-hit") {
            _ = try await cache.data(for: key) {
                throw BenchmarkError.unexpectedMiss
            }
        }

        let storageHit = try await measure("storage-hit") {
            let coldCache = YCache(storageDirectory: root)
            _ = try await coldCache.data(for: key) {
                throw BenchmarkError.unexpectedMiss
            }
        }

        let generatedWrite = try await measure("generated-write") {
            let generatedKey = CacheKey(
                namespace: "benchmarks",
                identity: "generated-\(UUID().uuidString)"
            )
            _ = try await cache.data(for: generatedKey) {
                payload
            }
        }

        let singleFlight = try await measure("single-flight-100") {
            let sharedKey = CacheKey(
                namespace: "benchmarks",
                identity: "single-flight-\(UUID().uuidString)"
            )
            try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try await cache.data(for: sharedKey) {
                            payload
                        }
                    }
                }

                for try await value in group {
                    guard value == payload else {
                        throw BenchmarkError.invalidPayload
                    }
                }
            }
        }

        print("# YashimaBenchmarks")
        print("")
        print("- iterations: \(configuration.iterations)")
        print("- payload bytes: \(configuration.payloadByteCount)")
        print("- swift: \(swiftVersionSummary())")
        print("- date: \(ISO8601DateFormatter().string(from: Date()))")
        print("")
        print("| Scenario | Mean ms | Min ms | Max ms |")
        print("|---|---:|---:|---:|")
        for result in [memoryHit, storageHit, generatedWrite, singleFlight] {
            print(result.markdownRow)
        }
        print("")
        print("These numbers are local measurements, not a general performance claim.")
    }

    private func measure(
        _ name: String,
        operation: () async throws -> Void
    ) async throws -> BenchmarkResult {
        var samples: [Double] = []
        samples.reserveCapacity(configuration.iterations)

        let clock = ContinuousClock()
        for _ in 0..<configuration.iterations {
            let start = clock.now
            try await operation()
            let elapsed = start.duration(to: clock.now)
            samples.append(elapsed.milliseconds)
        }

        return BenchmarkResult(name: name, samples: samples)
    }
}

struct BenchmarkResult {
    let name: String
    let samples: [Double]

    var mean: Double {
        samples.reduce(0, +) / Double(samples.count)
    }

    var minimum: Double {
        samples.min() ?? 0
    }

    var maximum: Double {
        samples.max() ?? 0
    }

    var markdownRow: String {
        "| \(name) | \(mean.formatted) | \(minimum.formatted) | \(maximum.formatted) |"
    }
}

enum BenchmarkError: Error {
    case unexpectedMiss
    case invalidPayload
}

func deterministicPayload(byteCount: Int) -> Data {
    var bytes = [UInt8]()
    bytes.reserveCapacity(byteCount)
    for index in 0..<byteCount {
        bytes.append(UInt8((index * 31 + 17) % 251))
    }
    return Data(bytes)
}

func swiftVersionSummary() -> String {
    #if swift(>=6.1)
    return "6.1+"
    #else
    return "below 6.1"
    #endif
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

private extension Double {
    var formatted: String {
        String(format: "%.3f", self)
    }
}
