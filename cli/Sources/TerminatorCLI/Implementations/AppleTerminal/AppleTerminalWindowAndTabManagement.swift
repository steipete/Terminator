import Foundation

extension AppleTerminalControl {
    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .info, "[AppleTerminalControl] Listing sessions, filter: \(filterByTag ?? "none")")

        let script = AppleTerminalScripts.listSessionsScript(appName: appName)
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            // resultData is Any from AppleScript result - pass it directly to parser
            // Logger.log(level: .debug, "AppleScript result for Terminal.app listing: \(resultData)") // Can be very verbose
            return try AppleTerminalParser.parseSessionListOutput(
                resultStringOrArray: resultData,
                scriptContent: script,
                filterByTag: filterByTag
            )

        case let .failure(error):
            Logger.log(level: .error, "Failed to list sessions for Terminal.app: \(error.localizedDescription)")
            throw TerminalControllerError.appleScriptError(
                message: "Listing sessions failed: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Reading output for tag: \(params.tag)"
        )

        // Find the session
        let sessions = try listSessions(filterByTag: params.tag)
        guard let session = sessions.first else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = session.tabIdentifier,
              let windowID = session.windowIdentifier
        else {
            throw TerminalControllerError.internalError(
                details: "Session \(session.sessionIdentifier) is missing required identifiers"
            )
        }

        // Get the full terminal history
        let script = AppleTerminalScripts.getTabHistoryScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID
        )

        let scriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch scriptResult {
        case let .success(result):
            // The script returns the full history as a string
            guard let fullHistory = result as? String else {
                throw TerminalControllerError.appleScriptError(
                    message: "Get history script returned non-string: \(result)",
                    scriptContent: script,
                    underlyingError: nil
                )
            }

            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Retrieved \(fullHistory.count) characters of history"
            )

            let outputToReturn = fullHistory

            // TODO: Implement file logging
            // Log the read action if file logging is enabled
            // if config.logToFile {
            //     let logManager = FileLogManager(sessionInfo: session, config: config)
            //     if logManager.shouldLogToFile {
            //         do {
            //             try logManager.logEntry(
            //                 type: .output,
            //                 content: outputToReturn,
            //                 metadata: [
            //                     "tag": params.tag,
            //                     "windowID": windowID,
            //                     "tabID": tabID
            //                 ]
            //             )
            //         } catch {
            //             Logger.log(
            //                 level: .error,
            //                 "[AppleTerminalControl] Failed to log output: \(error.localizedDescription)"
            //             )
            //         }
            //     }
            // }

            return ReadSessionResult(
                sessionInfo: session,
                output: outputToReturn
            )

        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to read session output: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Focusing session for tag: \(params.tag)"
        )

        // Find the session
        let sessions = try listSessions(filterByTag: params.tag)
        guard let session = sessions.first else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = session.tabIdentifier,
              let windowID = session.windowIdentifier
        else {
            throw TerminalControllerError.internalError(
                details: "Session \(session.sessionIdentifier) is missing required identifiers"
            )
        }

        // Focus the window and tab
        let script = AppleTerminalScripts.focusSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID
        )

        let scriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch scriptResult {
        case .success:
            Logger.log(
                level: .info,
                "[AppleTerminalControl] Successfully focused session for tag '\(params.tag)'"
            )

            return FocusSessionResult(
                focusedSessionInfo: session
            )

        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to focus session: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }
}
