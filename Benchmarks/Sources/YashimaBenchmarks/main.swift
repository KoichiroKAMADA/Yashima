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
    var generatorWorkFactor = 8

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
            case "--generator-work-factor":
                if index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                    generatorWorkFactor = max(1, value)
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

        let generator = SyntheticArtifactGenerator(
            byteCount: configuration.payloadByteCount,
            workFactor: configuration.generatorWorkFactor
        )
        let payload = generator.generate(seed: 0)
        let cache = YCache(storageDirectory: root)
        let key = CacheKey(namespace: "benchmarks", identity: "payload")

        _ = try await cache.data(for: key) {
            payload
        }

        let uncachedRegeneration = try await measure("uncached-regeneration") { iteration in
            _ = generator.generate(seed: iteration)
        }

        let memoryHit = try await measure("yashima-memory-hit") { _ in
            _ = try await cache.data(for: key) {
                throw BenchmarkError.unexpectedMiss
            }
        }

        let storageHit = try await measure("yashima-storage-hit") { _ in
            let coldCache = YCache(storageDirectory: root)
            _ = try await coldCache.data(for: key) {
                throw BenchmarkError.unexpectedMiss
            }
        }

        let generatedWrite = try await measure("yashima-generated-write") { iteration in
            let generatedKey = CacheKey(
                namespace: "benchmarks",
                identity: "generated-\(iteration)"
            )
            _ = try await cache.data(for: generatedKey) {
                generator.generate(seed: iteration)
            }
        }

        let singleFlight = try await measure("yashima-single-flight-100") { iteration in
            let sharedKey = CacheKey(
                namespace: "benchmarks",
                identity: "single-flight-\(iteration)"
            )
            try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in 0..<100 {
                    group.addTask {
                        try await cache.data(for: sharedKey) {
                            generator.generate(seed: iteration)
                        }
                    }
                }

                for try await value in group {
                    guard value.count == configuration.payloadByteCount else {
                        throw BenchmarkError.invalidPayload
                    }
                }
            }
        }

        print("# YashimaBenchmarks")
        print("")
        print("- iterations: \(configuration.iterations)")
        print("- payload bytes: \(configuration.payloadByteCount)")
        print("- generator work factor: \(configuration.generatorWorkFactor)")
        print("- os: \(environmentSummary.operatingSystem)")
        print("- architecture: \(environmentSummary.architecture)")
        print("- processor: \(environmentSummary.processor)")
        print("- memory: \(environmentSummary.memory)")
        print("- swift: \(environmentSummary.swiftToolchain)")
        print("- date: \(ISO8601DateFormatter().string(from: Date()))")
        print("")
        print("| Scenario | Mean ms | Min ms | Max ms |")
        print("|---|---:|---:|---:|")
        for result in [
            uncachedRegeneration,
            memoryHit,
            storageHit,
            generatedWrite,
            singleFlight,
        ] {
            print(result.markdownRow)
        }
        print("")
        print("The uncached-regeneration row is a synthetic reference for repeated local generation, not another cache implementation.")
        print("These numbers are local measurements, not a universal performance claim.")
    }

    private func measure(
        _ name: String,
        operation: (Int) async throws -> Void
    ) async throws -> BenchmarkResult {
        var samples: [Double] = []
        samples.reserveCapacity(configuration.iterations)

        let clock = ContinuousClock()
        for iteration in 0..<configuration.iterations {
            let start = clock.now
            try await operation(iteration)
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

struct SyntheticArtifactGenerator: Sendable {
    let byteCount: Int
    let workFactor: Int

    func generate(seed: Int) -> Data {
        guard byteCount > 0 else {
            return Data()
        }

        var bytes = [UInt8](repeating: UInt8(truncatingIfNeeded: seed), count: byteCount)
        for round in 0..<workFactor {
            var previous = UInt8(truncatingIfNeeded: seed + round)
            for index in bytes.indices {
                let mixed = bytes[index]
                    &+ previous
                    &+ UInt8(truncatingIfNeeded: index &* 31 &+ round &* 17)
                bytes[index] = mixed
                previous = mixed ^ UInt8(truncatingIfNeeded: index &+ round)
            }
        }
        return Data(bytes)
    }
}

struct BenchmarkEnvironment {
    let operatingSystem: String
    let architecture: String
    let processor: String
    let memory: String
    let swiftToolchain: String
}

var environmentSummary: BenchmarkEnvironment {
    BenchmarkEnvironment(
        operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: architectureSummary,
        processor: commandOutput("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"]) ?? "unknown",
        memory: memorySummary,
        swiftToolchain: commandOutput("/usr/bin/env", ["swift", "--version"])?.singleLine ?? swiftLanguageSummary
    )
}

var architectureSummary: String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}

var swiftLanguageSummary: String {
    #if swift(>=6.1)
    return "Swift language mode 6.1+"
    #else
    return "Swift language mode below 6.1"
    #endif
}

var memorySummary: String {
    let bytes = ProcessInfo.processInfo.physicalMemory
    let gibibytes = Double(bytes) / 1_073_741_824
    return "\(gibibytes.formatted) GiB"
}

func commandOutput(_ executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
        return nil
    }
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

private extension String {
    var singleLine: String {
        split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}
