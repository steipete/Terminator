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
            defaultLinesOption: nil, 
            backgroundStartupOption: nil, 
            foregroundCompletionOption: nil,
            defaultFocusOption: nil, 
            sigintWaitOption: nil, 
            sigtermWaitOption: nil
        )
        let config = TerminatorCLI.currentConfig!
        Logger.log(level: .info, "Executing 'info' command. JSON output: \(json)")

        var sessions: [TerminalSessionInfo] = []
        
        switch config.terminalAppEnum {
        case .appleTerminal:
            let appleTerminalController = AppleTerminalControl(config: config, appName: config.terminalApp)
            do {
                sessions = try appleTerminalController.listSessions(filterByTag: nil)
            } catch let error as TerminalControllerError {
                fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
                // Continue to show version and config
            } catch {
                fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
            }
            
        case .iterm:
            let iTermController = ITermControl(config: config, appName: config.terminalApp)
            do {
                sessions = try iTermController.listSessions(filterByTag: nil)
            } catch let error as TerminalControllerError {
                fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
                // Continue to show version and config
            } catch {
                fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
            }
            
        case .ghosty:
            // GhostyControl is not yet implemented, so this is stubbed
            fputs("Warning: Ghosty terminal is not yet fully supported for listing sessions.\n", stderr)
            // When GhostyControl is available:
            // let ghostyController = GhostyControl(config: config, appName: config.terminalApp)
            // do {
            //     sessions = try ghostyController.listSessions(filterByTag: nil)
            // } catch let error as TerminalControllerError {
            //     fputs("Warning: Failed to list active sessions for info command. Error: \(error.localizedDescription)\n", stderr)
            // } catch {
            //     fputs("Warning: An unexpected error occurred while listing sessions: \(error.localizedDescription)\n", stderr)
            // }
            
        case .unknown:
            Logger.log(level: .error, "Unknown terminal application: \(config.terminalApp)")
            throw ExitCode(ErrorCodes.configurationError)
        }

        let codableSessions = sessions.map { InfoOutput.SessionInfo(from: $0).asDictionary }

        let infoOutput = InfoOutput(
            version: APP_VERSION,
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
                fputs("Error: Failed to generate JSON for info: \(error.localizedDescription)\n", stderr)
                print("{\"version\": \"\(APP_VERSION)\", \"error\": \"Failed to retrieve full info, check logs.\"}")
                throw ExitCode(ErrorCodes.generalError)
            }
        } else {
            print("Terminator CLI Version: \(APP_VERSION)")
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
         throw ExitCode(ErrorCodes.success) // Explicitly throw success for clean exit
    }
} 