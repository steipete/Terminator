import ArgumentParser
import Foundation

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "info",
        abstract: "Display information about the terminator and its configuration."
    )

    @OptionGroup var globals: TerminatorCLI.GlobalOptions

    @Flag(name: .long, help: "Output in JSON format.")
    var json: Bool = false

    mutating func run() throws {
        let config = try setupConfiguration()

        try validateTerminalApp(config: config)

        let sessions = fetchSessions(config: config)

        if json {
            try outputJSON(config: config, sessions: sessions)
        } else {
            outputText(config: config, sessions: sessions)
        }
    }

    // MARK: - Private Helper Methods

    private func setupConfiguration() throws -> AppConfig {
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
        Logger.log(level: .info, "Executing 'info' command. JSON output: \(json)")
        return config
    }

    private func validateTerminalApp(config: AppConfig) throws {
        if config.terminalAppEnum == .unknown {
            if json {
                print(
                    "{\"version\": \"\(TerminatorCLI.configuration.version)\", \"error\": \"Unknown terminal application: \(config.terminalApp)\", \"activeConfiguration\": { \"TERMINATOR_APP\": \"\(config.terminalApp)\" } }"
                )
                throw ExitCode(ErrorCodes.configurationError)
            } else {
                fputs("Error: Unknown terminal application: \(config.terminalApp)\n", stderr)
                throw ExitCode(ErrorCodes.configurationError)
            }
        }
    }

    private func fetchSessions(config: AppConfig) -> [TerminalSessionInfo] {
        var sessions: [TerminalSessionInfo] = []

        switch config.terminalAppEnum {
        case .appleTerminal:
            sessions = fetchSessionsFromTerminal(
                controllerType: AppleTerminalControl.self,
                config: config,
                appName: config.terminalApp
            )

        case .iterm:
            sessions = fetchSessionsFromTerminal(
                controllerType: ITermControl.self,
                config: config,
                appName: config.terminalApp
            )

        case .ghosty:
            if !json {
                fputs("Warning: Ghosty terminal is not yet fully supported for listing sessions.\n", stderr)
            }

        case .unknown:
            // Should not reach here due to earlier validation
            break
        }

        return sessions
    }

    private func fetchSessionsFromTerminal<T: TerminalControlling>(
        controllerType _: T.Type,
        config: AppConfig,
        appName: String
    ) -> [TerminalSessionInfo] {
        let controller = T(config: config, appName: appName)

        do {
            return try controller.listSessions(filterByTag: nil)
        } catch let error as TerminalControllerError {
            if !json {
                fputs(
                    "Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n",
                    stderr
                )
            }
        } catch {
            if !json {
                fputs(
                    "Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n",
                    stderr
                )
            }
        }

        return []
    }

    private func outputJSON(config: AppConfig, sessions: [TerminalSessionInfo]) throws {
        let codableSessions = sessions.map { InfoOutput.SessionInfo(from: $0).asDictionary }

        let infoOutput = InfoOutput(
            version: TerminatorCLI.configuration.version,
            managedSessions: codableSessions.map { $0.mapValues { AnyCodable($0) } },
            activeConfiguration: config.asDictionary.mapValues { AnyCodable($0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let jsonData = try encoder.encode(infoOutput)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                throw ExitCode(ErrorCodes.generalError)
            }
        } catch {
            fputs(
                "Error: Failed to generate JSON for info: \(error.localizedDescription)\n",
                stderr
            )
            print(
                "{\"version\": \"\(TerminatorCLI.configuration.version)\", \"error\": \"Failed to retrieve full info, check logs.\"}"
            )
            throw ExitCode(ErrorCodes.generalError)
        }
    }

    private func outputText(config: AppConfig, sessions: [TerminalSessionInfo]) {
        print("Terminator CLI Version: \(TerminatorCLI.configuration.version)")
        print("--- Active Configuration ---")

        for (key, value) in config.asDictionary.sorted(by: { $0.key < $1.key }) {
            let displayValue = formatConfigValue(value)
            print("  \(key): \(displayValue)")
        }

        print("--- Managed Sessions ---")
        if sessions.isEmpty {
            print("  No active sessions found.")
        } else {
            for sessionInfo in sessions {
                printSessionInfo(sessionInfo)
            }
        }
    }

    private func formatConfigValue(_ value: Any) -> String {
        let displayValue = if let anyCodableValue = value as? AnyCodable {
            "\(anyCodableValue)"
        } else {
            "\(value)"
        }
        return displayValue == "NSNull()" ? "nil" : displayValue
    }

    private func printSessionInfo(_ sessionInfo: TerminalSessionInfo) {
        print(
            "  Session ID: \(sessionInfo.sessionIdentifier), Tag: \(sessionInfo.tag), TTY: \(sessionInfo.tty ?? "N/A"), Busy: \(sessionInfo.isBusy)"
        )
        print("    Full Tab Title: \(sessionInfo.fullTabTitle ?? "N/A")")
        if let projectPath = sessionInfo.projectPath {
            print("    Project Path: \(projectPath)")
        }
    }
}
