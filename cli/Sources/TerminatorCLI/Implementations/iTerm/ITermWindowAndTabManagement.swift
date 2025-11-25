import Foundation

// MARK: - Window and Tab Management Extension for ITermControl

extension ITermControl {
    // MARK: - Helper functions for session identifiers

    static func extractSessionID(from compositeIdentifier: String?) -> String? {
        guard let composite = compositeIdentifier else { return nil }
        let parts = composite.split(separator: ":").map(String.init)
        return parts.count >= 2 ? parts[1] : nil
    }

    static func extractTabID(from compositeIdentifier: String?) -> String? {
        guard let composite = compositeIdentifier else { return nil }
        let parts = composite.split(separator: ":").map(String.init)
        return parts.count >= 1 ? parts[0] : nil
    }

    // MARK: - List Sessions

    func listSessionsViaAppleScript(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(
            level: .info,
            "[ITermControl] Listing sessions, filter: \(filterByTag ?? "nil")",
            file: #file,
            function: #function
        )

        let script = ITermScripts.listSessionsScript(appName: appName)
        Logger.log(level: .debug, "[ITermControl] Generated AppleScript for listSessions")

        Logger.log(level: .debug, "[ITermControl] About to run AppleScript")
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)
        Logger.log(level: .debug, "[ITermControl] AppleScript execution completed")

        switch appleScriptResult {
        case let .success(resultStringOrArray):
            Logger.log(
                level: .debug,
                "AppleScript result for iTerm listing: \(resultStringOrArray)",
                file: #file,
                function: #function
            )
            return try ITermParser.parseListSessionsOutput(
                resultData: resultStringOrArray,
                scriptContent: script,
                filterByTag: filterByTag
            )

        case let .failure(error):
            Logger.log(
                level: .error,
                "Failed to list sessions for iTerm: \(error.localizedDescription)",
                file: #file,
                function: #function
            )
            throw TerminalControllerError.appleScriptError(
                message: "Listing iTerm sessions failed: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    // MARK: - Read Session Output
    // Note: readSessionOutputViaAppleScript is implemented in the main ITermControl class

    // MARK: - Focus Session

    func focusSessionViaAppleScript(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(
            level: .info,
            "[ITermControl] Focusing session for tag: \(params.tag), project: \(params.projectPath ?? "nil")",
            file: #file,
            function: #function
        )

        let existingSessions = try listSessionsViaAppleScript(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities
            .generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions
            .first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let tabID = Self.extractTabID(from: compositeTabID),
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let windowID = sessionInfo.windowIdentifier
        else {
            throw TerminalControllerError
                .internalError(
                    details: "iTerm session found for focus is missing tabID, sessionID or windowID. Session: \(sessionInfo)"
                )
        }

        let script = ITermScripts.focusSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            sessionID: sessionID
        )
        // Logger.log(level: .debug, "AppleScript for focusSession (iTerm):\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success:
            Logger.log(
                level: .info,
                "Successfully focused iTerm session for tag: \(params.tag).",
                file: #file,
                function: #function
            )
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case let .failure(error):
            let errorMsg = "Failed to focus iTerm session for tag '\(params.tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(
                message: errorMsg,
                scriptContent: script,
                underlyingError: error
            )
        }
    }
}
