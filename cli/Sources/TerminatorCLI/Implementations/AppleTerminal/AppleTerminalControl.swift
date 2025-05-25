import Foundation

// Helper structs for parsing AppleScript list output
private struct AppleTerminalTabInfo {
    let id: String
    let title: String
}

private struct AppleTerminalWindowInfo {
    let id: String
    let tabs: [AppleTerminalTabInfo]
}

struct AppleTerminalControl: TerminalControlling {
    let config: AppConfig
    let appName: String // Should be "Terminal" or "Terminal.app"

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .debug, "AppleTerminalControl initialized for app: \(appName)")
    }

    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .info, "[AppleTerminalControl] Listing sessions, filter: \(filterByTag ?? "none")")

        let script = AppleTerminalScripts.listSessionsScript(appName: appName)
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            // resultData is Any from AppleScript result - pass it directly to parser
            // Logger.log(level: .debug, "AppleScript result for Terminal.app listing: \(resultData)") // Can be very verbose
            return try AppleTerminalParser.parseSessionListOutput(resultStringOrArray: resultData, scriptContent: script, filterByTag: filterByTag)

        case let .failure(error):
            Logger.log(level: .error, "Failed to list sessions for Terminal.app: \(error.localizedDescription)")
            throw TerminalControllerError.appleScriptError(message: "Listing sessions failed: \(error.localizedDescription)", scriptContent: script, underlyingError: error)
        }
    }

    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[AppleTerminalControl] Attempting to execute command for tag: \(params.tag), project: \(params.projectPath ?? "none")")

        let sessionToUse = try findOrCreateSessionInternal(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference
        )

        guard let tabID = sessionToUse.tabIdentifier,
              let windowID = sessionToUse.windowIdentifier,
              let tty = sessionToUse.tty
        else {
            throw TerminalControllerError.internalError(details: "Found/created Apple Terminal session is missing critical identifiers. Session: \(sessionToUse)")
        }

        let shouldActivateForCommand = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        // Clear the session screen before any command execution
        // This internal clear might also handle activation if shouldActivateForCommand is true.
        Self._clearSessionScreen(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            tag: params.tag,
            shouldActivate: shouldActivateForCommand
        )

        // Busy Check
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid
            let foundCommand = processInfo.command

            Logger.log(level: .info, "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) is busy with command '\(foundCommand)' (PGID: \(foundPgid)). Attempting to interrupt.")

            _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(level: .debug, "[AppleTerminalControl] Sent SIGINT to PGID \(foundPgid) on TTY \(tty).")

            Thread.sleep(forTimeInterval: Double(config.sigintWaitSeconds)) // Use configured wait time, CASTED

            if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                Logger.log(level: .error, "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) remained busy with command '\(stillBusyInfo.command)' after interrupt attempt.")
                throw TerminalControllerError.busy(tty: tty, processDescription: stillBusyInfo.command)
            } else {
                Logger.log(level: .info, "[AppleTerminalControl] Process on TTY \(tty) was successfully interrupted.")
            }
        }

        // Handle session preparation if command is nil or empty
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(level: .info, "[AppleTerminalControl] No command provided. Preparing session (focus) for tag: \(params.tag)")

            if shouldActivateForCommand {
                let focusScript = AppleTerminalScripts.setSelectedTabScript(appName: appName, windowID: windowID, tabID: tabID)
                _ = AppleScriptBridge.runAppleScript(script: focusScript) // Best effort focus
            }

            return ExecuteCommandResult(
                sessionInfo: sessionToUse,
                output: "",
                exitCode: 0,
                pid: nil,
                wasKilledByTimeout: false
            )
        }

        let commandToExecute = params.command!
        let trimmedCommandToExecute = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)

        let ttyBasename = (tty as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
        let timestamp = Int(Date().timeIntervalSince1970)
        let logFileName = "terminator_output_\(ttyBasename)_\(timestamp)_\(UUID().uuidString.prefix(8)).log"
        let logFilePath = config.logDir.appendingPathComponent("cli_command_outputs").appendingPathComponent(logFileName)

        do {
            try FileManager.default.createDirectory(at: logFilePath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.log(level: .error, "[AppleTerminalControl] Could not create directory for command output logs: \(logFilePath.deletingLastPathComponent().path). Error: \(error.localizedDescription)")
            throw TerminalControllerError.internalError(details: "Failed to create command output log directory.")
        }

        let completionMarker = "TERMINATOR_CMD_LOG_DONE_\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground

        // New: Construct the full shell command here
        let quotedLogFilePathForShell = "'\(logFilePath.path.replacingOccurrences(of: "'", with: "'\\''"))'"
        var shellCommandToExecuteInTerminal: String
        if isForeground {
            let shellEscapedCommand = trimmedCommandToExecute.replacingOccurrences(of: "'", with: "'\\''")
            shellCommandToExecuteInTerminal = "(( \(shellEscapedCommand) ) > \(quotedLogFilePathForShell) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePathForShell))"
        } else { // Background
            let shellEscapedCommand = trimmedCommandToExecute.replacingOccurrences(of: "'", with: "'\\''")
            shellCommandToExecuteInTerminal = "(( \(shellEscapedCommand) ) > \(quotedLogFilePathForShell) 2>&1) & disown"
        }
        // End New

        // Modified: Call the simpler script
        let submissionScript = AppleTerminalScripts.simpleExecuteShellCommandInTabScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shellCommandToExecute: shellCommandToExecuteInTerminal, // Pass the constructed command
            shouldActivateTerminal: shouldActivateForCommand
        )

        Logger.log(level: .debug, "[AppleTerminalControl] Submitting command. Shell cmd: \(shellCommandToExecuteInTerminal). Log: \(logFilePath.path)")
        let appleScriptSubmissionResult = AppleScriptBridge.runAppleScript(script: submissionScript)

        // This part will be further refactored in next steps to include Swift-based polling
        // For now, we handle the submission result and prepare for log processing.
        switch appleScriptSubmissionResult {
        case let .success(submissionResultData):
            // submissionResultData is Any from AppleScript result
            guard let responseStr = submissionResultData as? String, responseStr == "OK_COMMAND_SUBMITTED" else {
                Logger.log(level: .error, "[AppleTerminalControl] Command submission script returned unexpected response or non-string: \(submissionResultData). Log: \(logFilePath.path)")
                _ = try? FileManager.default.removeItem(at: logFilePath) // Clean up potentially empty log file
                throw TerminalControllerError.commandExecutionFailed(reason: "Command submission to Apple Terminal failed or returned unexpected data. Log: \(logFilePath.path)")
            }
            Logger.log(level: .info, "[AppleTerminalControl] Command submitted to Apple Terminal for tag: \(params.tag). Log: \(logFilePath.path)")

            var markerFoundByPolling = false
            var pollingTimedOut = false

            if isForeground {
                Logger.log(level: .debug, "[AppleTerminalControl] Foreground command submitted. Starting Swift polling for completion marker '\(completionMarker)' in tab history.")
                let pollTimeoutSeconds = params.timeout > 0 ? params.timeout : Int(config.foregroundCompletionSeconds)
                let startTime = Date()

                while Date().timeIntervalSince(startTime) < Double(pollTimeoutSeconds) && !markerFoundByPolling {
                    Thread.sleep(forTimeInterval: 0.2) // Polling interval
                    let historyScript = AppleTerminalScripts.getTabHistoryScript(appName: appName, windowID: windowID, tabID: tabID)
                    let historyResult = AppleScriptBridge.runAppleScript(script: historyScript)

                    // historyData is Any from AppleScript result
                    if case let .success(historyData) = historyResult, let historyText = historyData as? String {
                        if historyText.contains(completionMarker) {
                            markerFoundByPolling = true
                            Logger.log(level: .info, "[AppleTerminalControl] Completion marker found in tab history by Swift polling for tag: \(params.tag).")
                        }
                    } else if case .failure = historyResult { // Replaced histError with _
                        Logger.log(level: .warn, "[AppleTerminalControl] Error reading tab history during Swift polling. Continuing poll.")
                        // Consider adding a counter for consecutive errors to break loop if too many.
                    }
                }

                if !markerFoundByPolling {
                    pollingTimedOut = true
                    Logger.log(level: .warn, "[AppleTerminalControl] Foreground command Swift polling timed out for tag: \(params.tag). Log: \(logFilePath.path)")
                }
            } else { // Background command
                // For background, submission success implies we proceed to log capture phase (if any)
                // No polling needed here.
            }

            return try _processExecuteCommandResult(
                sessionInfo: sessionToUse,
                params: params,
                logFilePath: logFilePath.path,
                completionMarker: completionMarker,
                isForeground: isForeground,
                commandSubmittedSuccessfully: true, // Submission was OK
                markerFoundBySwiftPolling: markerFoundByPolling,
                swiftPollingTimedOut: pollingTimedOut
            )

        case let .failure(error):
            let errorMsg = "Failed to submit command via AppleScript for tag '\(params.tag)' (log: \(logFilePath.path)): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            _ = try? FileManager.default.removeItem(at: logFilePath)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: submissionScript, underlyingError: error)
        }
    }

    private func _processExecuteCommandResult(
        sessionInfo: TerminalSessionInfo,
        params: ExecuteCommandParams,
        logFilePath: String,
        completionMarker: String,
        isForeground: Bool,
        commandSubmittedSuccessfully _: Bool, // Remains for structural consistency, though always true if we reach here
        markerFoundBySwiftPolling: Bool,
        swiftPollingTimedOut: Bool
    ) throws -> ExecuteCommandResult {
        var outputText = ""
        var wasKilledByTimeoutInternal = swiftPollingTimedOut // Initialize with polling timeout status

        if isForeground {
            if markerFoundBySwiftPolling {
                outputText = "Foreground command completed. Marker found by Swift polling."
                Logger.log(level: .info, "[AppleTerminalControl] Processing result: Foreground marker found for tag: \(params.tag).")
            } else if swiftPollingTimedOut {
                outputText = "Timeout waiting for foreground completion marker (Swift polling). Log (\(logFilePath)) may contain output."
                Logger.log(level: .warn, "[AppleTerminalControl] Processing result: Foreground Swift polling TIMEOUT for tag: \(params.tag). Log: \(logFilePath)")
            } else {
                // This case should ideally not be hit if submission was successful and it's foreground.
                // It implies neither marker found nor timeout, which is unusual for foreground.
                outputText = "Foreground command submitted, but completion status unclear after Swift polling."
                Logger.log(level: .warn, "[AppleTerminalControl] Processing result: Foreground completion status unclear for tag: \(params.tag) after Swift polling. Log: \(logFilePath)")
            }
        } else { // Background
            outputText = "Background command submitted. Output logged to: \(logFilePath)"
            Logger.log(level: .info, "[AppleTerminalControl] Processing result: Background command for tag: \(params.tag). Log: \(logFilePath)")
        }

        var finalLogOutput = ""
        if FileManager.default.fileExists(atPath: logFilePath) {
            let linesToCaptureAfterCmd = (isForeground && markerFoundBySwiftPolling) ? params.linesToCapture : config.defaultLines
            let markerForTailingInLog = (isForeground && markerFoundBySwiftPolling) ? completionMarker : "TERMINATOR_BG_OR_TIMEOUT_LOG_CAPTURE_\(UUID().uuidString)" // Different marker for BG/Timeout to capture initial lines
            let timeoutForLogTailing = (isForeground && markerFoundBySwiftPolling) ? 2 : (isForeground ? params.timeout : Int(config.backgroundStartupSeconds))

            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: markerForTailingInLog,
                timeoutSeconds: timeoutForLogTailing,
                linesToCapture: linesToCaptureAfterCmd,
                controlIdentifier: isForeground ? "AppleTerminalFGLogProcess" : "AppleTerminalBGLogProcess"
            )
            finalLogOutput = tailResult.output

            if isForeground && markerFoundBySwiftPolling && !wasKilledByTimeoutInternal {
                Logger.log(level: .debug, "[AppleTerminalControl] Foreground command completed. Removing log file: \(logFilePath)")
                do {
                    try FileManager.default.removeItem(atPath: logFilePath)
                } catch {
                    Logger.log(level: .warn, "[AppleTerminalControl] Failed to delete foreground command output log \(logFilePath): \(error.localizedDescription)")
                }
            } else if wasKilledByTimeoutInternal {
                finalLogOutput = outputText + "\n--- PARTIAL LOG CONTENT ON SWIFT POLLING TIMEOUT ---\n" + finalLogOutput
            } else if !isForeground {
                finalLogOutput = outputText + "\n--- INITIAL BACKGROUND OUTPUT (up to \(linesToCaptureAfterCmd) lines) ---\n" + finalLogOutput.replacingOccurrences(of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
            }
        } else {
            finalLogOutput = outputText // If log file doesn't exist for some reason
            Logger.log(level: .warn, "[AppleTerminalControl] Log file not found at \(logFilePath) during final processing.")
        }

        // Kill timed out foreground process if necessary (based on Swift polling timeout)
        if isForeground && swiftPollingTimedOut && sessionInfo.tty != nil { // Check swiftPollingTimedOut here
            if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: sessionInfo.tty!) {
                let pgidToKill = processInfo.pgid
                var killMsg = ""
                if ProcessUtilities.attemptExecuteTimeoutKill(pgid: pgidToKill, config: config, message: &killMsg) {
                    finalLogOutput += "\n--- KILLED PROCESS GROUP \(pgidToKill) DUE TO SWIFT POLLING TIMEOUT --- \(killMsg)"
                    Logger.log(level: .info, "[AppleTerminalControl] Successfully killed PGID \(pgidToKill) for timed out command (Swift polling) on tag \(params.tag).")
                } else {
                    finalLogOutput += "\n--- FAILED TO KILL PROCESS GROUP \(pgidToKill) AFTER SWIFT POLLING TIMEOUT --- \(killMsg)"
                    Logger.log(level: .warn, "[AppleTerminalControl] Failed to kill PGID \(pgidToKill) for timed out command (Swift polling) on tag \(params.tag).")
                }
            } else {
                finalLogOutput += "\n--- COULD NOT IDENTIFY PROCESS GROUP TO KILL AFTER SWIFT POLLING TIMEOUT ---"
                Logger.log(level: .warn, "[AppleTerminalControl] Could not identify PGID to kill for timed out command (Swift polling) on tag \(params.tag).")
            }
            wasKilledByTimeoutInternal = true // Ensure this is set if we attempted a kill due to swift polling timeout
        }

        let finalSessionIsBusy = isForeground ? (swiftPollingTimedOut || !markerFoundBySwiftPolling) : true
        let updatedSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle,
            tty: sessionInfo.tty,
            isBusy: finalSessionIsBusy,
            windowIdentifier: sessionInfo.windowIdentifier,
            tabIdentifier: sessionInfo.tabIdentifier,
            ttyFromTitle: sessionInfo.ttyFromTitle,
            pidFromTitle: sessionInfo.pidFromTitle
        )

        return ExecuteCommandResult(
            sessionInfo: updatedSessionInfo,
            output: finalLogOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: nil,
            pid: nil,
            wasKilledByTimeout: wasKilledByTimeoutInternal
        )
    }

    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Reading session output for tag: \(params.tag), project: \(params.projectPath ?? "none")")

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "Session found for reading is missing tabID or windowID. Session: \(sessionInfo)")
        }

        let script = AppleTerminalScripts.readSessionOutputScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        )
        // Logger.log(level: .debug, "AppleScript for readSessionOutput (Apple Terminal):\n\(script)") // Script content now in AppleTerminalScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            // resultData is Any from AppleScript result - pass it directly to parser
            return try AppleTerminalParser.parseReadSessionOutput(resultData: resultData, scriptContent: script, sessionInfo: sessionInfo, linesToRead: params.linesToRead)

        case let .failure(error):
            let errorMsg = "Failed to read session output for tag '\(params.tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Focusing session for tag: \(params.tag), project: \(params.projectPath ?? "none")")

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "Session found for focus is missing tabID or windowID. Session: \(sessionInfo)")
        }

        let script = AppleTerminalScripts.focusSessionScript(appName: appName, windowID: windowID, tabID: tabID)
        // Logger.log(level: .debug, "AppleScript for focusSession (Apple Terminal):\n\(script)")

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            // resultData is Any from AppleScript result
            Logger.log(level: .info, "Successfully focused session for tag: \(params.tag). AppleScript result: \(resultData)")
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case let .failure(error):
            let errorMsg = "Failed to focus session for tag '\(params.tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Killing process in session for tag: \(params.tag), project: \(params.projectPath ?? "none")")

        let existingSessions = try listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tty = sessionInfo.tty, !tty.isEmpty else {
            Logger.log(level: .warn, "Session \(params.tag) found but has no TTY. Cannot kill process.")
            return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: "Session has no TTY.")
        }

        var killSuccess = false
        var message = "Kill attempt for session \(params.tag) (TTY: \(tty))."
        var pgidToKill: pid_t? = nil

        // Use ProcessUtilities.getForegroundProcessInfo instead of AppleScript ps command
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            pgidToKill = processInfo.pgid
            message += " Identified foreground process group ID: \(processInfo.pgid) (command: \(processInfo.command))."
            Logger.log(level: .info, "Identified PGID \(processInfo.pgid) for command '\(processInfo.command)' on TTY \(tty) for session \(params.tag).")
        } else {
            message += " No foreground process found on TTY \(tty) to kill."
            Logger.log(level: .info, "No foreground process found on TTY \(tty) for session \(params.tag). Assuming success as nothing to kill.")
            if config.preKillScriptPath != nil {
                // If pre-kill script is defined and no process found, consider it success
                killSuccess = true
            }
        }

        // Attempt graceful kill if PGID was found and kill hasn't already 'succeeded' (e.g. by finding no process)
        if let currentPgid = pgidToKill, currentPgid > 0, !killSuccess {
            killSuccess = ProcessUtilities.attemptGracefulKill(pgid: currentPgid, config: config, message: &message)
        }

        // Ctrl+C Fallback (SDD 3.2.5)
        // Condition: No pre-kill script AND (PGID not found OR graceful kill failed/process persisted)
        if config.preKillScriptPath == nil && (pgidToKill == nil || !killSuccess) {
            Logger.log(level: .info, "[AppleTerminalControl] PGID not found or graceful kill failed for session \(params.tag). Attempting Ctrl+C fallback.")
            guard let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier else {
                message += " Cannot attempt Ctrl+C: session missing window/tab identifiers."
                // killSuccess remains as it was
                Logger.log(level: .warn, message)
                return KillSessionResult(
                    killedSessionInfo: sessionInfo,
                    killSuccess: killSuccess,
                    message: message
                )
            }
            let ctrlCScript = AppleTerminalScripts.sendControlCScript(
                appName: appName,
                windowID: windowID,
                tabID: tabID,
                shouldActivateTerminal: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false) // Activate if focus desired
            )
            let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)
            switch ctrlCResult {
            case let .success(resultData):
                // resultData is Any from AppleScript result
                if let str = resultData as? String, str == "OK_CTRL_C_SENT" {
                    message += " Sent Ctrl+C to session as fallback."
                    Logger.log(level: .info, "[AppleTerminalControl] Successfully sent Ctrl+C to session \(params.tag).")
                    killSuccess = true // Mark as success because the action was performed.
                } else {
                    message += " Failed to send Ctrl+C to session. AppleScript result: \(resultData)."
                    Logger.log(level: .warn, "[AppleTerminalControl] Failed to send Ctrl+C to session \(params.tag). Result: \(resultData).")
                    // killSuccess remains as it was
                }
            case let .failure(error):
                message += " Failed to send Ctrl+C to session: \(error.localizedDescription)."
                Logger.log(level: .warn, "[AppleTerminalControl] Error sending Ctrl+C to session \(params.tag): \(error.localizedDescription).")
                // killSuccess remains as it was
            }
        } else if config.preKillScriptPath != nil {
            Logger.log(level: .debug, "[AppleTerminalControl] Pre-kill script was configured for \(params.tag). Ctrl+C fallback was skipped or conditions not met.")
        } else if killSuccess {
            Logger.log(level: .debug, "[AppleTerminalControl] Graceful kill succeeded or no process found. Ctrl+C fallback skipped for \(params.tag).")
        }

        // Clear the session screen after all kill attempts
        if let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier {
            Self._clearSessionScreen(
                appName: appName,
                windowID: windowID,
                tabID: tabID,
                tag: params.tag,
                shouldActivate: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false)
            )
            message += " Screen cleared post-kill attempt."
        } else {
            message += " Could not clear screen post-kill: session missing window/tab identifiers."
            Logger.log(level: .warn, "[AppleTerminalControl] Could not clear screen for session \(params.tag) post-kill: missing identifiers.")
        }

        return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: killSuccess, message: message)
    }

    // MARK: - Private Helper Methods for Apple Terminal

    private static func _clearSessionScreen(appName: String, windowID: String, tabID: String, tag: String, shouldActivate: Bool) {
        let clearScript = AppleTerminalScripts.clearSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: shouldActivate
        )
        let clearScriptResult = AppleScriptBridge.runAppleScript(script: clearScript)
        if case let .failure(error) = clearScriptResult {
            Logger.log(level: .warn, "[AppleTerminalControl] Failed to clear session \(tag): \(error.localizedDescription)")
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
                message += " Identified foreground process group ID: \(foundPgid)."
                Logger.log(level: .info, "Identified PGID \(foundPgid) on TTY \(tty) for session \(tag).")
                if parts.count > 1 {
                    let _ = parts[1]
                    Logger.log(level: .debug, "Foreground PID in group also identified as: \(parts[1]) for TTY \(tty) session \(tag).")
                }
            } else {
                message += " Could not parse PGID from ps output: '\(resultString)'."
                Logger.log(level: .warn, "Could not parse PGID from output: '\(resultString)' for TTY \(tty) session \(tag).")
            }
        } else {
            message += " No foreground process found on TTY \(tty) to kill."
            Logger.log(level: .info, "No foreground process found on TTY \(tty) for session \(tag). Assuming success as nothing to kill.")
            shouldReturnEarly = true
        }
        return (pgidToKill, message, shouldReturnEarly)
    }

    private func findOrCreateSessionInternal(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        let newSessionTitle = SessionUtilities.generateSessionTitle(projectPath: projectPath, tag: tag, ttyDevicePath: nil, processId: nil)
        let shouldActivate = attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        Logger.log(level: .debug, "[AppleTerminalControl] Finding or creating session. Title: '\(newSessionTitle)', Activate: \(shouldActivate)")

        // 1. List existing windows and tabs
        let listScript = AppleTerminalScripts.listWindowsAndTabsWithTitlesScript(appName: appName)
        let listResult = AppleScriptBridge.runAppleScript(script: listScript)

        var existingWindowsInfo: [AppleTerminalWindowInfo] = []
        switch listResult {
        case let .success(rawList):
            existingWindowsInfo = parseWindowAndTabData(rawList)
        case let .failure(error):
            Logger.log(level: .warn, "[AppleTerminalControl] Failed to list windows/tabs during findOrCreate: \(error.localizedDescription). Proceeding as if no windows exist.")
            // Continue, will likely create a new window
        }

        // 2. Try to find an existing session (tab with matching title)
        for windowInfo in existingWindowsInfo {
            for tabInfo in windowInfo.tabs {
                if tabInfo.title == newSessionTitle {
                    Logger.log(level: .info, "[AppleTerminalControl] Found existing session (tag: '\(tag)') in window \(windowInfo.id), tab \(tabInfo.id).")
                    // Need to get TTY for this existing tab. This might require another small script or enhance listWindowsAndTabs.
                    // For now, we assume listSessions would have found it if it was fully queryable.
                    // This path implies the session exists, we should try to focus it if needed.
                    if shouldActivate {
                        _ = AppleScriptBridge.runAppleScript(script: AppleTerminalScripts.setSelectedTabScript(appName: appName, windowID: windowInfo.id, tabID: tabInfo.id))
                    }
                    // Constructing TerminalSessionInfo for an existing tab found this way is tricky
                    // as `listWindowsAndTabsWithTitlesScript` doesn't give TTY.
                    // This simplified find might be better suited for just locating a window for grouping.
                    // For robust session re-use, `listSessions` is the primary mechanism.
                    // Let's assume for now that if we find by title, it's for window grouping and we'll create a new tab in it.
                    // This part needs more thought if we want to reuse exact tabs found by title only.
                }
            }
        }

        // 3. Determine target window ID based on grouping strategy
        var targetWindowID: String? = nil
        let windowGroupingStrategy = config.windowGrouping

        if windowGroupingStrategy == .project, let projPath = projectPath {
            let projectIdentifier = SessionUtilities.generateProjectHash(projectPath: projPath) // Use consistent naming
            let titleSearchPrefix = "\(SessionUtilities.sessionPrefix)PROJECT_HASH=\(projectIdentifier)::"
            for windowInfo in existingWindowsInfo {
                for tabInfo in windowInfo.tabs {
                    if tabInfo.title.starts(with: titleSearchPrefix) {
                        targetWindowID = windowInfo.id
                        Logger.log(level: .debug, "[AppleTerminalControl] Found window \(targetWindowID!) for project grouping: \(projPath)")
                        break
                    }
                }
                if targetWindowID != nil { break }
            }
            if targetWindowID == nil {
                Logger.log(level: .debug, "[AppleTerminalControl] No window found for project \(projPath). Will create new one if no other strategy matches.")
            }
        } else if windowGroupingStrategy == .smart {
            if let firstWindow = existingWindowsInfo.first {
                targetWindowID = firstWindow.id
                Logger.log(level: .debug, "[AppleTerminalControl] Smart grouping: Using first available window ID \(targetWindowID!).")
            } else {
                Logger.log(level: .debug, "[AppleTerminalControl] Smart grouping: No existing windows found. Will create new one.")
            }
        }
        // If windowGroupingStrategy is .off, or .project/.smart didn't find a window, targetWindowID remains nil here.

        if targetWindowID == nil {
            Logger.log(level: .debug, "[AppleTerminalControl] No suitable window found by grouping strategy or grouping is .off. Creating new window.")
            let createWindowScript = AppleTerminalScripts.createWindowScript(appName: appName, shouldActivateTerminal: shouldActivate)
            switch AppleScriptBridge.runAppleScript(script: createWindowScript) {
            case let .success(resultData):
                // resultData is Any from AppleScript result
                targetWindowID = resultData as? String
                if targetWindowID == nil {
                    Logger.log(level: .error, "Could not parse new window ID from AppleScript result (expected String): \(resultData)")
                }
            case let .failure(error):
                throw TerminalControllerError.appleScriptError(message: "Failed to create new window: \(error.localizedDescription)", scriptContent: createWindowScript, underlyingError: error)
            }
            guard let _ = targetWindowID else {
                throw TerminalControllerError.internalError(details: "Failed to obtain target window ID after creation attempt.")
            }
        }

        guard let finalWindowID = targetWindowID else {
            throw TerminalControllerError.internalError(details: "Could not determine target window ID for new tab.")
        }

        // 4. Create the new tab in the target window
        let createTabScript = AppleTerminalScripts.createTabInWindowScript(appName: appName, windowID: finalWindowID, newSessionTitle: newSessionTitle, shouldActivateTerminal: shouldActivate)
        let createTabResult = AppleScriptBridge.runAppleScript(script: createTabScript)

        switch createTabResult {
        case let .success(tabResultData):
            // tabResultData is Any from AppleScript result - expected to be a list
            guard let resultArray = tabResultData as? [Any], resultArray.count == 4 else {
                let errorMessage: String
                if tabResultData is [Any] {
                    errorMessage = "Create tab script returned a list but with unexpected item count. Expected 4. Got: \((tabResultData as? [Any])?.count ?? -1). Data: \(tabResultData)"
                } else {
                    errorMessage = "Create tab script returned unexpected type (expected list): \(tabResultData)"
                }
                throw TerminalControllerError.appleScriptError(message: errorMessage, scriptContent: createTabScript, underlyingError: nil)
            }

            let winID = resultArray[0] as? String
            let tabID = resultArray[1] as? String
            let tty = resultArray[2] as? String
            let _ = resultArray[3] as? String

            guard let wID = winID, let tID = tabID, let ttyPath = tty else {
                throw TerminalControllerError.appleScriptError(message: "Create tab script returned array with non-string elements: \(resultArray)", scriptContent: createTabScript, underlyingError: nil)
            }

            Logger.log(level: .info, "[AppleTerminalControl] Successfully created new tab. Window: \(wID), Tab: \(tID), TTY: \(ttyPath), Title: \(resultArray[3] as? String ?? "N/A")")

            let sessionInfo = TerminalSessionInfo(
                sessionIdentifier: "\(wID):\(tID)",
                projectPath: projectPath,
                tag: tag,
                fullTabTitle: newSessionTitle,
                tty: ttyPath,
                isBusy: false,
                windowIdentifier: wID,
                tabIdentifier: tID,
                ttyFromTitle: nil,
                pidFromTitle: nil
            )
            return sessionInfo

        case let .failure(error):
            throw TerminalControllerError.appleScriptError(message: "Failed to create new tab in window \(finalWindowID): \(error.localizedDescription)", scriptContent: createTabScript, underlyingError: error)
        }
    }

    // Helper to parse the output of listWindowsAndTabsWithTitlesScript
    private func parseWindowAndTabData(_ data: Any) -> [AppleTerminalWindowInfo] {
        guard let windowList = data as? [[Any]] else {
            Logger.log(level: .warn, "[AppleTerminalControl] Could not parse window list from AppleScript: Data is not [[Any]]. Got: \(data)")
            return []
        }

        var result: [AppleTerminalWindowInfo] = []
        for windowEntry in windowList {
            guard windowEntry.count == 2,
                  let windowID = windowEntry[0] as? String,
                  let tabList = windowEntry[1] as? [[Any]]
            else {
                Logger.log(level: .warn, "[AppleTerminalControl] Skipping invalid window entry: \(windowEntry)")
                continue
            }

            var tabs: [AppleTerminalTabInfo] = []
            for tabEntry in tabList {
                guard tabEntry.count == 2,
                      let tabID = tabEntry[0] as? String,
                      let tabTitle = tabEntry[1] as? String
                else {
                    Logger.log(level: .warn, "[AppleTerminalControl] Skipping invalid tab entry for window \(windowID): \(tabEntry)")
                    continue
                }
                tabs.append(AppleTerminalTabInfo(id: tabID, title: tabTitle))
            }
            result.append(AppleTerminalWindowInfo(id: windowID, tabs: tabs))
        }
        return result
    }

    private func attentesFocus(focusPreference: AppConfig.FocusCLIArgument, defaultFocusSetting: Bool) -> Bool {
        switch focusPreference {
        case .forceFocus:
            return true
        case .noFocus:
            return false
        case .default:
            return defaultFocusSetting
        case .autoBehavior:
            return defaultFocusSetting
        }
    }
}