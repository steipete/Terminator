import ArgumentParser
import Foundation

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read output from a session.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Argument(help: "Unique identifier for the session.")
    var tag: String

    @Option(name: .long, help: "Absolute path to the project directory. Env: TERMINATOR_PROJECT_PATH")
    var projectPath: String?
    
    @Option(name: .long, help: "Maximum number of recent output lines to return. Env: TERMINATOR_DEFAULT_LINES")
    var lines: Int?

    @Option(name: .long, help: "Focus behavior. See 'exec --help'. Env: TERMINATOR_DEFAULT_FOCUS_ON_ACTION") 
    var focusMode: String?

    mutating func run() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: lines,
            backgroundStartupOption: nil,
            foregroundCompletionOption: nil,
            defaultFocusOption: nil,
            sigintWaitOption: nil,
            sigtermWaitOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        
        Logger.log(level: .info, "Reading output... Tag: \(tag), Project: \(projectPath ?? "N/A")")
        let resolvedLines = lines ?? config.defaultLines
        let resolvedFocusPreference = AppConfig.FocusCLIArgument(rawValue: focusMode ?? config.defaultFocusOnAction ? "auto-behavior" : "no-focus") ?? .autoBehavior
        Logger.log(level: .debug, "  Lines to read: \(resolvedLines)")
        Logger.log(level: .debug, "  Focus Mode CLI: \(focusMode ?? "not set, using default logic") -> \(resolvedFocusPreference.rawValue)")

        let readParams = ReadSessionParams(
            projectPath: projectPath,
            tag: tag,
            linesToRead: resolvedLines,
            focusPreference: resolvedFocusPreference
        )

        do {
            let result: ReadSessionResult
            
            switch config.terminalAppEnum {
            case .appleTerminal:
                let appleTerminalController = AppleTerminalControl(config: config, appName: config.terminalApp)
                result = try appleTerminalController.readSessionOutput(params: readParams)
                
            case .iterm:
                let iTermController = ITermControl(config: config, appName: config.terminalApp)
                result = try iTermController.readSessionOutput(params: readParams)
                
            case .ghosty:
                // GhostyControl may not exist yet, so we'll handle it with a placeholder
                Logger.log(level: .error, "Ghosty read operation not implemented")
                throw TerminalControllerError.unsupportedTerminalApp(appName: config.terminalApp)
                
            case .unknown:
                Logger.log(level: .error, "Unknown terminal application for read: \(config.terminalApp)")
                throw TerminalControllerError.unsupportedTerminalApp(appName: config.terminalApp)
            }
            
            print(result.output)
            throw ExitCode(ErrorCodes.success)
        } catch let error as TerminalControllerError {
            fputs("Error reading session output: \(error.localizedDescription)\nScript (if applicable):\n\(error.scriptContent ?? "N/A")\n", stderr)
            throw ExitCode(error.suggestedErrorCode)
        } catch {
            fputs("An unexpected error occurred while reading session: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }
} 