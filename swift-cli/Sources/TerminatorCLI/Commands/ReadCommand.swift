import ArgumentParser
import Foundation

struct Read: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Read output from a session.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Option(name: .long, help: "Tag identifying the session.")
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
            defaultFocusOption: focusMode != nil ? (AppConfig.FocusCLIArgument(rawValue: focusMode!) != .noFocus) : nil,
            sigintWaitOption: globals.sigintWaitSeconds,
            sigtermWaitOption: globals.sigtermWaitSeconds,
            defaultFocusOnKillOption: nil,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        
        Logger.log(level: .info, "Reading output... Tag: \(tag), Project: \(projectPath ?? "N/A")")
        let resolvedLines = lines ?? config.defaultLines
        
        let focusPreferenceString: String
        if let fm = focusMode, !fm.isEmpty {
            focusPreferenceString = fm
        } else {
            focusPreferenceString = config.defaultFocusOnAction ? "auto-behavior" : "no-focus"
        }
        let resolvedFocusPreference = AppConfig.FocusCLIArgument(rawValue: focusPreferenceString) ?? .autoBehavior
        
        Logger.log(level: .debug, "  Lines to read: \(resolvedLines)")
        Logger.log(level: .debug, "  Focus Mode CLI: \(focusMode ?? "nil") -> \(resolvedFocusPreference.rawValue)")

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
            let baseErrorMessage = "Error reading session output for tag \"\(tag)\""
            let projectContext = projectPath != nil ? " in project \"\(projectPath!)\"" : ""
            let detailedErrorMessage = "\(baseErrorMessage)\(projectContext). Details: \(error.localizedDescription)"
            
            fputs("\(detailedErrorMessage)\n", stderr)
            if let scriptContent = error.scriptContent, !scriptContent.isEmpty {
                fputs("Underlying script (if applicable):\n\(scriptContent)\n", stderr)
            }
            throw ExitCode(error.suggestedErrorCode)
        } catch {
            let baseErrorMessage = "An unexpected error occurred while reading session output for tag \"\(tag)\""
            let projectContext = projectPath != nil ? " in project \"\(projectPath!)\"" : ""
            let detailedErrorMessage = "\(baseErrorMessage)\(projectContext). Details: \(error.localizedDescription)"

            fputs("\(detailedErrorMessage)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }
} 