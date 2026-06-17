import Darwin
import Foundation
import YashimaStressSupport

@main
struct YashimaStressRunner {
    static func main() async {
        do {
            let command = try StressCommand.parse(arguments: CommandLine.arguments)
            if command.showsHelp {
                print(StressCommand.usage)
                Darwin.exit(0)
            }

            let report = await StressRunner(command: command).run()
            switch command.format {
            case .text:
                print(report.renderedText())
            case .json:
                print(try report.renderedJSON())
            }

            Darwin.exit(report.success ? 0 : 1)
        } catch let error as StressCommandError {
            writeError(error.description)
            writeError("")
            writeError(StressCommand.usage)
            Darwin.exit(2)
        } catch {
            writeError(Redactor.sanitize(String(describing: error)))
            Darwin.exit(1)
        }
    }

    private static func writeError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
