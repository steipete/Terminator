import ArgumentParser
import Foundation

struct Kill: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Kill the process in a specific session.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Option(name: .long, help: "Absolute path to the project directory.")
    var projectPath: String?

    @Option(name: .long, help: "Tag identifying the session.")
    var tag: String // Required

    @Option(
        name: [.long, .customShort("f")],
        help: "Focus mode (force-focus, no-focus, auto-behavior) for any screen clearing/focusing done after kill."
    )
    var focusMode: String?

    @Option(name: .long, help: "Focus on kill (true/false) for any screen clearing/focusing done after kill.")
    var focusOnKill: Bool

    mutating func run() throws {
        let config = setupConfig()
        logCommand()

        let killParams = prepareKillParams()

        do {
            let result = try executeKill(config: config, params: killParams)
            reportResult(result)
            throw ExitCode(result.killSuccess ? ErrorCodes.success : ErrorCodes.generalError)
        } catch let error as TerminalControllerError {
            throw handleTerminalError(error, config: config)
        } catch {
            handleGeneralError(error)
        }
    }

    private mutating func setupConfig() -> AppConfig {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil,
            backgroundStartupOption: nil,
            foregroundCompletionOption: nil,
            defaultFocusOption: focusMode != nil ? (AppConfig.FocusCLIArgument(rawValue: focusMode!) != .noFocus) : nil,
            sigintWaitOption: globals.sigintWaitSeconds,
            sigtermWaitOption: globals.sigtermWaitSeconds,
            defaultFocusOnKillOption: focusOnKill,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: nil,
            iTermProfileNameOption: nil
        )
        return TerminatorCLI.currentConfig!
    }

    private func logCommand() {
        Logger.log(
            level: .info,
            "Executing 'kill' command for tag: \(tag)" + (projectPath != nil ? " in project: \(projectPath!)" : "")
        )
    }

    private func prepareKillParams() -> KillSessionParams {
        let resolvedFocusMode: AppConfig.FocusCLIArgument = if let focusModeString = focusMode?.lowercased(),
                                                               let mode = AppConfig
                                                               .FocusCLIArgument(rawValue: focusModeString) {
            mode
        } else {
            .autoBehavior
        }

        return KillSessionParams(
            projectPath: projectPath,
            tag: tag,
            focusPreference: resolvedFocusMode
        )
    }

    private func executeKill(config: AppConfig, params: KillSessionParams) throws -> KillSessionResult {
        switch config.terminalAppEnum {
        case .appleTerminal:
            let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
            return try controller.killProcessInSession(params: params)
        case .iterm:
            let controller = ITermControl(config: config, appName: config.terminalApp)
            return try controller.killProcessInSession(params: params)
        case .ghosty:
            Logger.log(level: .error, "Ghosty kill operation not fully supported")
            throw ExitCode(ErrorCodes.unsupportedOperationForApp)
        case .unknown:
            Logger.log(level: .error, "Unknown terminal application for kill: \(config.terminalApp)")
            throw ExitCode(ErrorCodes.configurationError)
        }
    }

    private func reportResult(_ result: KillSessionResult) {
        print(
            "Terminator: Process in session '\(result.killedSessionInfo.sessionIdentifier)' was targeted for termination. Success: \(result.killSuccess)"
        )
        if !result.killSuccess {
            fputs("Warning: Kill command issued, but process might still be running or was not found.\n", stderr)
        }
    }

    private func handleTerminalError(_ error: TerminalControllerError, config: AppConfig) -> ExitCode {
        var exitCode: Int32 = ErrorCodes.generalError

        switch error {
        case .sessionNotFound:
            exitCode = ErrorCodes.sessionNotFound
            fputs(
                "Error: Session for tag '\(tag)' in project '\(projectPath ?? "N/A")' not found for kill.\n",
                stderr
            )
        case let .appleScriptError(msg, _, _):
            exitCode = ErrorCodes.appleScriptError
            fputs("Error: AppleScript failed during kill operation. Details: \(msg)\n", stderr)
        case let .busy(tty, processDescription):
            exitCode = ErrorCodes.sessionBusyError
            var errorMsg = "Error: Session on TTY '\(tty)' is busy during kill."
            if let procDesc = processDescription {
                errorMsg += " Process: \(procDesc)"
            }
            fputs("\(errorMsg)\n", stderr)
        case .unsupportedTerminalApp:
            exitCode = ErrorCodes.configurationError
            fputs(
                "Error: The configured terminal application ('\(config.terminalApp)') is not supported for kill operations.\n",
                stderr
            )
        default:
            exitCode = ErrorCodes.generalError
            fputs("Error: Failed to kill session process. Details: \(error.localizedDescription)\n", stderr)
        }

        return ExitCode(exitCode)
    }

    private func handleGeneralError(_ error: Error) -> Never {
        fputs(
            "Error: An unexpected error occurred during the kill operation: \(error.localizedDescription)\n",
            stderr
        )
        exit(ErrorCodes.generalError)
    }
}
