import Foundation

extension AppleTerminalControl {
    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Attempting to kill process in session for tag: \(params.tag)"
        )

        // Find the session
        let sessions = try listSessions(filterByTag: params.tag)
        guard let session = sessions.first else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = session.tabIdentifier,
              let windowID = session.windowIdentifier,
              let tty = session.tty
        else {
            throw TerminalControllerError.internalError(
                details: "Session \(session.sessionIdentifier) is missing required identifiers"
            )
        }

        // Check if the session is busy
        let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty)

        if let processInfo {
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Found foreground process: \(processInfo.command) (PGID: \(processInfo.pgid), PID: \(processInfo.pid))"
            )
        } else {
            Logger.log(
                level: .info,
                "[AppleTerminalControl] No foreground process found on TTY \(tty)"
            )
            return KillSessionResult(
                killedSessionInfo: session,
                killSuccess: true,
                message: "No process to kill"
            )
        }

        var message = ""
        let killSuccess = ProcessUtilities.attemptGracefulKill(
            pgid: processInfo!.pgid,
            config: config,
            message: &message
        )

        // Clear the screen after killing the process
        if killSuccess && shouldFocus(focusPreference: params.focusPreference) {
            AppleTerminalControl.clearSessionScreen(
                appName: appName,
                windowID: windowID,
                tabID: tabID
            )
        }

        return KillSessionResult(
            killedSessionInfo: session,
            killSuccess: killSuccess,
            message: message
        )
    }
}
