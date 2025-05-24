import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List active Terminator sessions.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Adjusted for external reference

    @Option(name: .long, help: "Filter sessions by project path.")
    var projectPath: String?
    
    @Flag(name: .long, help: "Output in JSON format.")
    var json: Bool = false

    mutating func run() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil,
            backgroundStartupOption: nil,
            foregroundCompletionOption: nil,
            defaultFocusOption: nil,
            sigintWaitOption: nil,
            sigtermWaitOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'list' command." + (projectPath != nil ? " Filtering by project: \(projectPath!)" : ""))

        do {
            let sessions: [TerminalSessionInfo]
            
            switch config.terminalAppEnum {
            case .appleterminal:
                let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: nil)
            case .iterm2:
                let controller = ITermControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: nil)
            case .ghosty:
                let controller = GhostyControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: nil)
            case .unknown:
                throw ExitCode(ErrorCodes.configurationError)
            }
            
            let filteredSessions: [TerminalSessionInfo]
            if let projPath = projectPath {
                // Attempt to filter by project path. This might require a more robust matching 
                // if projectPath in sessionInfo is a hash or a different format.
                // For now, assumes direct string comparison or that sessionInfo.projectPath stores something comparable.
                let targetProjectHash = SessionUtilities.generateProjectHash(projectPath: projPath)
                filteredSessions = sessions.filter { ($0.projectPath ?? "") == targetProjectHash }
                 Logger.log(level: .debug, "Filtering list by project path '\(projPath)' (hash: \(targetProjectHash)). Found \(filteredSessions.count) matches out of \(sessions.count).")
            } else {
                filteredSessions = sessions
            }

            if json {
                // Use InfoOutput.SessionInfo for a consistent structure if it matches TerminalSessionInfo closely
                // Otherwise, if TerminalSessionInfo is the direct source, use it.
                let codableSessions = filteredSessions.map { InfoOutput.SessionInfo(from: $0) } 
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(codableSessions)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                } else {
                     throw ExitCode(ErrorCodes.generalError) // Error converting JSON data to string
                }
            } else {
                if filteredSessions.isEmpty {
                    print("Terminator: No active sessions found" + (projectPath != nil ? " for project \(projectPath!)" : "") + ".")
                } else {
                    print("Terminator: Found \(filteredSessions.count) session(s)" + (projectPath != nil ? " for project \(projectPath!)" : "") + ":")
                    for (index, sessionInfo) in filteredSessions.enumerated() {
                        print("  \(index + 1). ID: \(sessionInfo.sessionIdentifier), Tag: \(sessionInfo.tag), Project: \(sessionInfo.projectPath ?? "N/A"), TTY: \(sessionInfo.tty ?? "N/A"), Busy: \(sessionInfo.isBusy)")
                    }
                }
            }
            throw ExitCode(ErrorCodes.success)
        } catch let error as TerminalControllerError {
            fputs("Error listing sessions: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.appleScriptError) // Or a more specific error if applicable
        } catch {
            fputs("An unexpected error occurred: \(error.localizedDescription)\n", stderr)
            throw ExitCode(ErrorCodes.generalError)
        }
    }
} 