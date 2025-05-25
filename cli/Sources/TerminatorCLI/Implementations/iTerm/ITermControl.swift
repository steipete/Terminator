import Foundation

struct ITermControl: TerminalControlling {
    let config: AppConfig
    let appName: String // Should be "iTerm", "iTerm.app", "iTerm2", etc.

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .debug, "ITermControl initialized for app: \(appName)", file: #file, function: #function)
    }

    // Helper function to extract sessionID from composite tabIdentifier
    private static func extractSessionID(from compositeIdentifier: String?) -> String? {
        guard let composite = compositeIdentifier else { return nil }
        let parts = composite.split(separator: ":").map(String.init)
        return parts.count >= 2 ? parts[1] : nil
    }

    // Helper function to extract tabID from composite tabIdentifier
    private static func extractTabID(from compositeIdentifier: String?) -> String? {
        guard let composite = compositeIdentifier else { return nil }
        let parts = composite.split(separator: ":").map(String.init)
        return parts.count >= 1 ? parts[0] : nil
    }

    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .info, "[ITermControl] Listing sessions, filter: \(filterByTag ?? "nil")", file: #file, function: #function)

        let script = ITermScripts.listSessionsScript(appName: appName)
        // Logger.log(level: .debug, "AppleScript for listSessions (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultStringOrArray):
            Logger.log(level: .debug, "AppleScript result for iTerm listing: \\(resultStringOrArray)", file: #file, function: #function)
            return try ITermParser.parseListSessionsOutput(resultData: resultStringOrArray, scriptContent: script, filterByTag: filterByTag)

        case let .failure(error):
            Logger.log(level: .error, "Failed to list sessions for iTerm: \\(error.localizedDescription)", file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: "Listing iTerm sessions failed: \\(error.localizedDescription)", scriptContent: script, underlyingError: error)
        }
    }

    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[ITermControl] Attempting to execute command for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, line: #line, function: #function)

        let sessionToUse = try findOrCreateSessionForITerm(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference // Initial focus applied here
        )

        guard let compositeTabID = sessionToUse.tabIdentifier,
              let _ = Self.extractTabID(from: compositeTabID), // tabID
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let _ = sessionToUse.windowIdentifier, // windowID
              let tty = sessionToUse.tty
        else {
            throw TerminalControllerError.internalError(details: "Found/created iTerm session is missing critical identifiers (tabID, sessionID, windowID, or tty). Session: \\(sessionToUse)")
        }

        // Clear the session screen before any command execution
        Self._clearSessionScreen(appName: appName, sessionID: sessionID, tag: params.tag)

        // SDD 3.2.5: Pre-execution Step: Busy Check & Stop
        if !config.reuseBusySessions { // Only check if not reusing busy sessions
            if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                let foundPgid = processInfo.pgid
                let _ = processInfo.command

                Logger.log(level: .info, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) is busy with command '\\(processInfo.command)' (PGID: \\(foundPgid)). Attempting to interrupt.", file: #file, line: #line, function: #function)

                _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
                Logger.log(level: .debug, "[ITermControl] Sent SIGINT to PGID \\(foundPgid) on TTY \\(tty).", file: #file, function: #function)

                Thread.sleep(forTimeInterval: TimeInterval(config.sigintWaitSeconds)) // Use configured wait

                if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                    Logger.log(level: .error, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) remained busy with command '\\(stillBusyInfo.command)' after interrupt attempt.", file: #file, function: #function)
                    throw TerminalControllerError.busy(tty: tty, processDescription: stillBusyInfo.command)
                } else {
                    Logger.log(level: .info, "[ITermControl] Process on TTY \\(tty) was successfully interrupted.", file: #file, function: #function)
                }
            }
        }
        // End of Busy Check

        // Handle session preparation if command is nil or empty
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(level: .info, "[ITermControl] No command provided. Preparing session (focus/clear) for tag: \\(params.tag)", file: #file, function: #function)
            // Focus is handled by findOrCreate and _clearSessionScreen which might also activate
            return ExecuteCommandResult(
                sessionInfo: sessionToUse,
                output: "",
                exitCode: 0,
                pid: nil,
                wasKilledByTimeout: false
            )
        }

        // Command execution with file-based output logging
        let commandToExecute = params.command!
        let trimmedCommandToExecute = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)

        let _ = (tty as NSString).lastPathComponent
        let _ = Int(Date().timeIntervalSince1970)
        let logFileName = "terminator_output_iterm_\\((tty as NSString).lastPathComponent)_\\(Int(Date().timeIntervalSince1970)).log"
        let logFilePathURL = config.logDir.appendingPathComponent("cli_command_outputs").appendingPathComponent(logFileName)

        do {
            try FileManager.default.createDirectory(at: logFilePathURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.log(level: .error, "[ITermControl] Could not create directory for command output logs: \\(error.localizedDescription)", file: #file, function: #function)
            throw TerminalControllerError.internalError(details: "Failed to create output log directory: \\(error.localizedDescription)")
        }

        let completionMarker = "TERMINATOR_CMD_DONE_\\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground

        // Construct the shell command string in Swift
        let shellCommandToExecuteInTerminal: String
        let quotedLogFilePathForShell = ProcessUtilities.escapePathForShell(logFilePathURL.path)
        let escapedCommandForShell = ProcessUtilities.escapeCommandForShell(trimmedCommandToExecute)

        if isForeground {
            shellCommandToExecuteInTerminal = "((\(escapedCommandForShell)) > \(quotedLogFilePathForShell) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePathForShell))"
        } else {
            // For background, redirect output and run in background, then disown.
            shellCommandToExecuteInTerminal = "((\(escapedCommandForShell)) > \(quotedLogFilePathForShell) 2>&1) & disown"
        }

        // Escape the entire shell command for AppleScript
        let appleScriptSafeShellCommand = shellCommandToExecuteInTerminal
            .replacingOccurrences(of: "\\\\", with: "\\\\\\\\") // Escape backslashes first
            .replacingOccurrences(of: "\"", with: "\\\"") // Then escape quotes

        let shouldActivateITermForCommand = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.simpleExecuteShellCommandInSessionScript(
            appName: appName,
            sessionID: sessionID,
            shellCommandToExecuteEscapedForAppleScript: appleScriptSafeShellCommand,
            shouldActivateITerm: shouldActivateITermForCommand
        )

        Logger.log(level: .debug, "[ITermCtrl] Executing in session ([iTermSessID: \(sessionID), TTY: \(tty)]): \(appleScriptSafeShellCommand). Log: \(logFilePathURL.path). Marker: \(completionMarker)", file: #file, function: #function)

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData): // resultData is now a simple status string
            return try _processExecuteCommandWithFileLogging(
                appleScriptStatusString: resultData, // resultData is already a String from Result<String, AppleScriptError>
                scriptContent: script,
                sessionInfo: sessionToUse,
                params: params,
                commandToExecute: trimmedCommandToExecute, // For logging/timeout messages
                logFilePath: logFilePathURL.path,
                completionMarker: completionMarker
            )
        case let .failure(error):
            let errorMsg = "Failed to execute iTerm command for tag \\(params.tag): \\(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            // Attempt to clean up log file if script submission failed.
            try? FileManager.default.removeItem(atPath: logFilePathURL.path)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    private func _processExecuteCommandWithFileLogging(
        appleScriptStatusString: Any, // Changed from resultData
        scriptContent: String,
        sessionInfo: TerminalSessionInfo,
        params: ExecuteCommandParams,
        commandToExecute trimmedCommandToExecute: String, // Renamed for clarity
        logFilePath: String,
        completionMarker: String
    ) throws -> ExecuteCommandResult {
        // Handle AppleScript errors directly from the status string
        guard let statusString = appleScriptStatusString as? String else {
            Logger.log(level: .error, "[ITermControl] iTerm execute command AppleScript result is not a string: \(type(of: appleScriptStatusString))", file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: "iTerm execute script returned unexpected type", scriptContent: scriptContent)
        }
        
        if !statusString.uppercased().contains("OK") { // e.g. "OK_COMMAND_SUBMITTED" or just "OK"
            Logger.log(level: .error, "[ITermControl] iTerm execute command AppleScript reported error: \\(statusString)", file: #file, function: #function)
            // Attempt to clean up log file if script submission failed.
            try? FileManager.default.removeItem(atPath: logFilePath)
            throw TerminalControllerError.appleScriptError(message: "iTerm execute script error: \\(statusString)", scriptContent: scriptContent)
        }

        var output = ""
        var exitCode: Int? = nil // For foreground, successful completion implies 0 unless timeout
        let pid: pid_t? = nil // PID is not reliably obtained from this script structure. Changed to let.
        var wasKilledByTimeout = false

        let isForeground = params.executionMode == .foreground
        // Use params.timeout for foreground, config.backgroundStartupSeconds for background's initial read
        let timeoutForThisOperation = isForeground ? params.timeout : Int(config.backgroundStartupSeconds)

        if isForeground {
            Logger.log(level: .debug, "[ITermControl] Foreground command. Tailing log file \\(logFilePath) for completion marker with timeout \\(timeoutForThisOperation)s", file: #file, function: #function)

            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: completionMarker,
                timeoutSeconds: timeoutForThisOperation,
                linesToCapture: params.linesToCapture,
                controlIdentifier: "ITermFG-\(params.tag)"
            )

            output = tailResult.output
            wasKilledByTimeout = tailResult.timedOut

            if wasKilledByTimeout {
                Logger.log(level: .warn, "[ITermControl] Command '\\(trimmedCommandToExecute)' for tag \\(params.tag) timed out after \\(timeoutForThisOperation)s waiting for marker.", file: #file, function: #function)
                output = output.replacingOccurrences(of: "\\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "") // Clean if present
                output += "\\n---[ITERM_CMD_TIMEOUT_MARKER_NOT_FOUND]---"

                // Attempt to kill the process group if we have the TTY
                if let tty = sessionInfo.tty {
                    let ttyNameOnly = (tty as NSString).lastPathComponent
                    let pgidFindScript = ITermScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly) // Uses common findPgidScriptForKill
                    let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)

                    if case let .success(pgidData) = pgidFindResult {
                        let parseResult = _parsePgidFromResult(resultStringOrArray: pgidData, tty: tty, tag: params.tag)
                        if let pgidToKill = parseResult.pgid {
                            Logger.log(level: .info, "[ITermControl] Timeout: Attempting to kill process group \\(pgidToKill) for TTY \\(tty)", file: #file, function: #function)
                            var killMessage = ""
                            _ = ProcessUtilities.attemptGracefulKill(pgid: pgidToKill, config: config, message: &killMessage)
                            Logger.log(level: .debug, "[ITermControl] Timeout kill attempt result: \\(killMessage)", file: #file, function: #function)
                        }
                    }
                }
            } else {
                output = output.replacingOccurrences(of: completionMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                exitCode = 0 // Success if marker was found and not timed out
                Logger.log(level: .info, "[ITermControl] Foreground iTerm command '\\(trimmedCommandToExecute)' completed. Log: \\(logFilePath).", file: #file, function: #function)
            }
        } else { // Background
            Logger.log(level: .info, "[ITermControl] Background command '\(params.command ?? "<no command>")' submitted for tag \(params.tag). Capturing initial output from \(logFilePath) with timeout \(timeoutForThisOperation)s.", file: #file, function: #function)

            let initialOutputTail = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: "TERMINATOR_ITERM_BG_NON_EXISTENT_MARKER_\(UUID().uuidString)", // Marker not expected
                timeoutSeconds: timeoutForThisOperation,
                linesToCapture: params.linesToCapture,
                controlIdentifier: "ITermBGInitial-\(params.tag)"
            )
            output = initialOutputTail.output.replacingOccurrences(of: "\\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
            if output.isEmpty {
                output = "Background command submitted. (No initial output captured within \\(timeoutForThisOperation)s or output log is empty)"
            } else {
                output = "Initial output (up to \\(params.linesToCapture) lines):\\n\\(output)"
            }
            exitCode = 0 // Submission itself is a success for background.
            Logger.log(level: .info, "[ITermControl] Background iTerm command submitted. Initial output check complete. Log: \\(logFilePath).", file: #file, function: #function)
        }

        // Clean up log file for successful foreground commands OR if it's a background command (log might grow large).
        // For timed-out foreground commands, keep the log for inspection.
        if (isForeground && !wasKilledByTimeout) || !isForeground {
            if FileManager.default.fileExists(atPath: logFilePath) {
                do {
                    try FileManager.default.removeItem(atPath: logFilePath)
                    Logger.log(level: .debug, "[ITermControl] Removed log file: \\(logFilePath)", file: #file, function: #function)
                } catch {
                    // Log error but don't fail the operation
                    Logger.log(level: .warn, "[ITermControl] Failed to remove log file \\(logFilePath): \\(error.localizedDescription)", file: #file, function: #function)
                }
            }
        }

        let finalSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle, // Title might have been updated by findOrCreate
            tty: sessionInfo.tty,
            isBusy: params.executionMode == .background ? ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty ?? "") : false,
            windowIdentifier: sessionInfo.windowIdentifier,
            tabIdentifier: sessionInfo.tabIdentifier,
            ttyFromTitle: sessionInfo.ttyFromTitle, // Preserve from original findOrCreate if present
            pidFromTitle: sessionInfo.pidFromTitle // Preserve from original findOrCreate if present
        )

        return ExecuteCommandResult(
            sessionInfo: finalSessionInfo,
            output: output.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: exitCode,
            pid: pid, // Still nil, as not reliably fetched.
            wasKilledByTimeout: wasKilledByTimeout
        )
    }

    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .info, "[ITermControl] Reading session output for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let _ = sessionInfo.windowIdentifier
        else {
            throw TerminalControllerError.internalError(details: "iTerm session found for reading is missing sessionID or windowID. Session: \\(sessionInfo)")
        }

        let shouldActivateITermForRead = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.readSessionOutputScript(
            appName: appName,
            sessionID: sessionID,
            linesToRead: params.linesToRead,
            shouldActivateITerm: shouldActivateITermForRead
        )
        // Logger.log(level: .debug, "AppleScript for readSessionOutput (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            let outputString = try ITermParser.parseReadSessionOutput(resultData: resultData, scriptContent: script, linesToRead: params.linesToRead)
            return ReadSessionResult(sessionInfo: sessionInfo, output: outputString)

        case let .failure(error):
            let errorMsg = "Failed to read iTerm session output for tag \(params.tag): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[ITermControl] Focusing session for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let tabID = Self.extractTabID(from: compositeTabID),
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let windowID = sessionInfo.windowIdentifier
        else {
            throw TerminalControllerError.internalError(details: "iTerm session found for focus is missing tabID, sessionID or windowID. Session: \\(sessionInfo)")
        }

        let script = ITermScripts.focusSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            sessionID: sessionID
        )
        // Logger.log(level: .debug, "AppleScript for focusSession (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success:
            Logger.log(level: .info, "Successfully focused iTerm session for tag: \\(params.tag).", file: #file, function: #function)
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case let .failure(error):
            let errorMsg = "Failed to focus iTerm session for tag '\\(params.tag)': \\(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[ITermControl] Killing process in session for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tty = sessionInfo.tty, !tty.isEmpty else {
            Logger.log(level: .warn, "iTerm session \\(params.tag) found but has no TTY. Cannot kill process.", file: #file, function: #function)
            return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: "Session has no TTY.")
        }

        var killSuccess = false
        var message = "Kill attempt for iTerm session \\(params.tag) (TTY: \\(tty))."
        var pgidToKill: pid_t? = nil

        // 1. Attempt to run pre-kill script if configured
        if let preKillScriptPath = config.preKillScriptPath, !preKillScriptPath.isEmpty {
            // ... (existing pre-kill script logic) ...
        }

        // 2. Find PGID using AppleScript (`ps` command)
        let ttyNameOnly = (tty as NSString).lastPathComponent
        let pgidFindScript = ITermScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
        Logger.log(level: .debug, "[ITermControl] Executing PGID find script for iTerm: \\(pgidFindScript)", file: #file, function: #function)

        let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)

        switch pgidFindResult {
        case let .success(resultStringOrArray):
            let parseResult = _parsePgidFromResult(resultStringOrArray: resultStringOrArray, tty: tty, tag: params.tag)
            pgidToKill = parseResult.pgid
            message += parseResult.message
            if parseResult.shouldReturnEarly && config.preKillScriptPath == nil { // If no pgid and no pre-kill script, consider Ctrl+C
                // Fall through to Ctrl+C logic if pgidToKill is still nil
            } else if parseResult.shouldReturnEarly {
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: true, message: message + " (No process found via ps)")
            }

        case let .failure(error):
            message += " Failed to query processes on TTY \(tty) for iTerm session: \(error.localizedDescription)."
            Logger.log(level: .error, "[ITermControl] Failed to run ps to find PGID on TTY \(tty) for iTerm: \(error.localizedDescription)", file: #file, function: #function)
            // Fall through to Ctrl+C logic if no pre-kill script defined
            if config.preKillScriptPath != nil {
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: message)
            }
        }

        // 3. Attempt graceful kill if PGID was found
        if let currentPgid = pgidToKill, currentPgid > 0 {
            killSuccess = ProcessUtilities.attemptGracefulKill(pgid: currentPgid, config: config, message: &message)
            if killSuccess {
                Logger.log(level: .info, "[ITermControl] Graceful kill successful for PGID \\(currentPgid) in iTerm session \\(params.tag).", file: #file, function: #function)
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: true, message: message)
            }
            message += " Graceful kill attempt for PGID \\(currentPgid) failed or process persisted."
            Logger.log(level: .warn, "[ITermControl] Graceful kill failed or process persisted for PGID \\(currentPgid) in iTerm session \\(params.tag).", file: #file, function: #function)
        }

        // 4. Ctrl+C Fallback (SDD 3.2.5)
        // Condition: No pre-kill script defined AND (PGID not found OR graceful kill failed/process persisted)
        if config.preKillScriptPath == nil && (pgidToKill == nil || !killSuccess) {
            Logger.log(level: .info, "[ITermControl] PGID not found or graceful kill failed for iTerm session \\(params.tag). Attempting Ctrl+C fallback.", file: #file, function: #function)
            guard let _ = sessionInfo.windowIdentifier,
                  let compositeTabID = sessionInfo.tabIdentifier,
                  let sessionID = Self.extractSessionID(from: compositeTabID)
            else {
                message += " Cannot attempt Ctrl+C: session missing window/sessionID identifiers."
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: message)
            }

            let ctrlCScript = ITermScripts.sendControlCScript(
                appName: appName,
                sessionID: sessionID,
                shouldActivateITerm: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false) // Activate if focus desired
            )
            let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)
            switch ctrlCResult {
            case let .success(ctrlCResult):
                guard let strResult = ctrlCResult as? String else {
                    message += " Failed to send Ctrl+C to iTerm session. Unexpected result type: \\(type(of: ctrlCResult))."
                    Logger.log(level: .warn, "[ITermControl] Failed to send Ctrl+C to iTerm session \\(params.tag). Non-string result.", file: #file, function: #function)
                    killSuccess = false
                    break
                }
                if strResult == "OK_CTRL_C_SENT" {
                    message += " Sent Ctrl+C to iTerm session as fallback."
                    Logger.log(level: .info, "[ITermControl] Successfully sent Ctrl+C to iTerm session \\(params.tag).", file: #file, function: #function)
                    // We can't easily confirm kill success from Ctrl+C, so assume it was delivered.
                    // The next status check or operation will reveal if it's still busy.
                    killSuccess = true // Mark as success because the action was performed.
                } else {
                    message += " Failed to send Ctrl+C to iTerm session. AppleScript result: \\(strResult)."
                    Logger.log(level: .warn, "[ITermControl] Failed to send Ctrl+C to iTerm session \\(params.tag). Result: \\(strResult).", file: #file, function: #function)
                    killSuccess = false
                }
            case let .failure(error):
                message += " Failed to send Ctrl+C to iTerm session: \(error.localizedDescription)."
                Logger.log(level: .warn, "[ITermControl] Error sending Ctrl+C to iTerm session \(params.tag): \(error.localizedDescription).", file: #file, function: #function)
                killSuccess = false
            }
        } else if config.preKillScriptPath == nil && pgidToKill != nil && killSuccess {
            // This case is when graceful kill succeeded and there was no pre-kill script, so no fallback needed.
        } else if config.preKillScriptPath != nil {
            // If pre-kill script was run, its success/failure (or the subsequent graceful kill) is the final state.
            // No Ctrl+C fallback in this path according to spec logic.
            Logger.log(level: .debug, "[ITermControl] Pre-kill script was configured for \\(params.tag). Ctrl+C fallback skipped.", file: #file, function: #function)
        }

        // Clear the session screen after all kill attempts
        if let compositeTabID = sessionInfo.tabIdentifier,
           let sessionID = Self.extractSessionID(from: compositeTabID)
        {
            Self._clearSessionScreen(appName: appName, sessionID: sessionID, tag: params.tag)
        }

        return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: killSuccess, message: message)
    }

    // MARK: - Private Helper Methods for iTerm

    private func findOrCreateSessionForITerm(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        let newSessionTitle = SessionUtilities.generateSessionTitle(projectPath: projectPath, tag: tag, ttyDevicePath: nil, processId: nil)
        let shouldActivate = attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        let selectTabOnCreation = shouldActivate // If activating, also select the new tab.
        let defaultProfileName = config.iTermProfileName ?? "Default"

        Logger.log(level: .debug, "[ITermControl] (Refactored) Finding or creating iTerm session. Title: '\(newSessionTitle)', Activate: \(shouldActivate), Profile: \(defaultProfileName)", file: #file, function: #function)

        var targetWindowID: String? = nil
        var existingWindows: [(windowID: String, windowName: String)] = []

        // 1. List existing windows if project grouping is active
        if config.windowGrouping == .project, projectPath != nil {
            let listWinScript = ITermScripts.listWindowsForGroupingScript(appName: appName)
            let listWinResult = AppleScriptBridge.runAppleScript(script: listWinScript)
            switch listWinResult {
            case let .success(data):
                existingWindows = (try? ITermParser.parseWindowListForGrouping(resultData: data, scriptContent: listWinScript)) ?? []
            case let .failure(error):
                Logger.log(level: .warn, "[ITermControl] Failed to list iTerm windows for grouping: \(error.localizedDescription). Proceeding without window list.", file: #file, function: #function)
            }
        }

        // 2. Determine target window ID based on grouping strategy
        if config.windowGrouping == .project, let projPath = projectPath {
            let projectHash = SessionUtilities.generateProjectHash(projectPath: projPath)
            let searchMarker = "::TERMINATOR_SESSION::PROJECT_HASH=\(projectHash)::"
            for winInfo in existingWindows {
                if winInfo.windowName.contains(searchMarker) {
                    targetWindowID = winInfo.windowID
                    Logger.log(level: .debug, "[ITermControl] Found existing iTerm window '\(winInfo.windowName)' (ID: \(targetWindowID!)) for project grouping: \(projPath)", file: #file, function: #function)
                    break
                }
            }
        }

        // If not found by project, or if strategy is .smart, try to use current window.
        if targetWindowID == nil && config.windowGrouping == .smart {
            Logger.log(level: .debug, "[ITermControl] Window grouping is .smart and no project window found. Trying to use current iTerm window.", file: #file, function: #function)
            if shouldActivate { // Ensure iTerm is frontmost for 'current window' to be reliable
                _ = AppleScriptBridge.runAppleScript(script: ITermScripts.activateITermAppScript(appName: appName))
                Thread.sleep(forTimeInterval: 0.1) // Brief pause for activation
            }
            let getCurrentWinScript = ITermScripts.getCurrentWindowIDScript(appName: appName)
            let currentWinResult = AppleScriptBridge.runAppleScript(script: getCurrentWinScript)
            if case let .success(winIdData) = currentWinResult,
               let winIdStr = winIdData as? String,
               !winIdStr.isEmpty, winIdStr != "ERROR" {
                targetWindowID = winIdStr
                Logger.log(level: .debug, "[ITermControl] Using current iTerm window ID: \\(winIdStr) for .smart grouping.", file: #file, function: #function)
            } else {
                Logger.log(level: .debug, "[ITermControl] Could not get current iTerm window for .smart grouping, or iTerm not active. Will create new window.", file: #file, function: #function)
            }
        }
        // If config.windowGrouping is .off, or still no targetWindowID, a new window will be created.

        var newSessionData: (winID: String, tabID: String, sessionID: String, tty: String)

        if let existingWinID = targetWindowID { // Found a window for project grouping or current (if implemented)
            Logger.log(level: .info, "[ITermControl] Creating new tab in existing iTerm window ID: \(existingWinID)", file: #file, function: #function)
            let createTabScript = ITermScripts.createTabInWindowWithProfileScript(
                appName: appName,
                windowID: existingWinID,
                profileName: defaultProfileName,
                shouldActivate: shouldActivate,
                selectTab: selectTabOnCreation
            )
            let createTabResult = AppleScriptBridge.runAppleScript(script: createTabScript)
            switch createTabResult {
            case let .success(data):
                let (tabID, sessionID, tty) = try ITermParser.parseCreateTabInWindowWithProfile(resultData: data, scriptContent: createTabScript)
                newSessionData = (winID: existingWinID, tabID: tabID, sessionID: sessionID, tty: tty)
            case let .failure(error):
                throw TerminalControllerError.appleScriptError(message: "Failed to create new iTerm tab: \(error.localizedDescription)", scriptContent: createTabScript, underlyingError: error)
            }
        } else { // Create a new window
            Logger.log(level: .info, "[ITermControl] Creating new iTerm window.", file: #file, function: #function)
            let createWindowScript = ITermScripts.createWindowWithProfileScript(
                appName: appName,
                profileName: defaultProfileName,
                shouldActivate: shouldActivate
            )
            let createWindowResult = AppleScriptBridge.runAppleScript(script: createWindowScript)
            switch createWindowResult {
            case let .success(data):
                newSessionData = try ITermParser.parseCreateNewWindowWithProfile(resultData: data, scriptContent: createWindowScript)
                // If project grouping was intended, set the new window's name
                if config.windowGrouping == .project, let projPath = projectPath {
                    let projectHash = SessionUtilities.generateProjectHash(projectPath: projPath)
                    let windowNameMarker = "::TERMINATOR_SESSION::PROJECT_HASH=\(projectHash):: (Tag: \(tag))"
                    let setNameScript = ITermScripts.setWindowNameScript(appName: appName, windowID: newSessionData.winID, newName: windowNameMarker)
                    let setNameResult = AppleScriptBridge.runAppleScript(script: setNameScript)
                    if case let .failure(err) = setNameResult {
                        Logger.log(level: .warn, "[ITermControl] Failed to set new iTerm window name for project grouping: \(err.localizedDescription)", file: #file, function: #function)
                    }
                }
            case let .failure(error):
                throw TerminalControllerError.appleScriptError(message: "Failed to create new iTerm window: \(error.localizedDescription)", scriptContent: createWindowScript, underlyingError: error)
            }
        }

        // Set the session name (title)
        let setSessionNameScript = ITermScripts.setSessionNameScript(appName: appName, sessionID: newSessionData.sessionID, newName: newSessionTitle)
        let setSessionNameResult = AppleScriptBridge.runAppleScript(script: setSessionNameScript)
        if case let .failure(error) = setSessionNameResult {
            // Non-fatal, log and continue
            Logger.log(level: .warn, "[ITermControl] Failed to set iTerm session name to '\(newSessionTitle)': \(error.localizedDescription)", file: #file, function: #function)
        }

        // Ensure focus if needed (final check)
        if shouldActivate {
            let focusScript = ITermScripts.selectSessionInITermScript(appName: appName, windowID: newSessionData.winID, tabID: newSessionData.tabID, sessionID: newSessionData.sessionID)
            let focusResult = AppleScriptBridge.runAppleScript(script: focusScript)
            if case let .failure(error) = focusResult {
                Logger.log(level: .warn, "[ITermControl] Post-creation focus attempt failed for iTerm session \(newSessionData.sessionID): \(error.localizedDescription)", file: #file, function: #function)
            }
        }

        let compositeTabIdentifier = "\(newSessionData.tabID):\(newSessionData.sessionID)"
        let userFriendlyIdentifier = SessionUtilities.generateUserFriendlySessionIdentifier(projectPath: projectPath, tag: tag)

        return TerminalSessionInfo(
            sessionIdentifier: userFriendlyIdentifier,
            projectPath: projectPath,
            tag: tag,
            fullTabTitle: newSessionTitle,
            tty: newSessionData.tty,
            isBusy: false, // New session is not busy
            windowIdentifier: newSessionData.winID,
            tabIdentifier: compositeTabIdentifier, // Store composite ID
            ttyFromTitle: nil, // Not parsed from title here
            pidFromTitle: nil // Not parsed from title here
        )
    }

    private func attentesFocus(focusPreference: AppConfig.FocusCLIArgument, defaultFocusSetting: Bool) -> Bool {
        switch focusPreference {
        case .forceFocus:
            return true
        case .noFocus:
            return false
        case .autoBehavior:
            return defaultFocusSetting
        case .default:
            return defaultFocusSetting
        }
    }

    private func _parsePgidFromResult(resultStringOrArray: Any, tty: String, tag: String) -> (pgid: pid_t?, message: String, shouldReturnEarly: Bool) {
        var message = ""
        var pgidToKill: pid_t? = nil
        var shouldReturnEarly = false

        if let resultString = resultStringOrArray as? String, !resultString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = resultString.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
            if let pgidStr = parts.first, let foundPgid = pid_t(pgidStr) {
                pgidToKill = foundPgid
                message += " Identified foreground process group ID: \\(foundPgid)."
                Logger.log(level: .info, "Identified PGID \\(foundPgid) on TTY \\(tty) for iTerm session \\(tag).", file: #file, function: #function)
            } else {
                message += " Could not parse PGID from ps output: '\\(resultString)'."
                Logger.log(level: .warn, "Could not parse PGID from output: '\\(resultString)' for iTerm TTY \\(tty).", file: #file, function: #function)
            }
        } else {
            message += " No foreground process found on TTY \\(tty) in iTerm session to kill."
            Logger.log(level: .info, "No foreground process found on TTY \\(tty) for iTerm session \\(tag). Assuming success.", file: #file, function: #function)
            shouldReturnEarly = true // Indicate that we should return early from the calling function
        }
        return (pgidToKill, message, shouldReturnEarly)
    }

    private static func _clearSessionScreen(appName: String, sessionID: String, tag: String) {
        let clearScript = ITermScripts.clearSessionScript(appName: appName, sessionID: sessionID, shouldActivateITerm: false)
        let clearScriptResult = AppleScriptBridge.runAppleScript(script: clearScript)
        if case let .failure(error) = clearScriptResult {
            Logger.log(level: .warn, "[ITermControl] Failed to clear iTerm session for tag \(tag): \(error.localizedDescription)", file: #file, function: #function)
        }
    }
}
