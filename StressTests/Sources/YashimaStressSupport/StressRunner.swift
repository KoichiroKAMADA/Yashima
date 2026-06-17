import Foundation

public struct StressRunner: Sendable {
    private let command: StressCommand

    public init(command: StressCommand) {
        self.command = command
    }

    public func run() async -> StressReport {
        let startedAt = Date()
        var scenarioReports: [StressScenarioReport] = []

        do {
            let workspace = try StressWorkspace(command: command)
            defer {
                if !command.keepsArtifacts {
                    try? FileManager.default.removeItem(at: workspace.rootDirectory)
                }
            }

            for (index, scenario) in StressScenarios.all.enumerated() {
                let scenarioRoot = workspace.rootDirectory.appendingPathComponent(
                    "\(index)-\(scenario.safeName)",
                    isDirectory: true
                )
                try FileManager.default.createDirectory(
                    at: scenarioRoot,
                    withIntermediateDirectories: true
                )

                let scenarioStartedAt = Date()
                let context = StressScenarioContext(
                    profile: command.profile,
                    seed: command.seed,
                    rootDirectory: scenarioRoot
                )

                do {
                    let summary = try await withTimeout(seconds: command.profile.timeoutSeconds) {
                        try await scenario.run(context)
                    }
                    scenarioReports.append(
                        StressScenarioReport(
                            name: scenario.name,
                            status: .passed,
                            durationSeconds: Date().timeIntervalSince(scenarioStartedAt),
                            operations: summary.operations,
                            generatedCount: summary.generatedCount,
                            memoryHitCount: summary.memoryHitCount,
                            storageHitCount: summary.storageHitCount,
                            regeneratedCount: summary.regeneratedCount,
                            removedCount: summary.removedCount,
                            cancelledCount: summary.cancelledCount,
                            message: summary.message
                        )
                    )
                } catch {
                    scenarioReports.append(
                        StressScenarioReport(
                            name: scenario.name,
                            status: .failed,
                            durationSeconds: Date().timeIntervalSince(scenarioStartedAt),
                            operations: 0,
                            generatedCount: 0,
                            memoryHitCount: 0,
                            storageHitCount: 0,
                            regeneratedCount: 0,
                            removedCount: 0,
                            cancelledCount: 0,
                            message: String(describing: error)
                        )
                    )
                }
            }
        } catch {
            scenarioReports.append(
                StressScenarioReport(
                    name: "Workspace",
                    status: .failed,
                    durationSeconds: 0,
                    operations: 0,
                    generatedCount: 0,
                    memoryHitCount: 0,
                    storageHitCount: 0,
                    regeneratedCount: 0,
                    removedCount: 0,
                    cancelledCount: 0,
                    message: String(describing: error)
                )
            )
        }

        return StressReport(
            profile: command.profile.name,
            seed: command.seed,
            success: scenarioReports.allSatisfy { $0.status == .passed },
            durationSeconds: Date().timeIntervalSince(startedAt),
            scenarios: scenarioReports
        )
    }

    private func withTimeout<T: Sendable>(
        seconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(1, seconds)) * 1_000_000_000)
                throw StressFailure("Timed out after \(seconds) seconds.")
            }

            guard let result = try await group.next() else {
                throw StressFailure("Scenario did not produce a result.")
            }
            group.cancelAll()
            return result
        }
    }
}

private struct StressWorkspace {
    let rootDirectory: URL

    init(command: StressCommand) throws {
        let parent = command.rootURL ?? FileManager.default.temporaryDirectory
        rootDirectory = parent.appendingPathComponent(
            "YashimaStressRunner-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }
}

public struct StressScenarioContext: Sendable {
    public let profile: StressProfile
    public let seed: Int
    public let rootDirectory: URL
}

public struct StressScenario: Sendable {
    public let name: String
    public let run: @Sendable (StressScenarioContext) async throws -> StressScenarioSummary

    public init(
        name: String,
        run: @escaping @Sendable (StressScenarioContext) async throws -> StressScenarioSummary
    ) {
        self.name = name
        self.run = run
    }

    var safeName: String {
        name
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? character : "-"
            }
            .reduce(into: "") { partial, character in
                if character == "-", partial.last == "-" {
                    return
                }
                partial.append(character)
            }
    }
}

public struct StressFailure: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}
