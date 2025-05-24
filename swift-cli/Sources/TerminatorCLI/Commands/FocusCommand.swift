import ArgumentParser
import Foundation

struct Focus: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Focus a specific session (bring its terminal window and tab to front).")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Option(name: .long, help: "Absolute path to the project directory.")
    var projectPath: String?

    @Option(name: .long, help: "Tag identifying the session.")
    var tag: String // Required

    mutating func run() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil, backgroundStartupOption: nil, foregroundCompletionOption: nil,
            defaultFocusOption: nil, sigintWaitOption: nil, sigtermWaitOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'focus' command for tag: \(tag)" + (projectPath != nil ? " in project: \(projectPath!)" : ""))

        // Focus always implies force-focus for the purpose of the `focus` command itself.
        // The `focusMode` CLI flag is for actions like `execute` or `read` to control ancillary focus.
        let focusParams = FocusSessionParams(projectPath: projectPath, tag: tag)

        do {
            let result: FocusSessionResult
            
            switch config.terminalAppEnum {
            case .appleTerminal:
                Logger.log(level: .debug, "Instantiating AppleTerminalControl for focus operation.")
                let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
                result = try controller.focusSession(params: focusParams)
                
            case .iterm:
                Logger.log(level: .debug, "Instantiating ITermControl for focus operation.")
                let controller = ITermControl(config: config, appName: config.terminalApp)
                result = try controller.focusSession(params: focusParams)
                
            case .ghosty:
                Logger.log(level: .debug, "Attempting to instantiate GhostyControl for focus operation.")
                // GhostyControl is not yet implemented
                Logger.log(level: .error, "GhostyControl is not yet implemented.")
                throw ExitCode(rawValue: ErrorCodes.configurationError)!
                
            case .unknown:
                Logger.log(level: .error, "Unknown terminal application: \(config.terminalApp)")
                throw ExitCode(rawValue: ErrorCodes.configurationError)!
            }
            
            print("Terminator: Session '\(result.focusedSessionInfo.sessionIdentifier)' is now focused.")
            throw ExitCode(rawValue: ErrorCodes.success)!
        } catch let error as TerminalControllerError {
            var exitCode: Int32 = ErrorCodes.generalError
            switch error {
            case .sessionNotFound:
                exitCode = ErrorCodes.sessionNotFound
                fputs("Error: Session for tag '\(tag)' in project '\(projectPath ?? "N/A")' not found for focus.\n", stderr)
            case .appleScriptError(let msg, _, _):
                exitCode = ErrorCodes.appleScriptError
                fputs("Error: AppleScript failed during focus operation. Details: \(msg)\n", stderr)
            case .unsupportedTerminalApp:
                exitCode = ErrorCodes.configurationError
                fputs("Error: The configured terminal application ('\(config.terminalApp)') is not supported for focus operations.\n", stderr)
            default:
                exitCode = ErrorCodes.generalError
                fputs("Error: Failed to focus session. Details: \(error.localizedDescription)\n", stderr)
            }
            throw ExitCode(rawValue: exitCode)!
        } catch {
            fputs("Error: An unexpected error occurred during the focus operation: \(error.localizedDescription)\n", stderr)
            throw ExitCode(rawValue: ErrorCodes.generalError)!
        }
    }
} 