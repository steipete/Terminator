import ArgumentParser
import Foundation

struct Execute: ParsableCommand { // Changed from TerminatorSubcommand to ParsableCommand as it's standalone now
    static let configuration = CommandConfiguration(
        commandName: "execute",
        abstract: "Execute a command in a session."
    )

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Explicitly reference GlobalOptions from TerminatorCLI

    @Argument(help: "Unique identifier for the session.")
    var tag: String

    @Option(name: .long, help: "Absolute path to the project directory. Env: TERMINATOR_PROJECT_PATH")
    var projectPath: String?

    @Option(
        name: .long,
        help: "The shell command to execute. If omitted, session is prepared (cleared, focused) but no command runs."
    )
    var command: String?

    @Flag(name: .long, help: "Run command in background. Default: false.")
    var background: Bool = false

    @Option(
        name: .long,
        help: "Maximum number of recent output lines to return for foreground commands. Env: TERMINATOR_DEFAULT_LINES"
    )
    var lines: Int?

    @Option(
        name: .long,
        help: "Timeout in seconds for the command. Env: TERMINATOR_FOREGROUND_COMPLETION_SECONDS / TERMINATOR_BACKGROUND_STARTUP_SECONDS"
    )
    var timeout: Int?

    @Option(
        name: .long,
        help: "Focus behavior (force-focus, no-focus, auto-behavior). Env: TERMINATOR_DEFAULT_FOCUS_ON_ACTION"
    )
    var focusMode: String?

    @Flag(name: .long, help: "Reuse busy sessions. Default: false.")
    var reuseBusySession: Bool = false

    mutating func run() throws {
        let config = setupConfig()
        logCommandExecution()

        let params = prepareExecutionParams(config: config)

        do {
            let result = try executeCommand(config: config, params: params)
            try processResult(result, params: params)
        } catch let error as TerminalControllerError {
            var errorMessage = "Error executing command: \(error.localizedDescription)\n"

            // Check if this is a System Events permission error
            if case let .appleScriptError(_, _, underlyingError) = error,
               let scriptError = underlyingError as? AppleScriptError,
               case .systemEventsPermissionDenied = scriptError {
                errorMessage += "\n🔐 System Events Permission Required:\n"
                errorMessage += "1. Open System Settings > Privacy & Security > Accessibility\n"
                errorMessage += "2. Enable access for Terminal (or the terminal app you're using)\n"
                errorMessage += "3. You may need to restart Terminal after granting permission\n"
                errorMessage += "\nNote: This is required for creating new Terminal tabs programmatically.\n"
            } else {
                errorMessage += "Script (if applicable):\n\(error.scriptContent ?? "N/A")\n"
            }

            fputs(errorMessage, stderr)
            throw ExitCode(error.suggestedErrorCode)
        } catch {
            fputs("An unexpected error occurred: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }

    private mutating func setupConfig() -> AppConfig {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: lines,
            backgroundStartupOption: background ? timeout : nil,
            foregroundCompletionOption: !background ? timeout : nil,
            defaultFocusOption: focusMode != nil ? (AppConfig.FocusCLIArgument(rawValue: focusMode!) != .noFocus) : nil,
            sigintWaitOption: globals.sigintWaitSeconds,
            sigtermWaitOption: globals.sigtermWaitSeconds,
            defaultFocusOnKillOption: nil,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: reuseBusySession,
            iTermProfileNameOption: nil
        )
        return TerminatorCLI.currentConfig!
    }

    private func logCommandExecution() {
        Logger.log(level: .info, "Executing command... Tag: \(tag), Project: \(projectPath ?? "N/A")")
        if let cmd = command, !cmd.isEmpty {
            Logger.log(level: .debug, "  Command: \(cmd)")
        } else {
            Logger.log(level: .info, "  No command provided. Preparing session only.")
        }
        Logger.log(level: .debug, "  Background: \(background)")
    }

    private func prepareExecutionParams(config: AppConfig) -> ExecuteCommandParams {
        let resolvedLines = max(0, lines ?? config.defaultLines)
        let resolvedTimeout = timeout ??
            (background ? config.backgroundStartupSeconds : config.foregroundCompletionSeconds)

        let focusPreferenceString: String = if let fm = focusMode, !fm.isEmpty {
            fm
        } else {
            config.defaultFocusOnAction ? "auto-behavior" : "no-focus"
        }
        let resolvedFocusPreference = AppConfig.FocusCLIArgument(rawValue: focusPreferenceString) ?? .autoBehavior

        Logger.log(level: .debug, "  Lines to capture: \(resolvedLines)")
        Logger.log(level: .debug, "  Timeout: \(resolvedTimeout)s")
        Logger.log(level: .debug, "  Focus Mode CLI: \(focusMode ?? "nil") -> \(resolvedFocusPreference.rawValue)")

        return ExecuteCommandParams(
            projectPath: projectPath,
            tag: tag,
            command: command,
            executionMode: background ? .background : .foreground,
            linesToCapture: resolvedLines,
            timeout: resolvedTimeout,
            focusPreference: resolvedFocusPreference
        )
    }

    private func executeCommand(config: AppConfig, params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        switch config.terminalAppEnum {
        case .appleTerminal:
            let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
            return try controller.executeCommand(params: params)
        case .iterm:
            let controller = ITermControl(config: config, appName: config.terminalApp)
            return try controller.executeCommand(params: params)
        case .ghosty:
            Logger.log(level: .error, "Ghosty terminal control not yet implemented")
            throw TerminalControllerError.unsupportedTerminalApp(appName: config.terminalApp)
        case .unknown:
            Logger.log(level: .error, "Unsupported terminal application for exec: \(config.terminalApp)")
            throw ExitCode(ErrorCodes.configurationError)
        }
    }

    private func processResult(_ result: ExecuteCommandResult, params: ExecuteCommandParams) throws -> Never {
        if result.wasKilledByTimeout {
            fputs(
                "Terminator: Command '\(command ?? "<session prep>")' for tag '\(tag)' timed out after \(params.timeout) seconds.\nOutput (if any) captured before timeout:\n\(result.output ?? "<no output>")\n",
                stderr
            )
            throw ExitCode(ErrorCodes.timeoutError)
        } else {
            handleSuccessfulResult(result)
            throw ExitCode(ErrorCodes.success)
        }
    }

    private func handleSuccessfulResult(_ result: ExecuteCommandResult) {
        if !background, let outputText = result.output, let cmd = command, !cmd.isEmpty {
            print(outputText)
        }

        if background, let cmd = command, !cmd.isEmpty {
            Logger.log(
                level: .info,
                "Background command '\(cmd)' submitted successfully for tag '\(tag)'. PID (if available): \(result.pid?.description ?? "N/A")"
            )
        } else if command == nil || command!.isEmpty {
            Logger.log(level: .info, "Session '\(tag)' prepared successfully.")
        }
    }
}
