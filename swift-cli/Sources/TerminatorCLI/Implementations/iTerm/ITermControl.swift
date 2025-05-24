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
        
        let script = ITermScripts.listSessionsScript(appName: self.appName)
        // Logger.log(level: .debug, "AppleScript for listSessions (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultStringOrArray):
            Logger.log(level: .debug, "AppleScript result for iTerm listing: \\(resultStringOrArray)", file: #file, function: #function)
            return try ITermParser.parseListSessionsOutput(resultData: resultStringOrArray, scriptContent: script, filterByTag: filterByTag)
            
        case .failure(let error):
            Logger.log(level: .error, "Failed to list sessions for iTerm: \\(error.localizedDescription)", file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: "Listing iTerm sessions failed: \\(error.localizedDescription)", scriptContent: script, underlyingError: error)
        }
    }
    
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[ITermControl] Attempting to execute command for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let sessionToUse = try findOrCreateSessionForITerm(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference // Initial focus applied here
        )

        guard let compositeTabID = sessionToUse.tabIdentifier,
              let tabID = Self.extractTabID(from: compositeTabID),
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let windowID = sessionToUse.windowIdentifier, 
              let tty = sessionToUse.tty else {
            throw TerminalControllerError.internalError(details: "Found/created iTerm session is missing critical identifiers (tabID, sessionID, windowID, or tty). Session: \\(sessionToUse)")
        }
        
        // Clear the session screen before any command execution
        Self._clearSessionScreen(appName: self.appName, sessionID: sessionID, tag: params.tag)
        
        // SDD 3.2.5: Pre-execution Step: Busy Check & Stop
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid
            let _ = processInfo.command
            
            Logger.log(level: .info, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) is busy with command '\\(foundCommand)' (PGID: \\(foundPgid)). Attempting to interrupt.", file: #file, function: #function)
            
            // Send SIGINT to the process group
            _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(level: .debug, "[ITermControl] Sent SIGINT to PGID \\(foundPgid) on TTY \\(tty).", file: #file, function: #function)
            
            // Wait for 3 seconds
            Thread.sleep(forTimeInterval: 3.0)
            
            // Check if TTY is still busy
            if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                Logger.log(level: .error, "[ITermControl] Session TTY \\(tty) for tag \\(params.tag) remained busy with command '\\(stillBusyInfo.command)' after interrupt attempt.", file: #file, function: #function)
                throw TerminalControllerError.busy(tty: tty, processDescription: stillBusyInfo.command)
            } else {
                Logger.log(level: .info, "[ITermControl] Process on TTY \\(tty) was successfully interrupted.", file: #file, function: #function)
            }
        }
        // End of Busy Check

        // Handle session preparation if command is nil or empty (SDD 3.1.5, 3.2.5)
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(level: .info, "[ITermControl] No command provided. Preparing session (focus) for tag: \\(params.tag)", file: #file, function: #function)
            
            // Ensure focus (findOrCreateSession already handled initial focus, this re-confirms if needed)
            // If clearScreen changed focus, or if initial focus was no-op due to focusPreference
            if attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                let focusScript = ITermScripts.focusSessionScript(appName: self.appName, windowID: windowID, tabID: tabID, sessionID: sessionID)
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
        let _ = (tty as NSString).lastPathComponent
        let _ = Int(Date().timeIntervalSince1970)
        let logFileName = "terminator_output_\\(ttyBasename)_\\(timestamp).log"
        let logFilePathURL = config.logDir.appendingPathComponent("cli_command_outputs").appendingPathComponent(logFileName)
        
        // Ensure log directory exists
        do {
            try FileManager.default.createDirectory(at: logFilePathURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.log(level: .error, "[ITermControl] Could not create directory for command output logs: \\(error.localizedDescription)", file: #file, function: #function)
            throw TerminalControllerError.internalError(details: "Failed to create output log directory: \\(error.localizedDescription)")
        }
        
        let completionMarker = "TERMINATOR_CMD_DONE_\\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground
        let shouldActivateITermForCommand = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.executeCommandScript(
            appName: self.appName,
            sessionID: sessionID,
            commandToRunRaw: trimmedCommandToExecute,
            outputLogFilePath: logFilePathURL.path,
            completionMarker: completionMarker,
            isForeground: isForeground,
            shouldActivateITerm: shouldActivateITermForCommand
        )

        Logger.log(level: .debug, "[ITermControl] Executing command with log file: \\(logFilePathURL.path)", file: #file, function: #function)
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
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
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
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        
        let status = resultArray[0]
        let _ = resultArray[1]
        let pidString = resultArray.count >= 3 ? resultArray[2] : ""
        
        // Handle AppleScript errors
        if status == "ERROR" {
            Logger.log(level: .error, "[ITermControl] iTerm execute command AppleScript reported error: \\(message)", file: #file, function: #function)
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
            Logger.log(level: .debug, "[ITermControl] Tailing log file \\(logFilePath) for completion marker with timeout \\(timeoutSeconds)s", file: #file, function: #function)
            
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
                Logger.log(level: .warn, "[ITermControl] Command timed out for tag \\(params.tag) after \\(timeoutSeconds)s", file: #file, function: #function)
                output = "Command timed out after \\(params.timeout) seconds (iTerm)."
                
                // Attempt to kill the process group if we have the TTY
                if let tty = sessionInfo.tty {
                    let ttyNameOnly = (tty as NSString).lastPathComponent
                    let pgidFindScript = ITermScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
                    let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)
                    
                    if case .success(let resultStringOrArray) = pgidFindResult {
                        let parseResult = _parsePgidFromResult(resultStringOrArray: resultStringOrArray, tty: tty, tag: params.tag)
                        if let pgid = parseResult.pgid {
                            Logger.log(level: .info, "[ITermControl] Attempting to kill timed-out process group \\(pgid)", file: #file, function: #function)
                            var killMessage = ""
                            _ = ProcessUtilities.attemptGracefulKill(pgid: pgid, config: config, message: &killMessage)
                            Logger.log(level: .debug, "[ITermControl] Kill attempt result: \\(killMessage)", file: #file, function: #function)
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
            Logger.log(level: .info, "[ITermControl] Background command submitted for tag \\(params.tag). Capturing initial output from \\(logFilePath)", file: #file, function: #function)
            
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
                Logger.log(level: .debug, "[ITermControl] Removed log file after successful completion: \\(logFilePath)", file: #file, function: #function)
            } catch {
                Logger.log(level: .debug, "[ITermControl] Failed to remove log file \\(logFilePath): \\(error.localizedDescription)", file: #file, function: #function)
            }
        }
        
        // Update session info with current busy status
        let finalSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle,
            tty: sessionInfo.tty,
            isBusy: params.executionMode == .background ? ProcessUtilities.getTTYBusyStatus(tty: sessionInfo.tty ?? "") : false,
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
        Logger.log(level: .info, "[ITermControl] Reading session output for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let _ = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "iTerm session found for reading is missing sessionID or windowID. Session: \\(sessionInfo)")
        }
        
        let shouldActivateITermForRead = attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: config.defaultFocusOnAction)

        let script = ITermScripts.readSessionOutputScript(
            appName: self.appName,
            sessionID: sessionID,
            linesToRead: params.linesToRead,
            shouldActivateITerm: shouldActivateITermForRead
        )
        // Logger.log(level: .debug, "AppleScript for readSessionOutput (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(let resultData):
            let outputString = try ITermParser.parseReadSessionOutput(resultData: resultData, scriptContent: script, linesToRead: params.linesToRead)
            return ReadSessionResult(sessionInfo: sessionInfo, output: outputString)

        case .failure(let error):
            let errorMsg = "Failed to read iTerm session output for tag \(params.tag): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[ITermControl] Focusing session for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try self.listSessions(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions.first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let tabID = Self.extractTabID(from: compositeTabID),
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let windowID = sessionInfo.windowIdentifier else {
            throw TerminalControllerError.internalError(details: "iTerm session found for focus is missing tabID, sessionID or windowID. Session: \\(sessionInfo)")
        }

        let script = ITermScripts.focusSessionScript(
            appName: self.appName,
            windowID: windowID,
            tabID: tabID,
            sessionID: sessionID
        )
        // Logger.log(level: .debug, "AppleScript for focusSession (iTerm):\\n\(script)") // Script content now in ITermScripts

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case .success(_):
            Logger.log(level: .info, "Successfully focused iTerm session for tag: \\(params.tag).", file: #file, function: #function)
            return FocusSessionResult(focusedSessionInfo: sessionInfo)

        case .failure(let error):
            let errorMsg = "Failed to focus iTerm session for tag '\\(params.tag)': \\(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: script, underlyingError: error)
        }
    }
    
    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[ITermControl] Killing process in session for tag: \\(params.tag), project: \\(params.projectPath ?? \"nil\")", file: #file, function: #function)

        let existingSessions = try self.listSessions(filterByTag: params.tag)
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
        case .success(let resultStringOrArray):
            let parseResult = _parsePgidFromResult(resultStringOrArray: resultStringOrArray, tty: tty, tag: params.tag)
            pgidToKill = parseResult.pgid
            message += parseResult.message
            if parseResult.shouldReturnEarly && config.preKillScriptPath == nil { // If no pgid and no pre-kill script, consider Ctrl+C
                // Fall through to Ctrl+C logic if pgidToKill is still nil
            } else if parseResult.shouldReturnEarly {
                 return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: true, message: message + " (No process found via ps)")
            }

        case .failure(_):
            message += " Failed to query processes on TTY \\(tty) for iTerm session: \\(error.localizedDescription)."
            Logger.log(level: .error, "[ITermControl] Failed to run ps to find PGID on TTY \\(tty) for iTerm: \\(error.localizedDescription)", file: #file, function: #function)
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
                  let sessionID = Self.extractSessionID(from: compositeTabID) else {
                message += " Cannot attempt Ctrl+C: session missing window/sessionID identifiers."
                return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: false, message: message)
            }
            
            let ctrlCScript = ITermScripts.sendControlCScript(
                appName: self.appName,
                sessionID: sessionID,
                shouldActivateITerm: attentesFocus(focusPreference: params.focusPreference, defaultFocusSetting: false) // Activate if focus desired
            )
            let ctrlCResult = AppleScriptBridge.runAppleScript(script: ctrlCScript)
            switch ctrlCResult {
            case .success(let strResult):
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
            case .failure(_):
                message += " Failed to send Ctrl+C to iTerm session: \\(error.localizedDescription)."
                Logger.log(level: .warn, "[ITermControl] Error sending Ctrl+C to iTerm session \\(params.tag): \\(error.localizedDescription).", file: #file, function: #function)
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
           let sessionID = Self.extractSessionID(from: compositeTabID) {
            Self._clearSessionScreen(appName: self.appName, sessionID: sessionID, tag: params.tag)
        }

        return KillSessionResult(killedSessionInfo: sessionInfo, killSuccess: killSuccess, message: message)
    }
    
    // MARK: - Private Helper Methods for iTerm
    private func findOrCreateSessionForITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .debug, "[ITermControl] Finding or creating session for tag: \(tag), project: \(projectPath ?? "nil")", file: #file, function: #function)

        // 1. Try to find existing session
        if let existingSession = _findExistingSessionITerm(projectPath: projectPath, tag: tag, focusPreference: focusPreference) {
            return existingSession
        }
        
        // 2. If not found, create a new one.
        return try _findOrCreateSessionForITerm(projectPath: projectPath, tag: tag, focusPreference: focusPreference)
    }

    private func _findExistingSessionITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) -> TerminalSessionInfo? {
        Logger.log(level: .debug, "[ITermControl] Attempting to find existing iTerm session for tag: \(tag), project: \(projectPath ?? "nil")", file: #file, function: #function)
        do {
            let existingSessions = try self.listSessions(filterByTag: tag)
            let targetProjectHash = projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: projectPath) : "NO_PROJECT"

            for session in existingSessions {
                let sessionProjectHash = session.projectPath ?? "NO_PROJECT"
                if sessionProjectHash == targetProjectHash {
                    if !session.isBusy || config.reuseBusySessions {
                        Logger.log(level: .info, "Found suitable existing iTerm session for tag '\(tag)' (Project: \(projectPath ?? "Global"), TTY: \(session.tty ?? "nil")). Reusing.", file: #file, function: #function)
                        
                        if attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction) {
                            Logger.log(level: .debug, "Focus preference requires focusing existing iTerm session.", file: #file, function: #function)
                            guard let compositeTabID = session.tabIdentifier,
                                  let existingTabID = Self.extractTabID(from: compositeTabID),
                                  let existingSessionID = Self.extractSessionID(from: compositeTabID),
                                  let existingWindowID = session.windowIdentifier else {
                                Logger.log(level: .warn, "Cannot focus existing iTerm session for tag '\(tag)' due to missing identifiers.", file: #file, function: #function)
                                return session // Return session without focusing if IDs are missing
                            }
                            let focusScript = ITermScripts.focusSessionScript(
                                appName: self.appName,
                                windowID: existingWindowID,
                                tabID: existingTabID,
                                sessionID: existingSessionID
                            )
                            Logger.log(level: .debug, "Executing focus script for existing iTerm session: \\n\(focusScript)", file: #file, function: #function)
                            let focusResult = AppleScriptBridge.runAppleScript(script: focusScript)
                            switch focusResult {
                            case .success:
                                Logger.log(level: .info, "Successfully focused existing iTerm session: \(session.sessionIdentifier)", file: #file, function: #function)
                            case .failure(let err):
                                Logger.log(level: .warn, "Failed to focus existing iTerm session \(session.sessionIdentifier): \(err.localizedDescription)", file: #file, function: #function)
                            }
                        }
                        return session
                    } else {
                        Logger.log(level: .info, "Found existing iTerm session for tag '\(tag)' (Project: \(projectPath ?? "Global")) but it's busy and reuseBusySessions is false. TTY: \(session.tty ?? "nil")", file: #file, function: #function)
                    }
                }
            }
        } catch {
            Logger.log(level: .warn, "Error listing iTerm sessions while trying to find existing session for tag '\(tag)': \(error.localizedDescription). This is not fatal if new one can be created.", file: #file, function: #function)
        }
        Logger.log(level: .debug, "[ITermControl] No suitable existing iTerm session found for tag: \(tag), project: \(projectPath ?? "nil")", file: #file, function: #function)
        return nil
    }

    private func _findOrCreateSessionForITerm(projectPath: String?, tag: String, focusPreference: AppConfig.FocusCLIArgument) throws -> TerminalSessionInfo {
        Logger.log(level: .debug, "[ITermControl] Finding or creating session for tag: \(tag), project: \(projectPath ?? "nil")", file: #file, function: #function)
        
        // 1. Determine shouldActivateITerm based on focusPreference
        let shouldActivateITerm = attentesFocus(focusPreference: focusPreference, defaultFocusSetting: config.defaultFocusOnAction)
        
        // 2. Generate projectHashForTitle and customTitle using SessionUtilities
        let projectHash = SessionUtilities.generateProjectHash(projectPath: projectPath)
        let customTitle = SessionUtilities.generateSessionTitle(projectPath: projectPath, tag: tag, ttyDevicePath: nil, processId: nil)
        
        // 3. Implement window/tab creation strategy
        var targetWindowID: String? = nil
        var winID: String? = nil
        var tabID: String? = nil
        var sessionID: String? = nil
        var tty: String? = nil
        
        let groupingStrategy = config.windowGrouping
        
        if groupingStrategy == .project, let projectPath = projectPath {
            // 3a. If grouping is "project", try to find an existing window for that project
            let findWindowScript = ITermScripts.findWindowForProjectScript(appName: self.appName, projectPath: projectPath)
            let findWindowResult = AppleScriptBridge.runAppleScript(script: findWindowScript)
            
            if case .success(let resultData) = findWindowResult {
                // Parse the result - expecting a simple string with window ID or empty
                let resultString = resultData
                if !resultString.isEmpty {
                    targetWindowID = resultString
                    Logger.log(level: .debug, "[ITermControl] Found existing window for project: \(targetWindowID ?? "nil")", file: #file, function: #function)
                }
            }
        } else if groupingStrategy == .smart {
            // 3b. If grouping is "current", get the current window ID
            let getCurrentWindowScript = ITermScripts.getCurrentWindowIDScript(appName: self.appName)
            let getCurrentWindowResult = AppleScriptBridge.runAppleScript(script: getCurrentWindowScript)
            
            if case .success(let resultData) = getCurrentWindowResult {
                let resultString = resultData
                if !resultString.isEmpty {
                    targetWindowID = resultString
                    Logger.log(level: .debug, "[ITermControl] Using current window: \(targetWindowID ?? "nil")", file: #file, function: #function)
                }
            }
        }
        // 3c. If grouping is "new" or no window found/determined, we'll create a new window
        
        // 4. Create session based on whether we have a target window
        if let existingWindowID = targetWindowID {
            // Create a new tab in the existing window
            let createTabScript = ITermScripts.createNewTabInWindowScript(
                appName: self.appName,
                windowID: existingWindowID,
                customTitle: customTitle,
                commandToRunEscaped: nil,
                shouldActivateITerm: shouldActivateITerm
            )
            let createTabResult = AppleScriptBridge.runAppleScript(script: createTabScript)
            
            switch createTabResult {
            case .success(let resultData):
                let tabInfo = try ITermParser.parseNewTabOutput(resultData: resultData, scriptContent: createTabScript)
                winID = existingWindowID
                tabID = tabInfo.tabID
                sessionID = tabInfo.sessionID
                tty = tabInfo.tty
                Logger.log(level: .info, "[ITermControl] Created new tab in existing window. Tab: \(tabID ?? "nil"), Session: \(sessionID ?? "nil"), TTY: \(tty ?? "nil")", file: #file, function: #function)
            case .failure(let error):
                let errorMsg = "Failed to create new tab in iTerm window '\(existingWindowID)' for tag '\(tag)': \(error.localizedDescription)"
                Logger.log(level: .error, errorMsg, file: #file, function: #function)
                throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: createTabScript, underlyingError: error)
            }
        } else {
            // Create a new window with session
            let createWindowScript = ITermScripts.createNewWindowWithSessionScript(
                appName: self.appName,
                customTitle: customTitle,
                commandToRunEscaped: nil,
                shouldActivateITerm: shouldActivateITerm
            )
            let createWindowResult = AppleScriptBridge.runAppleScript(script: createWindowScript)
            
            switch createWindowResult {
            case .success(let resultData):
                let windowInfo = try ITermParser.parseNewWindowOutput(resultData: resultData, scriptContent: createWindowScript)
                winID = windowInfo.winID
                tabID = windowInfo.tabID
                sessionID = windowInfo.sessionID
                tty = windowInfo.tty
                Logger.log(level: .info, "[ITermControl] Created new window. Window: \(winID ?? "nil"), Tab: \(tabID ?? "nil"), Session: \(sessionID ?? "nil"), TTY: \(tty ?? "nil")", file: #file, function: #function)
            case .failure(let error):
                let errorMsg = "Failed to create new iTerm window for tag '\(tag)': \(error.localizedDescription)"
                Logger.log(level: .error, errorMsg, file: #file, function: #function)
                throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: createWindowScript, underlyingError: error)
            }
        }
        
        // 5. Construct TerminalSessionInfo
        let sessionIdentifier = SessionUtilities.generateUserFriendlySessionIdentifier(
            projectPath: projectPath,
            tag: tag
        )
        
        // Store both tabID and sessionID in composite format for iTerm
        let compositeTabIdentifier = "\(tabID ?? ""):\(sessionID ?? "")"
        
        let sessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionIdentifier,
            projectPath: projectHash,
            tag: tag,
            fullTabTitle: customTitle,
            tty: tty,
            isBusy: false, // New session is not busy
            windowIdentifier: winID,
            tabIdentifier: compositeTabIdentifier
        )
        
        // 6. Focus the session if needed
        if shouldActivateITerm, let windowID = winID, let tabID = tabID, let sessionID = sessionID {
            let focusScript = ITermScripts.focusSessionScript(
                appName: self.appName,
                windowID: windowID,
                tabID: tabID,
                sessionID: sessionID
            )
            _ = AppleScriptBridge.runAppleScript(script: focusScript) // Best effort focus
        }
        
        Logger.log(level: .info, "[ITermControl] Successfully created new iTerm session: \(sessionIdentifier)", file: #file, function: #function)
        return sessionInfo
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
        if case .failure(_) = clearScriptResult {
            Logger.log(level: .warn, "[ITermControl] Failed to clear iTerm session for tag \\(tag): \\(error.localizedDescription)", file: #file, function: #function)
        }
    }
} 