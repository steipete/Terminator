import ArgumentParser
import Foundation

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Display TerminatorCLI version, configuration, and active sessions.")

    @OptionGroup var globals: TerminatorCLI.GlobalOptions // Adjusted to refer to TerminatorCLI.GlobalOptions

    @Flag(name: .long, help: "Output in JSON format.")
    var json: Bool = false

    mutating func run() throws {
        // Ensure config is loaded based on global options for Info command too
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil, // Not relevant for Info
            backgroundStartupOption: nil, // Not relevant for Info
            foregroundCompletionOption: nil, // Not relevant for Info
            defaultFocusOption: nil, // Not relevant for Info
            sigintWaitOption: nil, // Global
            sigtermWaitOption: nil, // Global
            defaultFocusOnKillOption: nil,
            preKillScriptPathOption: nil,
            reuseBusySessionsOption: nil,
            iTermProfileNameOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'info' command. JSON output: \(json)")

        // Check for unknown terminal app at the beginning
        if config.terminalAppEnum == .unknown {
            if json {
                // Simplify the JSON output with a manually constructed JSON string
                print("{\"version\": \"\(appVersion)\", \"error\": \"Unknown terminal application: \(config.terminalApp)\", \"activeConfiguration\": { \"TERMINATOR_APP\": \"\(config.terminalApp)\" } }")
                throw ExitCode(ErrorCodes.configurationError)
            } else {
                fputs("Error: Unknown terminal application: \(config.terminalApp)\n", stderr)
                throw ExitCode(ErrorCodes.configurationError)
            }
        }

        var sessions: [TerminalSessionInfo] = []

        switch config.terminalAppEnum {
        case .appleTerminal:
            let appleTerminalController = AppleTerminalControl(config: config, appName: config.terminalApp)
            do {
                sessions = try appleTerminalController.listSessions(filterByTag: nil)
            } catch let error as TerminalControllerError {
                if !json {
                    fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
                }
                // Continue to show version and config
            } catch {
                if !json {
                    fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
                }
            }

        case .iterm:
            let iTermController = ITermControl(config: config, appName: config.terminalApp)
            do {
                sessions = try iTermController.listSessions(filterByTag: nil)
            } catch let error as TerminalControllerError {
                if !json {
                    fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
                }
                // Continue to show version and config
            } catch {
                if !json {
                    fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
                }
            }

        case .ghosty:
            // GhostyControl is not yet implemented, so this is stubbed
            if !json {
                fputs("Warning: Ghosty terminal is not yet fully supported for listing sessions.\n", stderr)
            }
            // When GhostyControl is available:
            // let ghostyController = GhostyControl(config: config, appName: config.terminalApp)
            // do {
            //     sessions = try ghostyController.listSessions(filterByTag: nil)
            // } catch let error as TerminalControllerError {
            //     if !json {
            //         fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
            //     }
            // } catch {
            //     if !json {
            //         fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
            //     }
            // }

        case .unknown:
            // This should not be reached if the earlier check is working correctly
            throw ExitCode(ErrorCodes.internalError)
        }

        let codableSessions = sessions.map { InfoOutput.SessionInfo(from: $0).asDictionary }

        let infoOutput = InfoOutput(
            version: TerminatorCLI.configuration.version,
            managedSessions: codableSessions.map { $0.mapValues { AnyCodable($0) } }, // Ensure AnyCodable handles Any? from asDictionary
            activeConfiguration: config.asDictionary.mapValues { AnyCodable($0) }
        )

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                let jsonData = try encoder.encode(infoOutput)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print(jsonString)
                } else {
                    // Use ErrorCodes.generalError for throwing ExitCode
                    throw ExitCode(ErrorCodes.generalError)
                }
            } catch {
                let specificEncodingError = error // Capture the specific encoding error
                fputs("Error: Failed to generate JSON for info: \(specificEncodingError.localizedDescription)\nSpecific Encoding Error: \(specificEncodingError)\n", stderr)
                print("{\"version\": \"\(TerminatorCLI.configuration.version)\", \"error\": \"Failed to retrieve full info, check logs.\"}")
                throw ExitCode(ErrorCodes.generalError)
            }
        } else {
            print("Terminator CLI Version: \(TerminatorCLI.configuration.version)")
            print("--- Active Configuration ---")
            // Use .sorted to ensure consistent output order for testing/readability
            for (key, value) in config.asDictionary.sorted(by: { $0.key < $1.key }) {
                let displayValue: String
                if let anyCodableValue = value as? AnyCodable {
                    // This path might not be hit if asDictionary returns [String: Any]
                    // and AnyCodable is applied later. For now, assume direct display or basic types.
                    // A more robust way to pretty print AnyCodable might be needed if it wraps complex types here.
                    displayValue = "\(anyCodableValue)" // May need custom description for AnyCodable
                } else {
                    displayValue = "\(value)"
                }
                print("  \(key): \(displayValue == "NSNull()" ? "nil" : displayValue)")
            }
            print("--- Managed Sessions ---")
            if sessions.isEmpty {
                print("  No active sessions found.")
            } else {
                for sessionInfo in sessions {
                    print("  ID: \(sessionInfo.sessionIdentifier), Tag: \(sessionInfo.tag), Project: \(sessionInfo.projectPath ?? "N/A"), TTY: \(sessionInfo.tty ?? "N/A"), Busy: \(sessionInfo.isBusy)")
                }
            }
        }
    }
}
