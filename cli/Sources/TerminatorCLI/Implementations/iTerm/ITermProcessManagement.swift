import Foundation

// MARK: - Process Management Extension for ITermControl

extension ITermControl {
    // MARK: - Kill Process in Session

    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(
            level: .info,
            "[ITermControl] Killing process in session for tag: \(params.tag), project: \(params.projectPath ?? "nil")",
            file: #file,
            function: #function
        )

        let sessionInfo = try findSession(params: params)

        guard let tty = sessionInfo.tty, !tty.isEmpty else {
            Logger.log(
                level: .warn,
                "iTerm session \(params.tag) found but has no TTY. Cannot kill process.",
                file: #file,
                function: #function
            )
            return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: "Session has no TTY.")
        }

        var killSuccess = false
        var message = "Kill attempt for iTerm session \(params.tag) (TTY: \(tty))."

        // 1. Handle pre-kill script
        message += handlePreKillScript()

        // 2. Find and kill process
        let killResult = try findAndKillProcess(sessionInfo: sessionInfo, params: params, tty: tty)
        killSuccess = killResult.success
        message += killResult.message

        // 3. Clear screen after kill attempts
        clearSessionScreenIfPossible(sessionInfo: sessionInfo, tag: params.tag)

        return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: killSuccess, message: message)
    }

    private func findSession(params: KillSessionParams) throws -> TerminalSessionInfo {
        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities
            .generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions
            .first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        return sessionInfo
    }

    private func handlePreKillScript() -> String {
        guard let preKillScriptPath = config.preKillScriptPath, !preKillScriptPath.isEmpty else {
            return ""
        }

        Logger.log(
            level: .info,
            "[ITermControl] Pre-kill script configured but not implemented: \(preKillScriptPath)",
            file: #file,
            function: #function
        )
        return " Pre-kill script configured but not executed (not implemented)."
    }

    private func findAndKillProcess(
        sessionInfo: TerminalSessionInfo,
        params: KillSessionParams,
        tty: String
    ) throws -> (success: Bool, message: String) {
        var message = ""
        var killSuccess = false

        // Find PGID
        let pgidResult = findPGID(tty: tty, tag: params.tag)
        message += pgidResult.message

        if pgidResult.shouldReturnEarly && config.preKillScriptPath == nil {
            // Fall through to Ctrl+C logic
        } else if pgidResult.shouldReturnEarly {
            return (true, message + " (No process found via ps)")
        }

        if pgidResult.error != nil && config.preKillScriptPath != nil {
            return (false, message)
        }

        // Try graceful kill if PGID found
        if let pgid = pgidResult.pgid, pgid > 0 {
            let gracefulResult = attemptGracefulKill(pgid: pgid, tag: params.tag)
            killSuccess = gracefulResult.success
            message += gracefulResult.message

            if killSuccess {
                return (true, message)
            }
        }

        // Ctrl+C fallback
        if config.preKillScriptPath == nil && (pgidResult.pgid == nil || !killSuccess) {
            let ctrlCResult = attemptCtrlCFallback(sessionInfo: sessionInfo, params: params)
            killSuccess = ctrlCResult.success
            message += ctrlCResult.message
        }

        return (killSuccess, message)
    }

    private struct PGIDResult {
        let pgid: pid_t?
        let message: String
        let shouldReturnEarly: Bool
        let error: Error?
    }

    private func findPGID(tty: String, tag: String) -> PGIDResult {
        let ttyNameOnly = (tty as NSString).lastPathComponent
        Logger.log(
            level: .debug,
            "[ITermControl] Attempting to find PGID for TTY \(ttyNameOnly) using ProcessUtilities.",
            file: #file,
            function: #function
        )

        if let processDetails = ProcessUtilities.getForegroundProcessInfo(forTTY: ttyNameOnly) {
            let pgid = processDetails.pgid
            let message = " Found PGID \(pgid) for iTerm session \(tag) (TTY: \(ttyNameOnly)) using ProcessUtilities."
            Logger.log(level: .info, "[ITermControl]\(message)", file: #file, function: #function)
            return PGIDResult(
                pgid: pgid,
                message: message,
                shouldReturnEarly: false,
                error: nil
            )
        } else {
            let message = " Could not find PGID for TTY \(ttyNameOnly) using ProcessUtilities for iTerm session \(tag)."
            Logger.log(level: .warn, "[ITermControl]\(message)", file: #file, function: #function)
            // shouldReturnEarly: true if no PGID means we should proceed to Ctrl+C or skip further kill attempts.
            // This depends on the calling logic in findAndKillProcess.
            // If preKillScriptPath is nil, findAndKillProcess will try Ctrl+C if pgid is nil.
            // So, shouldReturnEarly: true seems appropriate here if no PGID is found by ps.
            return PGIDResult(
                pgid: nil,
                message: message,
                shouldReturnEarly: true,
                error: nil // Not an AppleScript error, but a failure to find PGID via ps.
            )
        }
    }

    private func attemptGracefulKill(pgid: pid_t, tag: String) -> (success: Bool, message: String) {
        var message = ""
        let killSuccess = ProcessUtilities.attemptGracefulKill(pgid: pgid, config: config, message: &message)

        if killSuccess {
            Logger.log(
                level: .info,
                "[ITermControl] Graceful kill successful for PGID \(pgid) in iTerm session \(tag).",
                file: #file,
                function: #function
            )
        } else {
            message += " Graceful kill attempt for PGID \(pgid) failed or process persisted."
            Logger.log(
                level: .warn,
                "[ITermControl] Graceful kill failed or process persisted for PGID \(pgid) in iTerm session \(tag).",
                file: #file,
                function: #function
            )
        }

        return (killSuccess, message)
    }

    private func attemptCtrlCFallback(
        sessionInfo: TerminalSessionInfo,
        params: KillSessionParams
    ) -> (success: Bool, message: String) {
        var message = ""
        var killSuccess = false

        Logger.log(
            level: .info,
            "[ITermControl] PGID not found or graceful kill failed for iTerm session \(params.tag). Attempting Ctrl+C fallback.",
            file: #file,
            function: #function
        )

        guard sessionInfo.windowIdentifier != nil,
              let compositeTabID = sessionInfo.tabIdentifier,
              let sessionID = Self.extractSessionID(from: compositeTabID)
        else {
            message += " Cannot attempt Ctrl+C: session missing window/sessionID identifiers."
            return (false, message)
        }

        let ctrlCScript = ITermScripts.sendControlCScript(
            appName: appName,
            sessionID: sessionID,
            shouldActivateITerm: attentesFocus(
                focusPreference: params.focusPreference,
                defaultFocusSetting: false
            )
        )

        let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)

        switch ctrlCResult {
        case let .success(result):
            (killSuccess, message) = handleCtrlCResult(result, tag: params.tag)
        case let .failure(error):
            message += " Failed to send Ctrl+C to iTerm session: \(error.localizedDescription)."
            Logger.log(
                level: .warn,
                "[ITermControl] Error sending Ctrl+C to iTerm session \(params.tag): \(error.localizedDescription).",
                file: #file,
                function: #function
            )
            killSuccess = false
        }

        return (killSuccess, message)
    }

    private func handleCtrlCResult(_ result: Any, tag: String) -> (success: Bool, message: String) {
        guard let strResult = result as? String else {
            let message = " Failed to send Ctrl+C to iTerm session. Unexpected result type: \(type(of: result))."
            Logger.log(
                level: .warn,
                "[ITermControl] Failed to send Ctrl+C to iTerm session \(tag). Non-string result.",
                file: #file,
                function: #function
            )
            return (false, message)
        }

        if strResult == "OK_CTRL_C_SENT" {
            Logger.log(
                level: .info,
                "[ITermControl] Successfully sent Ctrl+C to iTerm session \(tag).",
                file: #file,
                function: #function
            )
            return (true, " Sent Ctrl+C to iTerm session as fallback.")
        } else {
            let message = " Failed to send Ctrl+C to iTerm session. AppleScript result: \(strResult)."
            Logger.log(
                level: .warn,
                "[ITermControl] Failed to send Ctrl+C to iTerm session \(tag). Result: \(strResult).",
                file: #file,
                function: #function
            )
            return (false, message)
        }
    }

    private func clearSessionScreenIfPossible(sessionInfo: TerminalSessionInfo, tag: String) {
        if let compositeTabID = sessionInfo.tabIdentifier,
           let sessionID = Self.extractSessionID(from: compositeTabID) {
            Self.clearSessionScreen(appName: appName, sessionID: sessionID, tag: tag)
        }
    }

    // MARK: - Helper Methods for Process Management

    func parsePgidFromResult(
        resultStringOrArray: Any,
        tty: String,
        tag: String
    ) -> (pgid: pid_t?, message: String, shouldReturnEarly: Bool) {
        var message = ""
        var pgidToKill: pid_t?
        var shouldReturnEarly = false

        if let resultString = resultStringOrArray as? String,
           !resultString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = resultString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if let pgidStr = parts.first, let foundPgid = pid_t(pgidStr) {
                pgidToKill = foundPgid
                message += " Identified foreground process group ID: \(foundPgid)."
                Logger.log(
                    level: .info,
                    "Identified PGID \(foundPgid) on TTY \(tty) for iTerm session \(tag).",
                    file: #file,
                    function: #function
                )
            } else {
                message += " Could not parse PGID from ps output: '\(resultString)'."
                Logger.log(
                    level: .warn,
                    "Could not parse PGID from output: '\(resultString)' for iTerm TTY \(tty).",
                    file: #file,
                    function: #function
                )
            }
        } else {
            message += " No foreground process found on TTY \(tty) in iTerm session to kill."
            Logger.log(
                level: .info,
                "No foreground process found on TTY \(tty) for iTerm session \(tag). Assuming success.",
                file: #file,
                function: #function
            )
            shouldReturnEarly = true // Indicate that we should return early from the calling function
        }
        return (pgidToKill, message, shouldReturnEarly)
    }
}
