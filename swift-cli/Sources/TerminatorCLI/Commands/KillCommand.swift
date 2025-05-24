import ArgumentParser
import Foundation

struct Kill: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Kill the process in a specific session.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Option(name: .long, help: "Absolute path to the project directory.")
    var projectPath: String?

    @Option(name: .long, help: "Tag identifying the session.")
    var tag: String // Required

    @Option(name: [.long, .customShort("f")], help: "Focus mode (force-focus, no-focus, auto-behavior) for any screen clearing/focusing done after kill.")
    var focusMode: String?

    mutating func run() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil, backgroundStartupOption: nil, foregroundCompletionOption: nil,
            defaultFocusOption: nil, // Focus preference for ancillary actions like screen clearing
            sigintWaitOption: nil, // Will use AppConfig defaults
            sigtermWaitOption: nil, // Will use AppConfig defaults
            defaultFocusOnKillOption: nil // Will use AppConfig defaults
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'kill' command for tag: \(tag)" + (projectPath != nil ? " in project: \(projectPath!)" : ""))
        
        let resolvedFocusMode: AppConfig.FocusCLIArgument
        if let focusModeString = focusMode?.lowercased(), let mode = AppConfig.FocusCLIArgument(rawValue: focusModeString) {
            resolvedFocusMode = mode
        } else {
            resolvedFocusMode = .autoBehavior
        }

        let killParams = KillSessionParams(
            projectPath: projectPath,
            tag: tag,
            focusPreference: resolvedFocusMode // For post-kill actions like screen clearing if implemented with focus
        )

        do {
            let result: KillSessionResult
            
            switch config.terminalAppEnum {
            case .appleTerminal:
                let appleTerminalController = AppleTerminalControl(config: config, appName: config.terminalApp)
                result = try appleTerminalController.killProcessInSession(params: killParams)
            case .iTerm:
                let iTermController = ITermControl(config: config, appName: config.terminalApp)
                result = try iTermController.killProcessInSession(params: killParams)
            case .ghosty:
                Logger.log(level: .error, "Ghosty kill operation not fully supported")
                throw ExitCode(ErrorCodes.unsupportedOperationForApp)
            case .unknown:
                Logger.log(level: .error, "Unknown terminal application for kill: \(config.terminalApp)")
                throw ExitCode(ErrorCodes.configurationError)
            }
            
            print("Terminator: Process in session '\(result.killedSessionInfo.sessionIdentifier)' was targeted for termination. Success: \(result.killSuccess)")
            if !result.killSuccess {
                 fputs("Warning: Kill command issued, but process might still be running or was not found.\n", stderr)
            }
            throw ExitCode(result.killSuccess ? ErrorCodes.success : ErrorCodes.generalError)
        } catch let error as TerminalControllerError {
            var exitCode: Int32 = ErrorCodes.generalError
            switch error {
            case .sessionNotFound:
                exitCode = ErrorCodes.sessionNotFound
                fputs("Error: Session for tag '\(tag)' in project '\(projectPath ?? "N/A")' not found for kill.\n", stderr)
            case .appleScriptError(let msg, _, _):
                exitCode = ErrorCodes.appleScriptError
                fputs("Error: AppleScript failed during kill operation. Details: \(msg)\n", stderr)
            case .busy(let tty, let processDescription):
                exitCode = ErrorCodes.sessionBusyError
                var errorMsg = "Error: Session on TTY '\(tty)' is busy during kill."
                if let procDesc = processDescription {
                    errorMsg += " Process: \(procDesc)"
                }
                fputs("\(errorMsg)\n", stderr)
            case .unsupportedTerminalApp:
                exitCode = ErrorCodes.configurationError
                fputs("Error: The configured terminal application ('\(config.terminalApp)') is not supported for kill operations.\n", stderr)
            default:
                exitCode = ErrorCodes.generalError
                fputs("Error: Failed to kill session process. Details: \(error.localizedDescription)\n", stderr)
            }
            throw ExitCode(exitCode)
        } catch {
            fputs("Error: An unexpected error occurred during the kill operation: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }
} 