import Foundation

struct ITermControl: TerminalControlling {
    let config: AppConfig
    let appName: String // Should be "iTerm", "iTerm.app", "iTerm2", etc.

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .debug, "ITermControl initialized for app: \(appName)")
    }

    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .info, "[ITermControl] Listing sessions, filter: \(filterByTag ?? "N/A")")
        
        let script = ITermScripts.listSessionsScript(appName: self.appName)
        // Logger.log(level: .debug, "AppleScript for listSessions (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultStringOrArray):
            Logger.log(level: .debug, "AppleScript result for iTerm listing: \\(resultStringOrArray)")
            return try ITermParser.parseListSessionsOutput(resultData: resultStringOrArray, scriptContent: script, filterByTag: filterByTag)
            
        case .failure(let error):
            Logger.log(level: .error, "Failed to list sessions for iTerm: \\(error.localizedDescription)")
            throw TerminalControllerError.appleScriptError(message: "Listing iTerm sessions failed: \\(error.localizedDescription)", scriptContent: script, underlyingError: error)
        }
    }
    
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[ITermControl] Attempting to execute command for tag: \\(params.tag), project: \\(params.projectPath ?? "N/A")")

        let sessionToUse = try findOrCreateSessionForITerm(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference // Initial focus applied here
        )

        guard let tabID = sessionToUse.tabIdentifier, 
              let windowID = sessionToUse.windowIdentifier, 
              let tty = sessionToUse.tty else {
            throw TerminalControllerError.internalError(details: "Found/created iTerm session is missing critical identifiers (tabID, windowID, or tty). Session: \\(sessionToUse)")
        }
        
        // Clear the session screen before any command execution
        Self._clearSessionScreen(appName: self.appName, windowID: windowID, tabID: tabID, sessionID: sessionToUse.iTermSessionID, tag: params.tag)
        
        // SDD 3.2.5: Pre-execution Step: Busy Check & Stop
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid
            let foundCommand = processInfo.command
            
            Logger.log(level: .info, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) is busy with command '\\(foundCommand)' (PGID: \\(foundPgid)). Attempting to interrupt.")
            
            // Send SIGINT to the process group
            ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(level: .debug, "[ITermControl] Sent SIGINT to PGID \\(foundPgid) on TTY \\(tty).")
            
            // Wait for 3 seconds
            Thread.sleep(forTimeInterval: 3.0)
            
            // Check if TTY is still busy
            if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                Logger.log(level: .error, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) remained busy with command '\\(stillBusyInfo.command)' after interrupt attempt.")
                throw TerminalControllerError.sessionBusyError(
                    message: "Session for tag \\(params.tag) (TTY: \\(tty)) remained busy with command '\\(stillBusyInfo.command)' after interrupt attempt.",
                    suggestedErrorCode: ErrorCodes.sessionBusyError
                )
            } else {
                Logger.log(level: .info, "[ITermControl] Process on TTY \\(tty) was successfully interrupted.")
            }
        }
        // End of Busy Check

        // Handle session preparation if command is nil or empty (SDD 3.1.5, 3.2.5)
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(level: .info, "[ITermControl] No command provided. Preparing session (focus) for tag: \\(params.tag)")
            
            // Ensure focus (findOrCreateSession already handled initial focus, this re-confirms if needed)
            // If clearScreen changed focus, or if initial focus was no-op due to focusPreference
            if attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                let focusScript = ITermScripts.focusSessionScript(appName: self.appName, windowID: windowID, tabID: tabID)
                _ = AppleScriptBridge.runAppleScript(script: focusScript) // Best effort focus
            }
            
            return ExecuteCommandResult(
                sessionInfo: sessionToUse, // sessionInfo from findOrCreate
                output: "", // No command output
                exitCode: 0, // Success for prep
                pid: nil,
                wasKilledByTimeout: false
            )
        }
        
        // Command execution with file-based output logging (SDD 3.2.5)
        let commandToExecute = params.command! // Now we know command is not nil
        let trimmedCommandToExecute = commandToExecute.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create log file path for output capture
        let ttyBasename = (tty as NSString).lastPathComponent
        let timestamp = Int(Date().timeIntervalSince1970)
        let logFileName = "terminator_output_\\(ttyBasename)_\\(timestamp).log"
        let logFilePathURL = config.logDir.appendingPathComponent("cli_command_outputs").appendingPathComponent(logFileName)
        
        // Ensure log directory exists
        do {
            try FileManager.default.createDirectory(at: logFilePathURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.log(level: .error, "[ITermControl] Could not create directory for command output logs: \\(error.localizedDescription)")
            throw TerminalControllerError.internalError(details: "Failed to create output log directory: \\(error.localizedDescription)")
        }
        
        let completionMarker = "TERMINATOR_CMD_DONE_\\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground
        let shouldActivateITermForCommand = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.executeCommandScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID,
            commandToRunRaw: trimmedCommandToExecute,
            outputLogFilePath: logFilePathURL.path,
            completionMarker: completionMarker,
            isForeground: isForeground,
            shouldActivateITerm: shouldActivateITermForCommand
        )

        Logger.log(level: .debug, "[ITermControl] Executing command with log file: \\(logFilePathURL.path)")
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            return try _processExecuteCommandWithFileLogging(
                resultData: resultData,
                scriptContent: script,
                sessionInfo: sessionToUse,
                params: params,
                commandToExecute: trimmedCommandToExecute,
                logFilePath: logFilePathURL.path,
                completionMarker: completionMarker
            )
        case .failure(let error):
            let errorMsg = "Failed to execute iTerm command for tag \\(params.tag): \\(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    private func _processExecuteCommandWithFileLogging(
        resultData: Any,
        scriptContent: String,
        sessionInfo: TerminalSessionInfo,
        params: ExecuteCommandParams,
        commandToExecute: String,
        logFilePath: String,
        completionMarker: String
    ) throws -> ExecuteCommandResult {
        // Parse AppleScript result
        guard let resultArray = resultData as? [String], resultArray.count >= 2 else {
            let errorMsg = "iTerm AppleScript for execute did not return expected format. Result: \\(resultData)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        
        let status = resultArray[0]
        let message = resultArray[1]
        let pidString = resultArray.count >= 3 ? resultArray[2] : ""
        
        // Handle AppleScript errors
        if status == "ERROR" {
            Logger.log(level: .error, "[ITermControl] iTerm execute command AppleScript reported error: \\(message)")
            throw TerminalControllerError.appleScriptError(message: "iTerm execute script error: \\(message)", scriptContent: scriptContent)
        }
        
        var output = ""
        var exitCode: Int? = nil
        var pid: pid_t? = nil
        var wasKilledByTimeout = false
        
        if !pidString.isEmpty, let parsedPID = pid_t(pidString) {
            pid = parsedPID
        }
        
        let isForeground = params.executionMode == .foreground
        let timeoutSeconds = isForeground ? params.timeout : Int(config.backgroundStartupSeconds)
        
        if isForeground {
            // Tail log file for completion marker
            Logger.log(level: .debug, "[ITermControl] Tailing log file \\(logFilePath) for completion marker with timeout \\(timeoutSeconds)s")
            
            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: completionMarker,
                timeoutSeconds: timeoutSeconds,
                linesToCapture: params.linesToCapture,
                controlIdentifier: "ITermFG-\\(params.tag)"
            )
            
            output = tailResult.output
            wasKilledByTimeout = tailResult.timedOut
            
            if wasKilledByTimeout {
                Logger.log(level: .warn, "[ITermControl] Command timed out for tag \\(params.tag) after \\(timeoutSeconds)s")
                output = "Command timed out after \\(params.timeout) seconds (iTerm)."
                
                // Attempt to kill the process group if we have the TTY
                if let tty = sessionInfo.tty {
                    let ttyNameOnly = (tty as NSString).lastPathComponent
                    let pgidFindScript = ITermScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
                    let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)
                    
                    if case .success(let resultStringOrArray) = pgidFindResult {
                        let parseResult = _parsePgidFromResult(resultStringOrArray: resultStringOrArray, tty: tty, tag: params.tag)
                        if let pgid = parseResult.pgid {
                            Logger.log(level: .info, "[ITermControl] Attempting to kill timed-out process group \\(pgid)")
                            var killMessage = ""
                            _ = ProcessUtilities.attemptGracefulKill(pgid: pgid, config: config, message: &killMessage)
                            Logger.log(level: .debug, "[ITermControl] Kill attempt result: \\(killMessage)")
                        }
                    }
                }
            } else {
                // Remove completion marker from output if found
                output = output.replacingOccurrences(of: completionMarker, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                exitCode = 0 // Success if marker was found
            }
        } else {
            // Background command - capture initial output
            Logger.log(level: .info, "[ITermControl] Background command submitted for tag \\(params.tag). Capturing initial output from \\(logFilePath)")
            
            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: "TERMINATOR_ITERM_BG_NONEXISTENT_MARKER_\\(UUID().uuidString)", // Won't find this
                timeoutSeconds: timeoutSeconds,
                linesToCapture: params.linesToCapture,
                controlIdentifier: "ITermBG-\\(params.tag)"
            )
            
            output = tailResult.output.replacingOccurrences(of: "\\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
            if output.isEmpty {
                output = "Background command submitted. PID: \\(pid ?? -1)"
            }
        }
        
        // Clean up log file after successful foreground completion
        if isForeground && !wasKilledByTimeout && FileManager.default.fileExists(atPath: logFilePath) {
            do {
                try FileManager.default.removeItem(atPath: logFilePath)
                Logger.log(level: .debug, "[ITermControl] Removed log file after successful completion: \\(logFilePath)")
            } catch {
                Logger.log(level: .debug, "[ITermControl] Failed to remove log file \\(logFilePath): \\(error.localizedDescription)")
            }
        }
        
        // Update session info with current busy status
        let finalSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle,
            tty: sessionInfo.tty,
            isBusy: params.executionMode == .background ? ProcessUtilities.getTTYBusyStatus(sessionInfo.tty ?? "") : false,
            windowIdentifier: sessionInfo.windowIdentifier,
            tabIdentifier: sessionInfo.tabIdentifier
        )
        
        return ExecuteCommandResult(
            sessionInfo: finalSessionInfo,
            output: output,
            exitCode: exitCode,
            pid: pid,
            wasKilledByTimeout: wasKilledByTimeout
        )
    }
    
    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .info, "[ITermControl] Reading session output for tag: \\(params.tag), project: \\(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, 
              let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "iTerm session found for reading is missing tabID or windowID. Session: \\(sessionInfo)")
        }
        
        let shouldActivateITermForRead = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.readSessionOutputScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateITerm: shouldActivateITermForRead
        )
        // Logger.log(level: .debug, "AppleScript for readSessionOutput (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            return try ITermParser.parseReadSessionOutput(resultData: resultData, scriptContent: script, linesToRead: params.linesToRead)

        case .failure(let error):
            let errorMsg = "Failed to read iTerm session output for tag \(params.tag): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[ITermControl] Focusing session for tag: \\(params.tag), project: \\(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tabID = sessionInfo.tabIdentifier, 
              let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "iTerm session found for focus is missing tabID or windowID. Session: \\(sessionInfo)")
        }

        let script = ITermScripts.focusSessionScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID
        )
        // Logger.log(level: .debug, "AppleScript for focusSession (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            Logger.log(level: .info, "Successfully focused iTerm session for tag: \\(params.tag). AppleScript result: \\(resultData)")
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case .failure(let error):
            let errorMsg = "Failed to focus iTerm session for tag '\\(params.tag)': \\(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[ITermControl] Killing process in session for tag: \\(params.tag), project: \\(params.projectPath ?? "N/A")")

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let tty = sessionInfo.tty, !tty.isEmpty else {
            Logger.log(level: .warn, "iTerm session \\(params.tag) found but has no TTY. Cannot kill process.")
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
        Logger.log(level: .debug, "[ITermControl] Executing PGID find script for iTerm: \\(pgidFindScript)")
        
        let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)

        switch pgidFindResult {
        case .success(let resultStringOrArray):
            let parseResult = _parsePgidFromResult(resultStringOrArray: resultStringOrArray, tty: tty, tag: params.tag)
            pgidToKill = parseResult.pgid
            message += parseResult.message
            if parseResult.shouldReturnEarly && config.preKillScriptPath == nil { // If no pgid and no pre-kill script, consider Ctrl+C
                // Fall through to Ctrl+C logic if pgidToKill is still nil
            } else if parseResult.shouldReturnEarly {
                 return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: true, message: message + " (No process found via ps)")
            }

        case .failure(let error):
            message += " Failed to query processes on TTY \\(tty) for iTerm session: \\(error.localizedDescription)."
            Logger.log(level: .error, "[ITermControl] Failed to run ps to find PGID on TTY \\(tty) for iTerm: \\(error.localizedDescription)")
            // Fall through to Ctrl+C logic if no pre-kill script defined
            if config.preKillScriptPath != nil {
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: message)
            }
        }

        // 3. Attempt graceful kill if PGID was found
        if let currentPgid = pgidToKill, currentPgid > 0 {
            killSuccess = ProcessUtilities.attemptGracefulKill(pgid: currentPgid, config: config, message: &message)
            if killSuccess {
                 Logger.log(level: .info, "[ITermControl] Graceful kill successful for PGID \\(currentPgid) in iTerm session \\(params.tag).")
                 return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: true, message: message)
            }
            message += " Graceful kill attempt for PGID \\(currentPgid) failed or process persisted."
            Logger.log(level: .warn, "[ITermControl] Graceful kill failed or process persisted for PGID \\(currentPgid) in iTerm session \\(params.tag).")
        }
        
        // 4. Ctrl+C Fallback (SDD 3.2.5)
        // Condition: No pre-kill script defined AND (PGID not found OR graceful kill failed/process persisted)
        if config.preKillScriptPath == nil && (pgidToKill == nil || !killSuccess) {
            Logger.log(level: .info, "[ITermControl] PGID not found or graceful kill failed for iTerm session \\(params.tag). Attempting Ctrl+C fallback.")
            guard let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier else {
                message += " Cannot attempt Ctrl+C: session missing window/tab identifiers."
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: message)
            }
            
            let ctrlCScript = ITermScripts.sendControlCScript(
                appName: self.appName,
                windowID: windowID,
                tabID: tabID,
                shouldActivateITerm: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false) // Activate if focus desired
            )
            let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)
            switch ctrlCResult {
            case .success(let strResult):
                if let resultStr = strResult as? String, resultStr == "OK_CTRL_C_SENT" {
                    message += " Sent Ctrl+C to iTerm session as fallback."
                    Logger.log(level: .info, "[ITermControl] Successfully sent Ctrl+C to iTerm session \\(params.tag).")
                    // We can't easily confirm kill success from Ctrl+C, so assume it was delivered.
                    // The next status check or operation will reveal if it's still busy.
                    killSuccess = true // Mark as success because the action was performed.
                } else {
                    message += " Failed to send Ctrl+C to iTerm session. AppleScript result: \\(strResult ?? "empty")."
                    Logger.log(level: .warn, "[ITermControl] Failed to send Ctrl+C to iTerm session \\(params.tag). Result: \\(strResult ?? "empty").")
                    killSuccess = false
                }
            case .failure(let error):
                message += " Failed to send Ctrl+C to iTerm session: \\(error.localizedDescription)."
                Logger.log(level: .warn, "[ITermControl] Error sending Ctrl+C to iTerm session \\(params.tag): \\(error.localizedDescription).")
                killSuccess = false
            }
        } else if config.preKillScriptPath == nil && pgidToKill != nil && killSuccess {
             // This case is when graceful kill succeeded and there was no pre-kill script, so no fallback needed.
        } else if config.preKillScriptPath != nil {
            // If pre-kill script was run, its success/failure (or the subsequent graceful kill) is the final state.
            // No Ctrl+C fallback in this path according to spec logic.
            Logger.log(level: .debug, "[ITermControl] Pre-kill script was configured for \\(params.tag). Ctrl+C fallback skipped.")
        }
        
        // Clear the session screen after all kill attempts
        if let windowID = sessionInfo.windowIdentifier, let tabID = sessionInfo.tabIdentifier {
            Self._clearSessionScreen(appName: self.appName, windowID: windowID, tabID: tabID, sessionID: sessionInfo.iTermSessionID, tag: params.tag)
        }

        return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: killSuccess, message: message)
    }
    
    // MARK: - Private Helper Methods for iTerm
    private func findOrCreateSessionForITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .debug, "[ITermControl] Finding or creating session for tag: \(tag), project: \(projectPath ?? "N/A")")

        // 1. Try to find existing session
        if let existingSession = _findExistingSessionITerm(projectPath: projectPath, tag: tag, focusPreference: focusPreference) {
            return existingSession
        }
        
        // 2. If not found, create a new one.
        return try _createNewSessionITerm(projectPath: projectPath, tag: tag, focusPreference: focusPreference)
    }

    private func _findExistingSessionITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) -> TerminalSessionInfo? {
        Logger.log(level: .debug, "[ITermControl] Attempting to find existing iTerm session for tag: \(tag), project: \(projectPath ?? "N/A")")
        do {
            let existingSessions = try self.listSessions(filterByTag: tag)
            let targetProjectHash = projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: projectPath) : "NO_PROJECT"

            for session in existingSessions {
                let sessionProjectHash = session.projectPath ?? "NO_PROJECT"
                if sessionProjectHash == targetProjectHash {
                    if !session.isBusy || config.reuseBusySessions {
                        Logger.log(level: .info, "Found suitable existing iTerm session for tag '\(tag)' (Project: \(projectPath ?? "Global"), TTY: \(session.tty ?? "N/A")). Reusing.")
                        
                        if attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                            Logger.log(level: .debug, "Focus preference requires focusing existing iTerm session.")
                            guard let existingTabID = session.tabIdentifier, let existingWindowID = session.windowIdentifier else {
                                Logger.log(level: .warn, "Cannot focus existing iTerm session for tag '\(tag)' due to missing identifiers.")
                                return session // Return session without focusing if IDs are missing
                            }
                            let focusScript = ITermScripts.focusSessionScript(
                                appName: self.appName,
                                windowID: existingWindowID,
                                tabID: existingTabID
                            )
                            Logger.log(level: .debug, "Executing focus script for existing iTerm session: \\n\(focusScript)")
                            let focusResult = AppleScriptBridge.runAppleScript(script: focusScript)
                            switch focusResult {
                            case .success:
                                Logger.log(level: .info, "Successfully focused existing iTerm session: \(session.sessionIdentifier)")
                            case .failure(let err):
                                Logger.log(level: .warn, "Failed to focus existing iTerm session \(session.sessionIdentifier): \(err.localizedDescription)")
                            }
                        }
                        return session
                    } else {
                        Logger.log(level: .info, "Found existing iTerm session for tag '\(tag)' (Project: \(projectPath ?? "Global")) but it's busy and reuseBusySessions is false. TTY: \(session.tty ?? "N/A")")
                    }
                }
            }
        } catch {
            Logger.log(level: .warn, "Error listing iTerm sessions while trying to find existing session for tag '\(tag)': \(error.localizedDescription). This is not fatal if new one can be created.")
        }
        Logger.log(level: .debug, "[ITermControl] No suitable existing iTerm session found for tag: \(tag), project: \(projectPath ?? "N/A")")
        return nil
    }

    private func _createNewSessionITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .debug, "[ITermControl] Creating new iTerm session for tag: \(tag), project: \(projectPath ?? "N/A")")
        
        let projectHashForTitle = SessionUtilities.getProjectHashForTitle(projectPath: projectPath, config: config)
        let customTitle = SessionUtilities.generateSessionTitle(projectPath: projectPath, tag: tag, ttyDevicePath: nil, processId: nil)
        let shouldActivate = attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        
        // For iTerm, a command is typically run *after* session creation, not during the initial AppleScript typically.
        // However, if a setup command is absolutely needed, it would be passed here.
        // For now, assuming no initial command during creation via this path.
        let script = ITermScripts.createNewSessionScript(
            appName: self.appName,
            projectPath: projectPath, // Pass for potential future use in script logic
            tag: tag,
            commandToRunEscaped: nil, // No command during creation script for iTerm in this model
            customTitle: customTitle,
            shouldActivateITerm: shouldActivate
        )

        Logger.log(level: .debug, "AppleScript for _createNewSessionITerm:\n\(script)")
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultString):
            return try ITermParser.parseCreateNewSessionITermOutput(resultString, scriptContent: script, projectPathProvided: projectPath, tag: tag, customTitle: customTitle)
        case .failure(let error):
            let errorMsg = "Failed to create new iTerm session for tag '\\(tag)'. Error: \\(error.localizedDescription)"
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
        case .autoBehavior:
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
                Logger.log(level: .info, "Identified PGID \\(foundPgid) on TTY \\(tty) for iTerm session \\(tag).")
            } else {
                message += " Could not parse PGID from ps output: '\\(resultString)'."
                Logger.log(level: .warn, "Could not parse PGID from output: '\\(resultString)' for iTerm TTY \\(tty).")
            }
        } else {
            message += " No foreground process found on TTY \\(tty) in iTerm session to kill."
            Logger.log(level: .info, "No foreground process found on TTY \\(tty) for iTerm session \\(tag). Assuming success.")
            shouldReturnEarly = true // Indicate that we should return early from the calling function
        }
        return (pgidToKill, message, shouldReturnEarly)
    }
    
    private static func _clearSessionScreen(appName: String, windowID: String, tabID: String, sessionID: String?, tag: String) {
        let clearScript = ITermScripts.clearSessionScript(appName: appName, windowID: windowID, tabID: tabID, sessionID: sessionID)
        let clearScriptResult = AppleScriptBridge.runAppleScript(script: clearScript)
        if case .failure(let error) = clearScriptResult {
            Logger.log(level: .warn, "[ITermControl] Failed to clear iTerm session for tag \\(tag): \\(error.localizedDescription)")
        }
    }
} 