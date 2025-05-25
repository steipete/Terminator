import ArgumentParser
import Foundation

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List active Terminator sessions.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Adjusted for external reference

    @Option(name: .long, help: "Filter sessions by project path.")
    var projectPath: String?

    @Option(name: .long, help: "Filter sessions by tag.")
    var tag: String?

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
            sigtermWaitOption: nil,
            defaultFocusOnKillOption: nil,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: nil,
            iTermProfileNameOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'list' command."
            + (projectPath != nil ? " Filtering by project: \(projectPath!)" : "")
            + (tag != nil ? " Filtering by tag: \(tag!)" : ""))

        let sessions: [TerminalSessionInfo]

        // Wrap session listing in do-catch to handle errors gracefully
        do {
            switch config.terminalAppEnum {
            case .appleTerminal:
                let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: tag)
            case .iterm:
                let controller = ITermControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: tag)
            case .ghosty:
                let controller = GhostyControl(config: config, appName: config.terminalApp)
                sessions = try controller.listSessions(filterByTag: tag)
            case .unknown:
                throw ExitCode(ErrorCodes.configurationError)
            }
        } catch {
            // Handle listing errors gracefully
            if json {
                // In JSON mode: print empty array, no stderr warnings
                print("[]")
            } else {
                // In default mode: print user-friendly message and warning to stderr
                print("No active sessions found.")
                fputs("Warning: Failed to list active sessions: \(error.localizedDescription)\n", stderr)
            }
            // Exit successfully as per requirements
            throw ExitCode(ErrorCodes.success)
        }

        // Filter sessions if needed
        let filteredSessions: [TerminalSessionInfo]
        if let projPath = projectPath {
            let targetProjectHash = SessionUtilities.generateProjectHash(projectPath: projPath)
            filteredSessions = sessions.filter { ($0.projectPath ?? "") == targetProjectHash }
            Logger.log(level: .debug, "Post-filtering list by project path '\(projPath)' (hash: \(targetProjectHash)). Found \(filteredSessions.count) matches out of \(sessions.count) total (after tag filter).")
        } else {
            filteredSessions = sessions
        }

        // Handle output based on format and whether sessions exist
        if filteredSessions.isEmpty {
            if json {
                print("[]")
            } else {
                print("No active sessions found"
                    + (projectPath != nil ? " for project \(projectPath!)" : "")
                    + (tag != nil ? " with tag \(tag!)" : "")
                    + ".")
            }
        } else {
            if json {
                let codableSessions = filteredSessions.map { InfoOutput.SessionInfo(from: $0) }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                do {
                    let jsonData = try encoder.encode(codableSessions)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        print(jsonString)
                    } else {
                        // If JSON encoding fails, print empty array
                        print("[]")
                    }
                } catch {
                    // If JSON encoding fails, print empty array
                    print("[]")
                }
            } else {
                print("Terminator: Found \(filteredSessions.count) session(s)"
                    + (projectPath != nil ? " for project \(projectPath!)" : "")
                    + (tag != nil ? " with tag \(tag!)" : "")
                    + ":")
                for (index, sessionInfo) in filteredSessions.enumerated() {
                    print("  \(index + 1). ID: \(sessionInfo.sessionIdentifier), Tag: \(sessionInfo.tag), Project: \(sessionInfo.projectPath ?? "N/A"), TTY: \(sessionInfo.tty ?? "N/A"), Busy: \(sessionInfo.isBusy)")
                }
            }
        }

        // Always exit with success
        throw ExitCode(ErrorCodes.success)
    }
}
