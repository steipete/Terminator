import ArgumentParser
import Foundation

struct Sessions: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List active Terminator sessions."
    )

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Adjusted for external reference

    @Option(name: .long, help: "Filter sessions by project path.")
    var projectPath: String?

    @Option(name: .long, help: "Filter sessions by tag.")
    var tag: String?

    @Flag(name: .long, help: "Output in JSON format.")
    var json: Bool = false

    mutating func run() throws {
        let config = setupConfig()
        logCommand()

        let sessions = try fetchSessions(config: config)
        let filteredSessions = filterSessionsByProject(sessions)

        outputResults(filteredSessions)
        throw ExitCode(ErrorCodes.success)
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
            defaultFocusOption: nil,
            sigintWaitOption: nil,
            sigtermWaitOption: nil,
            defaultFocusOnKillOption: nil,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: nil,
            iTermProfileNameOption: nil
        )
        return TerminatorCLI.currentConfig!
    }

    private func logCommand() {
        Logger.log(
            level: .info,
            "Executing 'sessions' command."
                + (projectPath != nil ? " Filtering by project: \(projectPath!)" : "")
                + (tag != nil ? " Filtering by tag: \(tag!)" : "")
        )
    }

    private func fetchSessions(config: AppConfig) throws -> [TerminalSessionInfo] {
        do {
            switch config.terminalAppEnum {
            case .appleTerminal:
                let controller = AppleTerminalControl(config: config, appName: config.terminalApp)
                return try controller.listSessions(filterByTag: tag)
            case .iterm:
                let controller = ITermControl(config: config, appName: config.terminalApp)
                return try controller.listSessions(filterByTag: tag)
            case .ghosty:
                let controller = GhostyControl(config: config, appName: config.terminalApp)
                return try controller.listSessions(filterByTag: tag)
            case .unknown:
                throw ExitCode(ErrorCodes.configurationError)
            }
        } catch {
            handleListingError(error)
            throw ExitCode(ErrorCodes.success)
        }
    }

    private func handleListingError(_ error: Error) {
        if json {
            print("[]")
        } else {
            print("No active sessions found.")
            fputs("Warning: Failed to list active sessions: \(error.localizedDescription)\n", stderr)
        }
    }

    private func filterSessionsByProject(_ sessions: [TerminalSessionInfo]) -> [TerminalSessionInfo] {
        guard let projPath = projectPath else { return sessions }

        let targetProjectHash = SessionUtilities.generateProjectHash(projectPath: projPath)
        let filtered = sessions.filter { ($0.projectPath ?? "") == targetProjectHash }

        Logger.log(
            level: .debug,
            "Post-filtering list by project path '\(projPath)' (hash: \(targetProjectHash)). Found \(filtered.count) matches out of \(sessions.count) total (after tag filter)."
        )

        return filtered
    }

    private func outputResults(_ sessions: [TerminalSessionInfo]) {
        if sessions.isEmpty {
            outputEmpty()
        } else if json {
            outputJSON(sessions)
        } else {
            outputText(sessions)
        }
    }

    private func outputEmpty() {
        if json {
            print("[]")
        } else {
            print("No active sessions found"
                + (projectPath != nil ? " for project \(projectPath!)" : "")
                + (tag != nil ? " with tag \(tag!)" : "")
                + "."
            )
        }
    }

    private func outputJSON(_ sessions: [TerminalSessionInfo]) {
        let codableSessions = sessions.map { InfoOutput.SessionInfo(from: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(codableSessions)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                print("[]")
            }
        } catch {
            print("[]")
        }
    }

    private func outputText(_ sessions: [TerminalSessionInfo]) {
        print("Terminator: Found \(sessions.count) session(s)"
            + (projectPath != nil ? " for project \(projectPath!)" : "")
            + (tag != nil ? " with tag \(tag!)" : "")
            + ":"
        )

        for (index, sessionInfo) in sessions.enumerated() {
            print(
                "  \(index + 1). ID: \(sessionInfo.sessionIdentifier), Tag: \(sessionInfo.tag), Project: \(sessionInfo.projectPath ?? "N/A"), TTY: \(sessionInfo.tty ?? "N/A"), Busy: \(sessionInfo.isBusy)"
            )
        }
    }
}
