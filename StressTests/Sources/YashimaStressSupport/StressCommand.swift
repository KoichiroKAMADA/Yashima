import Foundation

public enum StressOutputFormat: String, Codable, Equatable, Sendable {
    case text
    case json
}

public struct StressCommand: Equatable, Sendable {
    public var profile: StressProfile
    public var seed: Int
    public var rootURL: URL?
    public var keepsArtifacts: Bool
    public var format: StressOutputFormat
    public var showsHelp: Bool

    public init(
        profile: StressProfile = .smoke,
        seed: Int = 1,
        rootURL: URL? = nil,
        keepsArtifacts: Bool = false,
        format: StressOutputFormat = .text,
        showsHelp: Bool = false
    ) {
        self.profile = profile
        self.seed = seed
        self.rootURL = rootURL
        self.keepsArtifacts = keepsArtifacts
        self.format = format
        self.showsHelp = showsHelp
    }

    public static let usage = """
    Usage:
      swift run --package-path StressTests YashimaStressRunner [options]

    Options:
      --profile smoke|standard|soak   Stress profile to run. Default: smoke.
      --seed <int>                    Deterministic payload seed. Default: 1.
      --root <path>                   Parent directory for the generated workspace.
      --keep-artifacts                Keep generated files for local inspection.
      --format text|json              Report format. Default: text.
      -h, --help                      Show this help.
    """

    public static func parse(arguments: [String]) throws -> StressCommand {
        var command = StressCommand()
        var index = arguments.isEmpty ? 0 : 1

        while index < arguments.count {
            let argument = arguments[index]

            if argument == "-h" || argument == "--help" {
                command.showsHelp = true
                index += 1
                continue
            }

            if argument == "--keep-artifacts" {
                command.keepsArtifacts = true
                index += 1
                continue
            }

            if let value = argument.valueForLongOption("--profile") {
                command.profile = try parseProfile(value)
                index += 1
                continue
            }

            if let value = argument.valueForLongOption("--seed") {
                command.seed = try parseSeed(value)
                index += 1
                continue
            }

            if let value = argument.valueForLongOption("--root") {
                command.rootURL = try parseRootURL(value)
                index += 1
                continue
            }

            if let value = argument.valueForLongOption("--format") {
                command.format = try parseFormat(value)
                index += 1
                continue
            }

            switch argument {
            case "--profile":
                let value = try value(after: argument, at: index, in: arguments)
                command.profile = try parseProfile(value)
                index += 2
            case "--seed":
                let value = try value(after: argument, at: index, in: arguments)
                command.seed = try parseSeed(value)
                index += 2
            case "--root":
                let value = try value(after: argument, at: index, in: arguments)
                command.rootURL = try parseRootURL(value)
                index += 2
            case "--format":
                let value = try value(after: argument, at: index, in: arguments)
                command.format = try parseFormat(value)
                index += 2
            default:
                throw StressCommandError.unknownOption(argument)
            }
        }

        return command
    }

    private static func value(
        after option: String,
        at index: Int,
        in arguments: [String]
    ) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw StressCommandError.missingValue(option)
        }
        return arguments[valueIndex]
    }

    private static func parseProfile(_ value: String) throws -> StressProfile {
        guard let profile = StressProfile.named(value) else {
            throw StressCommandError.invalidProfile(value)
        }
        return profile
    }

    private static func parseSeed(_ value: String) throws -> Int {
        guard let seed = Int(value) else {
            throw StressCommandError.invalidSeed(value)
        }
        return seed
    }

    private static func parseRootURL(_ value: String) throws -> URL {
        guard !value.isEmpty else {
            throw StressCommandError.invalidRoot(value)
        }

        let expanded = (value as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    private static func parseFormat(_ value: String) throws -> StressOutputFormat {
        guard let format = StressOutputFormat(rawValue: value) else {
            throw StressCommandError.invalidFormat(value)
        }
        return format
    }
}

public enum StressCommandError: Error, Equatable, CustomStringConvertible, Sendable {
    case unknownOption(String)
    case missingValue(String)
    case invalidProfile(String)
    case invalidSeed(String)
    case invalidRoot(String)
    case invalidFormat(String)

    public var description: String {
        switch self {
        case .unknownOption(let option):
            return "Unknown option: \(option)"
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .invalidProfile(let value):
            return "Invalid profile: \(value)"
        case .invalidSeed(let value):
            return "Invalid seed: \(value)"
        case .invalidRoot:
            return "Invalid root path."
        case .invalidFormat(let value):
            return "Invalid format: \(value)"
        }
    }
}

private extension String {
    func valueForLongOption(_ option: String) -> String? {
        let prefix = option + "="
        guard hasPrefix(prefix) else {
            return nil
        }
        return String(dropFirst(prefix.count))
    }
}
