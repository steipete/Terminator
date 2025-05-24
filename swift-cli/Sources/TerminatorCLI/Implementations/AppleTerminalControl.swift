import Foundation

struct AppleTerminalControl: TerminalControlling {
    let config: AppConfig
    let appName: String // Should be "Terminal" or "Terminal.app"

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .debug, "AppleTerminalControl initialized for app: \(appName)")
    }

    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .info, "[AppleTerminalControl] Listing sessions, filter: \(filterByTag ?? "N/A")")
        
        let script = AppleTerminalScripts.listSessionsScript(appName: self.appName)
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultStringOrArray):
            Logger.log(level: .debug, "AppleScript result for Terminal.app listing: \(resultStringOrArray)")
            return try AppleTerminalParser.parseSessionListOutput(resultStringOrArray: resultStringOrArray, scriptContent: script, filterByTag: filterByTag)
            
        case .failure(let error):
            Logger.log(level: .error, "Failed to list sessions for Terminal.app: \(error.localizedDescription)")
            throw TerminalControllerError.appleScriptError(message: "Listing sessions failed: \(error.localizedDescription)", scriptContent: script, underlyingError: error)
        }
    }
    
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[AppleTerminalControl] Attempting to execute command for tag: \(params.tag), project: \(params.projectPath ?? "N/A")")

        let sessionToUse = try findOrCreateSessionForAppleTerminal(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference
        )

        guard let tabID = sessionToUse.tabIdentifier,
              let windowID = sessionToUse.windowIdentifier,
              let tty = sessionToUse.tty else {
            throw TerminalControllerError.internalError(details: "Found/created Apple Terminal session is missing critical identifiers. Session: \(sessionToUse)")
        }

        // Clear the session screen before any command execution
        Self._clearSessionScreen(
            appName: self.appName, 
            windowID: windowID, 
            tabID: tabID, 
            tag: params.tag, 
            shouldActivate: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        )

        // Busy Check - updated to use ProcessUtilities.getForegroundProcessInfo
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid
            let foundCommand = processInfo.command
            
            Logger.log(level: .info, "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) is busy with command '\(foundCommand)' (PGID: \(foundPgid)). Attempting to interrupt.")
            
            // Send SIGINT to the process group
            ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(level: .debug, "[AppleTerminalControl] Sent SIGINT to PGID \(foundPgid) on TTY \(tty).")
            
            // Wait for 3 seconds
            Thread.sleep(forTimeInterval: 3.0)
            
            // Check if TTY is still busy
            if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                Logger.log(level: .error, "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) remained busy with command '\(stillBusyInfo.command)' after interrupt attempt.")
                throw TerminalControllerError.sessionBusyError(
                    message: "Session for tag \(params.tag) (TTY: \(tty)) remained busy with command '\(stillBusyInfo.command)' after interrupt attempt.",
                    suggestedErrorCode: ErrorCodes.sessionBusyError
                )
            } else {
                Logger.log(level: .info, "[AppleTerminalControl] Process on TTY \(tty) was successfully interrupted.")
            }
        }
        // End of Busy Check

        // Handle session preparation if command is nil or empty (SDD 3.1.5, 3.2.5)
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(level: .info, "[AppleTerminalControl] No command provided. Preparing session (focus) for tag: \(params.tag)")
            
            // Ensure focus (findOrCreateSession already handled initial focus, this re-confirms if needed)
            if attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                 let focusScript = AppleTerminalScripts.focusSessionScript(appName: self.appName, windowID: windowID, tabID: tabID)
                _ = AppleScriptBridge.runAppleScript(script: focusScript) // Best effort focus
            }
            
            return ExecuteCommandResult(
                sessionInfo: sessionToUse,
                output: "", // No command output
                exitCode: 0, // Success for prep
                pid: nil,
                wasKilledByTimeout: false
            )
        }
        
        // Existing command execution logic follows...
        let commandToExecute = params.command! // Now we know command is not nil
        
        // var output = "" // No longer needed here
        // var exitCode: Int? = nil // No longer needed here
        // var pid: pid_t? = nil // No longer needed here
        var wasKilledByTimeout = false // This will be set by _processExecuteCommandResult
        
        let trimmedCommandToExecute = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)

        // Create unique log file path (SDD 3.2.5)
        let ttyBasename = (tty as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
        let timestamp = Int(Date().timeIntervalSince1970)
        let logFileName = "terminator_output_\(ttyBasename)_\(timestamp)_\(UUID().uuidString.prefix(8)).log"
        let logFilePath = config.logDir.appendingPathComponent("cli_command_outputs").appendingPathComponent(logFileName)
        
        do { // Ensure the directory for command outputs exists
            try FileManager.default.createDirectory(at: logFilePath.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.log(level: .error, "[AppleTerminalControl] Could not create directory for command output logs: \(logFilePath.deletingLastPathComponent().path). Error: \(error.localizedDescription)")
            throw TerminalControllerError.internalError(details: "Failed to create command output log directory.")
        }

        let completionMarker = "TERMINATOR_CMD_LOG_DONE_\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground

        let script = AppleTerminalScripts.executeCommandScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID,
            tty: tty, // Pass full TTY path, script uses lastPathComponent
            commandToRunRaw: trimmedCommandToExecute, // Pass raw command
            outputLogFilePath: logFilePath.path,
            completionMarker: completionMarker,
            timeoutSeconds: params.timeout, // For AS waiting for marker
            isForeground: isForeground,
            shouldActivateTerminal: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        )

        Logger.log(level: .debug, "[AppleTerminalControl] Executing command with output to: \(logFilePath.path). AppleScript:\n\(script)")
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            return try _processExecuteCommandResult(
                appleScriptResultData: resultData, // Will be JSON string
                scriptContent: script, 
                sessionInfo: sessionToUse, 
                params: params, 
                logFilePath: logFilePath.path, // Pass log file path
                completionMarker: completionMarker // Pass marker
            )
        case .failure(let error):
            let errorMsg = "Failed to execute command for tag '\(params.tag)' (log: \(logFilePath.path)): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
             _ = try? FileManager.default.removeItem(at: logFilePath) // Cleanup attempt
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    private func _processExecuteCommandResult(appleScriptResultData: Any, scriptContent: String, sessionInfo: TerminalSessionInfo, params: ExecuteCommandParams, logFilePath: String, completionMarker: String) throws -> ExecuteCommandResult {
        var outputText = ""
        var wasKilledByTimeout = false
        let finalPid: pid_t? = nil // PID not reliably captured this way yet for Apple Terminal

        guard let jsonString = appleScriptResultData as? String,
              let jsonData = jsonString.data(using: .utf8) else {
            Logger.log(level: .error, "[AppleTerminalControl] Failed to decode AppleScript response (not a JSON string). Log file: \\(logFilePath). Response: \\(appleScriptResultData)")
            // Attempt to clean up the log file if we can't even parse the response
            _ = try? FileManager.default.removeItem(atPath: logFilePath)
            throw TerminalControllerError.commandExecutionFailed(reason: "Invalid response structure from AppleTerminal execution script (expected JSON string). Log: \\(logFilePath)", scriptContent: scriptContent)
        }

        let scriptResponse: AppleScriptExecuteResponse
        do {
            let decoder = JSONDecoder()
            scriptResponse = try decoder.decode(AppleScriptExecuteResponse.self, from: jsonData)
            Logger.log(level: .debug, "[AppleTerminalControl] Decoded AppleScript response: Status='\\(scriptResponse.status)', Message='\\(scriptResponse.message ?? "N/A")', LogFile='\\(scriptResponse.log_file)'")
        } catch {
            Logger.log(level: .error, "[AppleTerminalControl] JSON decoding error for AppleScript response. Error: \\(error.localizedDescription). JSON String: '\\(jsonString)'. Log file: \\(logFilePath)")
            // Attempt to clean up the log file if JSON parsing fails
            _ = try? FileManager.default.removeItem(atPath: logFilePath)
            throw TerminalControllerError.commandExecutionFailed(reason: "Failed to decode JSON response from AppleTerminal execution script. Error: \\(error.localizedDescription). Log: \\(logFilePath)", scriptContent: scriptContent)
        }
        
        // The log file path from the script response should ideally be the same one we passed in.
        // If it's different, log a warning but prefer the one from the script as it's authoritative for where the script *actually* wrote.
        let effectiveLogFilePath = scriptResponse.log_file
        if effectiveLogFilePath != logFilePath {
            Logger.log(level: .warn, "[AppleTerminalControl] Log file path mismatch. Expected: \\(logFilePath), Received from script: \\(effectiveLogFilePath). Using received path.")
        }

        var finalSessionIsBusy = sessionInfo.isBusy // Default to original busy status

        switch scriptResponse.status {
        case "OK_SUBMITTED_FG": // Foreground command submitted, marker found in history by AppleScript
            Logger.log(level: .info, "[AppleTerminalControl] Foreground command submitted for tag: \\(params.tag). AppleScript reported marker found. Now tailing log file: \\(effectiveLogFilePath)")
            
            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: effectiveLogFilePath,
                marker: completionMarker,
                timeoutSeconds: params.timeout > 0 ? params.timeout : 5, // Use command timeout, or 5s default if 0
                linesToCapture: params.linesToCapture,
                controlIdentifier: "AppleTerminalFG"
            )
            
            outputText = tailResult.output
            wasKilledByTimeout = tailResult.timedOut // If tailing timed out despite AS saying marker was seen
            
            if tailResult.timedOut {
                Logger.log(level: .warn, "[AppleTerminalControl] Tailing log file \\(effectiveLogFilePath) for marker timed out, even though AppleScript reported finding it in history. Output may be incomplete.")
                outputText += "\\n---[TAILING FOR MARKER TIMED OUT IN SWIFT AFTER APPLE SCRIPT REPORTED SUCCESS] ---"
            } else {
                Logger.log(level: .info, "[AppleTerminalControl] Successfully tailed log file \\(effectiveLogFilePath) for marker.")
                // Delete log file on successful foreground command completion and if not just session prep
                if params.command != nil && !params.command!.isEmpty {
                     do {
                        try FileManager.default.removeItem(atPath: effectiveLogFilePath)
                        Logger.log(level: .debug, "[AppleTerminalControl] Deleted foreground command output log: \\(effectiveLogFilePath)")
                    } catch {
                        Logger.log(level: .warn, "[AppleTerminalControl] Failed to delete foreground command output log \\(effectiveLogFilePath): \\(error.localizedDescription)")
                    }
                } else {
                    // If it was session prep, it wouldn't hit this path usually, but if it did, clear the log.
                     _ = try? FileManager.default.removeItem(atPath: effectiveLogFilePath)
                }
            }
            finalSessionIsBusy = false // Foreground command is considered finished

        case "TIMEOUT": // AppleScript timed out waiting for marker in history
            wasKilledByTimeout = true
            outputText = scriptResponse.message ?? "Command execution timed out (AppleScript history poll)."
            outputText += "\\nOutput log: \\(effectiveLogFilePath)"
            Logger.log(level: .warn, "[AppleTerminalControl] Command execution timed out for tag: \\(params.tag), as reported by AppleScript history poll. Log: \\(effectiveLogFilePath)")
            // We might still want to capture partial output if the log file exists
            if FileManager.default.fileExists(atPath: effectiveLogFilePath) {
                do {
                    let partialContent = try String(contentsOfFile: effectiveLogFilePath, encoding: .utf8)
                    let lines = partialContent.components(separatedBy: .newlines)
                    let captured: String
                    if params.linesToCapture > 0 && lines.count > params.linesToCapture {
                        captured = lines.suffix(params.linesToCapture).joined(separator: "\\n")
                    } else {
                        captured = lines.joined(separator: "\\n")
                    }
                    outputText += "\\n--- PARTIAL LOG CONTENT ON TIMEOUT ---\\n" + captured
                } catch {
                     Logger.log(level: .warn, "[AppleTerminalControl] Failed to read partial log \\(effectiveLogFilePath) on AppleScript timeout: \\(error.localizedDescription)")
                }
            }
            finalSessionIsBusy = ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty) // Re-check busy status
            
            // SDD 3.2.5: If timeout, sends SIGTERM then SIGKILL to the process group
            if params.executionMode == .foreground && sessionInfo.tty != nil {
                if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: sessionInfo.tty!) {
                    let pgidToKill = processInfo.pgid
                    var killMsg = ""
                    if ProcessUtilities.attemptExecuteTimeoutKill(pgid: pgidToKill, config: config, message: &killMsg) {
                        outputText += "\n--- KILLED PROCESS GROUP \(pgidToKill) DUE TO TIMEOUT ---" + killMsg
                        Logger.log(level: .info, "[AppleTerminalControl] Successfully killed PGID \(pgidToKill) for timed out command on tag \(params.tag).")
                    } else {
                        outputText += "\n--- FAILED TO KILL PROCESS GROUP \(pgidToKill) AFTER TIMEOUT ---" + killMsg
                        Logger.log(level: .warn, "[AppleTerminalControl] Failed to kill PGID \(pgidToKill) for timed out command on tag \(params.tag).")
                    }
                } else {
                    outputText += "\n--- COULD NOT IDENTIFY PROCESS GROUP TO KILL AFTER TIMEOUT ---"
                    Logger.log(level: .warn, "[AppleTerminalControl] Could not identify PGID to kill for timed out command on tag \(params.tag).")
                }
            }

        case "ERROR":
            Logger.log(level: .error, "[AppleTerminalControl] AppleScript execution failed for tag: \\(params.tag). Status: ERROR. Message: \\(scriptResponse.message ?? "No message"). Log: \\(effectiveLogFilePath)")
            outputText = "AppleScript execution error: \\(scriptResponse.message ?? "Unknown error from script"). Log: \\(effectiveLogFilePath)"
            // Don't delete error logs by default, they might be useful for debugging.
            // We might re-check busy status here too, as command might not have run or exited cleanly.
            finalSessionIsBusy = ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty)
             // This is an error from the AppleScript execution itself (e.g., couldn't find tab, etc.)
            // The command might not have even started.
            throw TerminalControllerError.appleScriptError(message: "AppleScript execution error: \\(scriptResponse.message ?? "Unknown error from script"). Log: \\(effectiveLogFilePath)", scriptContent: scriptContent, underlyingError: nil)

        default: // Includes implicit background (AppleScript just does `do script ... & disown`)
            if params.executionMode == .background {
                Logger.log(level: .info, "[AppleTerminalControl] Background command submitted for tag \\(params.tag). Output is being logged to: \\(effectiveLogFilePath)")
                outputText = "Background command submitted. Output logged to: \\(effectiveLogFilePath)"
                
                // SDD 3.2.5: For background, tail output file for `timeout-seconds` (for initial output)
                // We use a marker that's not expected to be found to just capture initial output within timeout.
                let uniqueNonMarker = "TERMINATOR_BG_NEVER_FOUND_\(UUID().uuidString)"
                let initialOutputTimeout = params.timeout > 0 ? params.timeout : Int(config.backgroundStartupSeconds)
                Logger.log(level: .debug, "[AppleTerminalControl] Capturing initial output for background command from \\(effectiveLogFilePath) for \\(initialOutputTimeout)s.")

                let tailResult = ProcessUtilities.tailLogFileForMarker(
                    logFilePath: effectiveLogFilePath,
                    marker: uniqueNonMarker, // This marker will (should) not be found
                    timeoutSeconds: initialOutputTimeout,
                    linesToCapture: params.linesToCapture,
                    controlIdentifier: "AppleTerminalBGInitialOutput"
                )
                
                if !tailResult.output.isEmpty {
                    outputText += "\n--- INITIAL OUTPUT (up to \\(params.linesToCapture) lines) ---\n" + tailResult.output.replacingOccurrences(of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
                }
                if tailResult.timedOut {
                     Logger.log(level: .debug, "[AppleTerminalControl] Background initial output capture period ended for \\(effectiveLogFilePath).")
                } // We expect this to timeout for marker finding

                // For background, session is presumed busy until command finishes
                finalSessionIsBusy = true // Or re-check with ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty) if more accuracy is needed immediately
            } else {
                 // This case should ideally not be hit if 'OK_SUBMITTED_FG' handles foreground.
                 // If it's a foreground command but status is not OK_SUBMITTED_FG, TIMEOUT, or ERROR, it's an unexpected script status.
                Logger.log(level: .warn, "[AppleTerminalControl] Unexpected AppleScript status '\\(scriptResponse.status)' for command on tag \\(params.tag). Log: \\(effectiveLogFilePath)")
                outputText = "Unexpected script response status: \\(scriptResponse.status). Message: \\(scriptResponse.message ?? "N/A"). Log: \\(effectiveLogFilePath)"
                // Attempt to read the log file as a fallback, as we don't know the command state
                if FileManager.default.fileExists(atPath: effectiveLogFilePath) {
                     let tailResult = ProcessUtilities.tailLogFileForMarker(
                        logFilePath: effectiveLogFilePath,
                        marker: completionMarker, // Attempt to find marker anyway
                        timeoutSeconds: 2, // Short timeout for this unexpected case
                        linesToCapture: params.linesToCapture,
                        controlIdentifier: "AppleTerminalUnexpected"
                    )
                    outputText += "\\n--- FALLBACK LOG CONTENT ---\\n" + tailResult.output
                    wasKilledByTimeout = tailResult.timedOut // It might have timed out here
                    if !tailResult.timedOut { 
                        // If marker was found, implies foreground command might have finished. Clean up.
                        if params.command != nil && !params.command!.isEmpty {
                            _ = try? FileManager.default.removeItem(atPath: effectiveLogFilePath)
                        }
                    }
                }
                finalSessionIsBusy = ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty) // Re-check
            }
        }

        // Update session info with potentially new busy status
        let updatedSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle, // Title doesn't change here
            tty: sessionInfo.tty,
            isBusy: finalSessionIsBusy,
            windowIdentifier: sessionInfo.windowIdentifier,
            tabIdentifier: sessionInfo.tabIdentifier,
            pidFromTitle: sessionInfo.pidFromTitle,
            ttyFromTitle: sessionInfo.ttyFromTitle
        )

        return ExecuteCommandResult(
            sessionInfo: updatedSessionInfo,
            output: outputText.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: nil, // Exit code not reliably available for Apple Terminal via script
            pid: finalPid,
            wasKilledByTimeout: wasKilledByTimeout
        )
    }
    
    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Reading session output for tag: \(params.tag), project: \(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "Session found for reading is missing tabID or windowID. Session: \(sessionInfo)")
        }
        
        let script = AppleTerminalScripts.readSessionOutputScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        )
        // Logger.log(level: .debug, "AppleScript for readSessionOutput (Apple Terminal):\n\(script)") // Script content now in AppleTerminalScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            return try AppleTerminalParser.parseReadSessionOutput(resultData: resultData, scriptContent: script, sessionInfo: sessionInfo, linesToRead: params.linesToRead)

        case .failure(let error):
            let errorMsg = "Failed to read session output for tag '\(params.tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Focusing session for tag: \(params.tag), project: \(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "Session found for focus is missing tabID or windowID. Session: \(sessionInfo)")
        }

        let script = AppleTerminalScripts.focusSessionScript(appName: self.appName, windowID: windowID, tabID: tabID)
        // Logger.log(level: .debug, "AppleScript for focusSession (Apple Terminal):\n\(script)")

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            Logger.log(level: .info, "Successfully focused session for tag: \(params.tag). AppleScript result: \(resultData)")
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case .failure(let error):
            let errorMsg = "Failed to focus session for tag '\(params.tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[AppleTerminalControl] Killing process in session for tag: \(params.tag), project: \(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
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
            }
            if let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier { // Re-check for safety
                let ctrlCScript = AppleTerminalScripts.sendControlCScript(
                    appName: self.appName,
                    windowID: windowID,
                    tabID: tabID,
                    shouldActivateTerminal: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false) // Activate if focus desired
                )
                let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)
                switch ctrlCResult {
                case .success(let strResult):
                    if let resultStr = strResult as? String, resultStr == "OK_CTRL_C_SENT" {
                        message += " Sent Ctrl+C to session as fallback."
                        Logger.log(level: .info, "[AppleTerminalControl] Successfully sent Ctrl+C to session \(params.tag).")
                        killSuccess = true // Mark as success because the action was performed.
                    } else {
                        message += " Failed to send Ctrl+C to session. AppleScript result: \(strResult ?? "empty")."
                        Logger.log(level: .warn, "[AppleTerminalControl] Failed to send Ctrl+C to session \(params.tag). Result: \(strResult ?? "empty").")
                        // killSuccess remains as it was
                    }
                case .failure(let error):
                    message += " Failed to send Ctrl+C to session: \(error.localizedDescription)."
                    Logger.log(level: .warn, "[AppleTerminalControl] Error sending Ctrl+C to session \(params.tag): \(error.localizedDescription).")
                    // killSuccess remains as it was
                }
            }
        } else if config.preKillScriptPath != nil {
            Logger.log(level: .debug, "[AppleTerminalControl] Pre-kill script was configured for \(params.tag). Ctrl+C fallback was skipped or conditions not met.")
        } else if killSuccess {
             Logger.log(level: .debug, "[AppleTerminalControl] Graceful kill succeeded or no process found. Ctrl+C fallback skipped for \(params.tag).")
        }

        // Clear the session screen after all kill attempts
        if let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier {
            Self._clearSessionScreen(
                appName: self.appName, 
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
        if case .failure(let error) = clearScriptResult {
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
                    let pidStr = parts[1]
                    Logger.log(level: .debug, "Foreground PID in group also identified as: \(pidStr) for TTY \(tty) session \(tag).")
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

    private func findOrCreateSessionForAppleTerminal(projectPath: String?, tag: String, commandToExecute: String? = nil, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .debug, "[AppleTerminalControl] Finding or creating session for tag: \(tag), project: \(projectPath ?? "N/A")")

        // 1. Try to find existing session
        if let existingSession = _findExistingSession(projectPath: projectPath, tag: tag, focusPreference: focusPreference) {
            return existingSession
        }

        // 2. If not found, create a new one.
        return try _createNewSession(projectPath: projectPath, tag: tag, focusPreference: focusPreference)
    }

    private func _findExistingSession(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) -> TerminalSessionInfo? {
        Logger.log(level: .debug, "[AppleTerminalControl] Attempting to find existing session for tag: \(tag), project: \(projectPath ?? "N/A")")
        do {
            let existingSessions = try self.listSessions(filterByTag: tag)
            let targetProjectHash = projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: projectPath) : "NO_PROJECT"

            for session in existingSessions {
                let sessionProjectHash = session.projectPath ?? "NO_PROJECT" // listSessions stores the hash in projectPath
                if sessionProjectHash == targetProjectHash {
                    if !session.isBusy || config.reuseBusySessions {
                        Logger.log(level: .info, "Found suitable existing session for tag '\(tag)' (Project: \(projectPath ?? "Global"), TTY: \(session.tty ?? "N/A")). Reusing.")
                        // BEGIN FOCUS HANDLING FOR EXISTING SESSION
                        if attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                            Logger.log(level: .debug, "Focus preference requires focusing existing session.")
                            guard let existingTabID = session.tabIdentifier, let existingWindowID = session.windowIdentifier else {
                                Logger.log(level: .warn, "Cannot focus existing session for tag '\(tag)' due to missing identifiers.")
                                return session // Return session without focusing if IDs are missing
                            }
                            let focusScript = AppleTerminalScripts.focusExistingSessionScript(appName: self.appName, windowID: existingWindowID, tabID: existingTabID)
                            let focusResult = AppleScriptBridge.runAppleScript(script: focusScript)
                            switch focusResult {
                            case .success:
                                Logger.log(level: .info, "Successfully focused existing session: \(session.sessionIdentifier)")
                            case .failure(let err):
                                Logger.log(level: .warn, "Failed to focus existing session \(session.sessionIdentifier): \(err.localizedDescription)")
                                // Continue without throwing; session is still valid, just not focused.
                            }
                        }
                        // END FOCUS HANDLING FOR EXISTING SESSION
                        return session
                    } else {
                        Logger.log(level: .info, "Found existing session for tag '\(tag)' (Project: \(projectPath ?? "Global")) but it's busy and reuseBusySessions is false. TTY: \(session.tty ?? "N/A")")
                    }
                }
            }
        } catch {
            Logger.log(level: .warn, "Error listing sessions while trying to find existing session for tag '\(tag)': \(error.localizedDescription). This is not fatal if we can create a new one.")
        }
        Logger.log(level: .debug, "[AppleTerminalControl] No suitable existing session found for tag: \(tag), project: \(projectPath ?? "N/A")")
        return nil
    }

    private func _createNewSession(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .info, "[AppleTerminalControl] Creating new session for tag: \(tag), project: \(projectPath ?? "N/A")")
        
        let newSessionTitle = SessionUtilities.generateSessionTitle(projectPath: projectPath, tag: tag)
        let shouldActivateTerminal = attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        let projectHashForGrouping = projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: projectPath) : nil

        let script = AppleTerminalScripts.findOrCreateSessionScript(
            appName: self.appName,
            newSessionTitle: newSessionTitle,
            shouldActivateTerminal: shouldActivateTerminal,
            windowGroupingStrategy: config.windowGrouping.rawValue, // Pass the rawValue of the enum
            projectPathForGrouping: projectPath,
            projectHashForGrouping: projectHashForGrouping
        )

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            return try AppleTerminalParser.parseCreateNewSessionOutput(resultData: resultData, scriptContent: script, projectPath: projectPath, tag: tag)
            
        case .failure(let error):
            let errorMsg = "Failed to create or find session for tag '\(tag)': \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }

    private func attentesFocus(focusPreference: AppConfig.FocusCLIArgument, defaultFocusSetting: Bool) -> Bool {
        switch focusPreference {
        case .forceFocus:
            return true
        case .noFocus:
            return false
        case .default:
            return defaultFocusSetting
        }
    }
} 