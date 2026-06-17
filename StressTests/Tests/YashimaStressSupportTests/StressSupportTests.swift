import Foundation
import Testing
import YashimaStressSupport

@Test func stressProfilesExposePlannedDefaults() {
    #expect(StressProfile.smoke.keyCount == 120)
    #expect(StressProfile.smoke.concurrency == 24)
    #expect(StressProfile.smoke.singleFlightFanout == 64)
    #expect(StressProfile.smoke.maximumPayloadByteCount == 32 * 1024)
    #expect(StressProfile.standard.timeoutSeconds == 5 * 60)
    #expect(StressProfile.soak.timeoutSeconds == 30 * 60)
}

@Test func commandParserUsesSmokeDefaults() throws {
    let command = try StressCommand.parse(arguments: ["runner"])

    #expect(command.profile == .smoke)
    #expect(command.seed == 1)
    #expect(command.rootURL == nil)
    #expect(!command.keepsArtifacts)
    #expect(command.format == .text)
}

@Test func commandParserAcceptsLongOptions() throws {
    let command = try StressCommand.parse(arguments: [
        "runner",
        "--profile", "standard",
        "--seed=42",
        "--root", "/tmp/yashima-stress",
        "--keep-artifacts",
        "--format=json",
    ])

    #expect(command.profile == .standard)
    #expect(command.seed == 42)
    #expect(command.rootURL?.path == "/tmp/yashima-stress")
    #expect(command.keepsArtifacts)
    #expect(command.format == .json)
}

@Test func deterministicPayloadIsStableForSeedAndIndex() {
    let first = DeterministicPayload.data(seed: 7, index: 11, profile: .smoke)
    let second = DeterministicPayload.data(seed: 7, index: 11, profile: .smoke)
    let other = DeterministicPayload.data(seed: 7, index: 12, profile: .smoke)

    #expect(first == second)
    #expect(first != other)
    #expect(first.count >= StressProfile.smoke.minimumPayloadByteCount)
    #expect(first.count <= StressProfile.smoke.maximumPayloadByteCount)
}

@Test func redactorRemovesLocalPathShapes() {
    let message = #"failed at /private/tmp/example/file.txt and file:///private/tmp/example/file.txt"#
    let redacted = Redactor.sanitize(message)

    #expect(!redacted.contains("/private/tmp/example"))
    #expect(redacted.contains("<path>"))
    #expect(redacted.contains("<file-url>"))
}
