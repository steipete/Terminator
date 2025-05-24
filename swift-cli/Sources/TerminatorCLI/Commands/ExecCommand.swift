import ArgumentParser
import Foundation

struct Exec: ParsableCommand { // Changed from TerminatorSubcommand to ParsableCommand as it's standalone now
    static let configuration = CommandConfiguration(abstract: "Execute a command in a session.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Explicitly reference GlobalOptions from TerminatorCLI

    @Argument(help: "Unique identifier for the session.")
    var tag: String

    @Option(name: .long, help: "Absolute path to the project directory. Env: TERMINATOR_PROJECT_PATH")
    var projectPath: String?

    @Option(name: .long, help: "The shell command to execute. If omitted, session is prepared (cleared, focused) but no command runs.")
    var command: String?
    
    @Flag(name: .long, help: "Run command in background. Default: false.")
    var background: Bool = false

    @Option(name: .long, help: "Maximum number of recent output lines to return for foreground commands. Env: TERMINATOR_DEFAULT_LINES")
    var lines: Int?

    @Option(name: .long, help: "Timeout in seconds for the command. Env: TERMINATOR_FOREGROUND_COMPLETION_SECONDS / TERMINATOR_BACKGROUND_STARTUP_SECONDS")
    var timeout: Int?

    @Option(name: .long, help: "Focus behavior (force-focus, no-focus, auto-behavior). Env: TERMINATOR_DEFAULT_FOCUS_ON_ACTION") 
    var focusMode: String?

    mutating func run() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: lines, // Pass directly from option
            backgroundStartupOption: background ? timeout : nil, // Pass timeout if background
            foregroundCompletionOption: !background ? timeout : nil, // Pass timeout if foreground
            defaultFocusOption: nil, // Focus is handled by focusMode string
            sigintWaitOption: nil, // These are global, not per-command usually
            sigtermWaitOption: nil
        )
        let config = TerminatorCLI.currentConfig!

        Logger.log(level: .info, "Executing command... Tag: \(tag), Project: \(projectPath ?? "N/A")")
        if let cmd = command, !cmd.isEmpty {
            Logger.log(level: .debug, "  Command: \(cmd)") // Command logged at debug for PII
        } else {
            Logger.log(level: .info, "  No command provided. Preparing session only.")
        }
        Logger.log(level: .debug, "  Background: \(background)")
        
        let resolvedLines = lines ?? config.defaultLines
        let resolvedTimeout = timeout ?? (background ? config.backgroundStartupSeconds : config.foregroundCompletionSeconds)
        let resolvedFocusPreference = AppConfig.FocusCLIArgument(rawValue: focusMode ?? config.defaultFocusOnAction ? "auto-behavior" : "no-focus") ?? .autoBehavior

        Logger.log(level: .debug, "  Lines to capture: \(resolvedLines)")
        Logger.log(level: .debug, "  Timeout: \(resolvedTimeout)s")
        Logger.log(level: .debug, "  Focus Mode CLI: \(focusMode ?? "not set, using default logic") -> \(resolvedFocusPreference.rawValue)")

        let execParams = ExecuteCommandParams(
            projectPath: projectPath,
            tag: tag,
            command: command,
            executionMode: background ? .background : .foreground,
            linesToCapture: resolvedLines,
            timeout: resolvedTimeout,
            focusPreference: resolvedFocusPreference 
        )

        do {
            let result: ExecuteCommandResult
            
            switch config.terminalAppEnum {
            case .appleTerminal:
                let appleTerminalController = AppleTerminalControl(config: config, appName: config.terminalApp)
                result = try appleTerminalController.executeCommand(params: execParams)
            case .iTerm:
                let iTermController = ITermControl(config: config, appName: config.terminalApp)
                result = try iTermController.executeCommand(params: execParams)
            case .ghosty:
                // GhostyControl implementation pending
                Logger.log(level: .error, "Ghosty terminal control not yet implemented")
                throw TerminalControllerError.unsupportedTerminalApp(appName: config.terminalApp)
            case .unknown:
                Logger.log(level: .error, "Unsupported terminal application for exec: \(config.terminalApp)")
                throw ExitCode(ErrorCodes.configurationError)
            }
            // Output from exec is now primarily handled by the Node.js wrapper based on success/failure.
            // The Swift CLI will print essential info or errors to its stdout/stderr.
            if result.wasKilledByTimeout {
                fputs("Terminator: Command '\(command ?? "<session prep>")' for tag '\(tag)' timed out after \(resolvedTimeout) seconds.\nOutput (if any) captured before timeout:\n\(result.output ?? "<no output>")\n", stderr)
                throw ExitCode(ErrorCodes.timeoutError) // Specific timeout error
            } else {
                // For successful foreground commands, print their output
                if !background, let output = result.output, let cmd = command, !cmd.isEmpty {
                    print(output) 
                }
                // For background, a success message is usually handled by the wrapper.
                // Here we just ensure clean exit.
                if background, let cmd = command, !cmd.isEmpty {
                    Logger.log(level: .info, "Background command '\(cmd)' submitted successfully for tag '\(tag)'. PID (if available): \(result.pid?.description ?? "N/A")")
                } else if command == nil || command!.isEmpty {
                     Logger.log(level: .info, "Session '\(tag)' prepared successfully.")
                }
                throw ExitCode(ErrorCodes.success) // Ensure success exit code
            }
        } catch let error as TerminalControllerError {
            fputs("Error executing command: \(error.localizedDescription)\nScript (if applicable):\n\(error.scriptContent ?? "N/A")\n", stderr)
            throw ExitCode(error.suggestedErrorCode)
        } catch {
            fputs("An unexpected error occurred: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }
} 