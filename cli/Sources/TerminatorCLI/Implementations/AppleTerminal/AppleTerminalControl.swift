import Foundation
@preconcurrency import ApplicationServices

/// Implementation for Apple Terminal that uses Accessibility APIs for UI operations and AppleScript for terminal operations
final class AppleTerminalControl: TerminalControlBase, @unchecked Sendable {
    
    required init(config: AppConfig, appName: String) {
        super.init(config: config, appName: appName)
    }
    
    // MARK: - Terminal.app Specific Accessibility Operations
    
    private func listSessionsViaAccessibilityEnhanced(filterByTag: String?) throws -> [TerminalSessionInfo] {
        let startTime = Date()
        
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        let sessions = try runAsyncBlocking { [self] in
            var allSessions: [TerminalSessionInfo] = []
            
            // Terminal.app specific: windows have a specific structure
            let windows = try await axProvider.findWindows(for: bundleIdentifier)
            
            for (windowIndex, window) in windows.enumerated() {
                // In Terminal.app, tabs are AXRadioButton elements in an AXTabGroup
                let tabs = try await findTerminalTabs(in: window)
                
                for (tabIndex, tab) in tabs.enumerated() {
                    // Get tab title from the associated text area
                    if let title = try await getTerminalTabTitle(tab: tab, window: window) {
                        if let sessionInfo = SessionTitleParser.parseSessionInfo(
                            from: title,
                            windowIndex: windowIndex + 1,
                            tabIndex: tabIndex + 1
                        ) {
                            if filterByTag == nil || sessionInfo.tag == filterByTag {
                                // Check if tab is busy using AX
                                var enrichedInfo = sessionInfo
                                let isBusy = try await isTerminalTabBusy(tab: tab, window: window)
                                enrichedInfo = TerminalSessionInfo(
                                    sessionIdentifier: sessionInfo.sessionIdentifier,
                                    projectPath: sessionInfo.projectPath,
                                    tag: sessionInfo.tag,
                                    fullTabTitle: sessionInfo.fullTabTitle,
                                    tty: sessionInfo.tty,
                                    isBusy: isBusy,
                                    windowIdentifier: sessionInfo.windowIdentifier,
                                    tabIdentifier: sessionInfo.tabIdentifier,
                                    ttyFromTitle: sessionInfo.ttyFromTitle,
                                    pidFromTitle: sessionInfo.pidFromTitle
                                )
                                allSessions.append(enrichedInfo)
                            }
                        }
                    }
                }
            }
            
            return allSessions
        }
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        Logger.log(level: .info, "Enhanced AX enumeration completed in \(String(format: "%.1f", duration))ms, found \(sessions.count) sessions")
        
        return sessions
    }
    
    private func findTerminalTabs(in window: AXUIElement) async throws -> [AXUIElement] {
        // Terminal.app structure: Window -> AXTabGroup -> AXRadioButton (tabs)
        var tabs: [AXUIElement] = []
        
        if let children = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: window) as? [AXUIElement] {
            for child in children {
                if let role = try await axProvider.getAttribute(kAXRoleAttribute as String, of: child) as? String,
                   role == "AXTabGroup" {
                    // Found the tab group, get its radio buttons
                    if let tabButtons = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: child) as? [AXUIElement] {
                        for button in tabButtons {
                            if let buttonRole = try await axProvider.getAttribute(kAXRoleAttribute as String, of: button) as? String,
                               buttonRole == "AXRadioButton" {
                                tabs.append(button)
                            }
                        }
                    }
                }
            }
        }
        
        return tabs
    }
    
    private func getTerminalTabTitle(tab: AXUIElement, window: AXUIElement) async throws -> String? {
        // In Terminal.app, the tab title is in the AXRadioButton's title
        if let title = try await axProvider.getTitle(of: tab) {
            return title
        }
        
        // Fallback: look for the selected tab's content
        if let isSelected = try await axProvider.getAttribute(kAXValueAttribute as String, of: tab) as? Int,
           isSelected == 1 {
            // This is the selected tab, we can get its title from the window
            return try await axProvider.getTitle(of: window)
        }
        
        return nil
    }
    
    private func isTerminalTabBusy(tab: AXUIElement, window: AXUIElement) async throws -> Bool {
        // Terminal.app exposes AXBusy on the text area of the selected tab
        if let isSelected = try await axProvider.getAttribute(kAXValueAttribute as String, of: tab) as? Int,
           isSelected == 1 {
            // Find the text area for the selected tab
            if let children = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: window) as? [AXUIElement] {
                for child in children {
                    if let role = try await axProvider.getAttribute(kAXRoleAttribute as String, of: child) as? String,
                       role == "AXTextArea" {
                        // Check if it's busy
                        return try await axProvider.isElementBusy(child)
                    }
                }
            }
        }
        
        return false
    }
    
    private func enrichSessionsWithAppleScriptData(_ axSessions: [TerminalSessionInfo]) throws -> [TerminalSessionInfo] {
        // Get full session data via AppleScript
        let scriptSessions = try listSessionsViaAppleScript(filterByTag: nil)
        
        // Create a map for quick lookup
        var scriptSessionMap: [String: TerminalSessionInfo] = [:]
        for session in scriptSessions {
            if let windowId = session.windowIdentifier,
               let tabId = session.tabIdentifier {
                let key = "\(windowId)-\(tabId)"
                scriptSessionMap[key] = session
            }
        }
        
        // Enrich AX sessions with script data
        return axSessions.map { axSession in
            if let windowId = axSession.windowIdentifier,
               let tabId = axSession.tabIdentifier {
                let key = "\(windowId)-\(tabId)"
                if let scriptSession = scriptSessionMap[key] {
                    // Create enriched session
                    return TerminalSessionInfo(
                        sessionIdentifier: axSession.sessionIdentifier,
                        projectPath: scriptSession.projectPath ?? axSession.projectPath,
                        tag: axSession.tag,
                        fullTabTitle: axSession.fullTabTitle,
                        tty: scriptSession.tty ?? axSession.tty,
                        isBusy: axSession.isBusy,
                        windowIdentifier: axSession.windowIdentifier,
                        tabIdentifier: axSession.tabIdentifier,
                        ttyFromTitle: scriptSession.ttyFromTitle ?? axSession.ttyFromTitle,
                        pidFromTitle: scriptSession.pidFromTitle ?? axSession.pidFromTitle
                    )
                }
            }
            return axSession
        }
    }
    
    // MARK: - AppleScript fallback for session enumeration (used for enrichment only)
    
    private func listSessionsViaAppleScript(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .debug, "[AppleTerminalControl] Using AppleScript for session enrichment data")

        let script = AppleTerminalScripts.listSessionsScript(appName: appName)
        Logger.log(level: .debug, "[AppleTerminalControl] About to run AppleScript for listing sessions")
        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)
        Logger.log(level: .debug, "[AppleTerminalControl] AppleScript execution completed")

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
    
    // MARK: - AppleScript Operations (required for terminal functionality)
    
    override func readSessionOutputViaAppleScript(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Reading output for tag: \(params.tag)"
        )

        // Find the session using Accessibility APIs
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

            // File logging is not applicable to the read action itself.
            // Command execution logging is handled within the executeCommand flow.

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
    
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    override func executeCommandViaAppleScript(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Attempting to execute command for tag: \(params.tag), project: \(params.projectPath ?? "none")"
        )

        let sessionToUse = try findOrCreateSession(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference
        )

        guard let tabID = sessionToUse.tabIdentifier,
              let windowID = sessionToUse.windowIdentifier,
              let tty = sessionToUse.tty
        else {
            throw TerminalControllerError
                .internalError(
                    details: "Found/created Apple Terminal session is missing critical identifiers. Session: \(sessionToUse)"
                )
        }

        let shouldActivateForCommand = shouldFocus(focusPreference: params.focusPreference)

        // Screen clearing as per SDD 3.2.5
        AppleTerminalControl.clearSessionScreen(
            appName: appName,
            windowID: windowID,
            tabID: tabID
        )

        // Busy Check and Interruption as per SDD 3.2.5
        if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid
            
            // Check if it's a shell process
            let commonShells = ["bash", "zsh", "fish", "sh", "tcsh", "csh", "login", "-bash", "-zsh", "-sh"]
            let isShell = commonShells.contains { processInfo.command.lowercased().contains($0) }
            
            if isShell {
                Logger.log(
                    level: .debug,
                    "[AppleTerminalControl] Session TTY \(tty) has shell '\(processInfo.command)' (PGID: \(foundPgid)). Proceeding without interruption."
                )
            } else {
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) is busy with command '\(processInfo.command)' (PGID: \(foundPgid)). Attempting to interrupt."
                )
                // SDD 3.2.5: "Attempt to stop the foreground process group by sending SIGINT via killpg(). Wait for a fixed
                // internal timeout (e.g., 3 seconds, non-configurable for V1)."
                // Using config.sigintWaitSeconds as per previous logic, which is 2s by default. Spec mentions 3s as
                // example.
                // Let's stick to config.sigintWaitSeconds for now.
                _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
                Logger.log(
                    level: .debug,
                    "[AppleTerminalControl] Sent SIGINT to PGID \(foundPgid) on TTY \(tty). Waiting \(config.sigintWaitSeconds)s."
                )
                Thread.sleep(forTimeInterval: Double(config.sigintWaitSeconds))

                if ProcessUtilities.isProcessGroupRunning(pgid: foundPgid) {
                    Logger.log(
                        level: .warn,
                        "[AppleTerminalControl] Busy process with PGID \(foundPgid) did not terminate after SIGINT and wait. Command execution might fail or be delayed."
                    )
                    // SDD 3.2.5: "If process still exists after timeout, execute fails with error code 4"
                    // Throwing error here to adhere to spec.
                    throw TerminalControllerError.internalError(
                        details: "Failed to stop busy process (PGID: \(foundPgid)) on TTY \(tty) before command execution."
                    )
                } else {
                    Logger.log(
                        level: .info,
                        "[AppleTerminalControl] Busy process with PGID \(foundPgid) terminated successfully."
                    )
                }
            }
        }

        let commandToRun = params.command ?? ""
        let logFileName =
            "terminator_output_\(tty.replacingOccurrences(of: "/dev/", with: ""))_\(Int(Date().timeIntervalSince1970)).log"
        let logFilePath = config.logDir.appendingPathComponent(logFileName).path
        let completionMarker = "TERMINATOR_CMD_COMPLETE_MARKER_\(UUID().uuidString)"

        var shellCommandSegments: [String] = []

        if let projectPath = params.projectPath {
            shellCommandSegments.append("cd '\(projectPath.escapingSingleQuotes())'")
            shellCommandSegments.append("clear") // As per SDD, clear after cd
        } else if commandToRun.isEmpty {
            shellCommandSegments.append("clear")
        }

        if !commandToRun.isEmpty {
            shellCommandSegments.append(commandToRun)
        }

        let coreCommand = shellCommandSegments.joined(separator: " && ")

        let shellCommandToExecuteWithRedirection: String
        let quotedLogFilePathForShell = "'\(logFilePath.escapingSingleQuotes())'"
        let escapedCompletionMarkerForShell = completionMarker.escapingSingleQuotes()

        if params.executionMode == .foreground {
            if coreCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // If only cd/clear, no marker needed, but still log output.
                shellCommandToExecuteWithRedirection = "( (\(coreCommand)) > \(quotedLogFilePathForShell) 2>&1 )"
            } else {
                shellCommandToExecuteWithRedirection =
                    "( (\(coreCommand)) > \(quotedLogFilePathForShell) 2>&1; echo '\(escapedCompletionMarkerForShell)' >> \(quotedLogFilePathForShell) )"
            }
        } else { // Background
            if coreCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shellCommandToExecuteWithRedirection =
                    "( (\(coreCommand)) > \(quotedLogFilePathForShell) 2>&1 )" // No disown if empty
            } else {
                shellCommandToExecuteWithRedirection =
                    "( (\(coreCommand)) > \(quotedLogFilePathForShell) 2>&1 ) & disown"
            }
        }

        Logger.log(
            level: .debug,
            "[AppleTerminalControl] Prepared shell command for AppleScript: \(shellCommandToExecuteWithRedirection)"
        )

        let script = AppleTerminalCommandScripts.executeCommandWithRedirectionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shellCommandToExecuteWithRedirection: shellCommandToExecuteWithRedirection,
            shouldActivateTerminal: shouldActivateForCommand
        )

        let scriptResult = AppleScriptBridge.runAppleScript(script: script)
        var pgidToReturn: pid_t?
        var outputText: String?
        var timedOut = false

        switch scriptResult {
        case let .success(appleScriptOutput):
            guard let responseString = appleScriptOutput as? String else {
                throw TerminalControllerError.appleScriptError(
                    message: "AppleScript execution did not return a string. Output: \(appleScriptOutput)",
                    scriptContent: script
                )
            }

            if responseString.hasPrefix("ERROR:") {
                Logger.log(level: .error, "[AppleTerminalControl] AppleScript reported error: \(responseString)")
                throw TerminalControllerError.appleScriptError(message: responseString, scriptContent: script)
            } else if responseString == "OK_COMMAND_SUBMITTED" {
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Command submitted successfully to Apple Terminal. Log: \(logFilePath)"
                )

                if params.executionMode == .foreground {
                    Logger.log(
                        level: .debug,
                        "[AppleTerminalControl] Foreground command. Tailing log \(logFilePath) for marker with timeout \(params.timeout)s."
                    )
                    let tailResult = ProcessUtilities.tailLogFileForMarker(
                        logFilePath: logFilePath,
                        marker: completionMarker,
                        timeoutSeconds: params.timeout > 0 ? params.timeout : config.foregroundCompletionSeconds,
                        linesToCapture: params.linesToCapture,
                        controlIdentifier: "AppleTerminalFG_\(params.tag)"
                    )
                    outputText = tailResult.output
                    timedOut = tailResult.timedOut

                    if timedOut {
                        Logger.log(
                            level: .warn,
                            "[AppleTerminalControl] Foreground command timed out waiting for marker in \(logFilePath)."
                        )
                        outputText = (outputText ?? "") + "\n---[APPLE_TERMINAL_CMD_TIMEOUT_MARKER_NOT_FOUND]---"
                        // Attempt to find PGID even on timeout for potential kill by wrapper
                        if let fgInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                            pgidToReturn = fgInfo.pgid
                        }
                    } else {
                        Logger.log(level: .info, "[AppleTerminalControl] Foreground command completed (marker found).")
                        Logger.log(level: .debug, "[AppleTerminalControl] Raw output before marker removal: \(outputText ?? "<nil>")")
                        outputText = outputText?.replacingOccurrences(of: completionMarker, with: "")
                        Logger.log(level: .debug, "[AppleTerminalControl] Final output after marker removal: \(outputText ?? "<nil>")")
                        // Try to get PGID of the command that just ran if possible, though it might be gone.
                        // This is best-effort for foreground.
                        if let fgInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                            // Check if it's a shell; if so, the command is done.
                            let commonShells = ["bash", "zsh", "fish", "sh", "tcsh", "csh", "login", "script"]
                            if !commonShells.contains(fgInfo.command.lowercased()) {
                                pgidToReturn = fgInfo.pgid
                            }
                        }
                    }
                } else { // Background
                    Logger.log(
                        level: .debug,
                        "[AppleTerminalControl] Background command. Capturing initial output from \(logFilePath) with timeout \(config.backgroundStartupSeconds)s."
                    )
                    let initialOutputTail = ProcessUtilities.tailLogFileForMarker(
                        logFilePath: logFilePath,
                        marker: "TERMINATOR_APPLE_TERMINAL_BG_NON_EXISTENT_MARKER_\(UUID().uuidString)",
                        timeoutSeconds: config.backgroundStartupSeconds,
                        linesToCapture: params.linesToCapture,
                        controlIdentifier: "AppleTerminalBG_\(params.tag)"
                    )
                    let initialOutput = initialOutputTail.output.replacingOccurrences(
                        of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---",
                        with: ""
                    )
                    if !initialOutput.isEmpty {
                        outputText = "Initial output (up to \(params.linesToCapture) lines):\n\(initialOutput)"
                    } else {
                        outputText = "No initial output captured for background command."
                    }
                    // For background, try to get PGID of the newly launched process.
                    // Wait a brief moment for the process to establish itself.
                    Thread.sleep(forTimeInterval: 0.2)
                    if let fgInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                        let commonShells = ["bash", "zsh", "fish", "sh", "tcsh", "csh", "login", "script"]
                        if !commonShells.contains(fgInfo.command.lowercased()) {
                            pgidToReturn = fgInfo.pgid
                        }
                    }
                    Logger.log(
                        level: .info,
                        "[AppleTerminalControl] Background command submitted. PGID identified: \(pgidToReturn ?? -1)"
                    )
                }
            } else {
                throw TerminalControllerError.appleScriptError(
                    message: "AppleScript execution returned unexpected success response: \(responseString)",
                    scriptContent: script
                )
            }

        case let .failure(error):
            Logger.log(
                level: .error,
                "[AppleTerminalControl] Failed to execute command via AppleScript: \(error.localizedDescription)"
            )
            throw TerminalControllerError.appleScriptError(
                message: "Command execution failed: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }

        // Clean up log file if foreground and completed without timeout and not preserving logs
        // For V1, logs are not aggressively deleted to aid debugging. Future enhancement.

        return ExecuteCommandResult(
            sessionInfo: sessionToUse,
            output: outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: nil, // Exit code not reliably available from Apple Terminal like this
            pid: pgidToReturn,
            wasKilledByTimeout: timedOut
        )
    }
    
    override func killProcessInSessionViaAppleScript(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Attempting to kill process in session for tag: \(params.tag)"
        )

        // Find the session
        let sessions = try listSessions(filterByTag: params.tag)
        guard let session = sessions.first else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let _ = session.tabIdentifier,
              let _ = session.windowIdentifier,
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
                "[AppleTerminalControl] Found foreground process '\(processInfo.command)' with PGID \(processInfo.pgid) on TTY \(tty)"
            )

            let pgidToKill = processInfo.pgid
            let commandToKill = processInfo.command

            // Check if the process is a shell - if so, nothing to kill
            let commonShells = ["bash", "zsh", "fish", "sh", "tcsh", "csh", "login", "-bash", "-zsh", "-sh"]
            let isShell = commonShells.contains { commandToKill.lowercased().contains($0) }

            if isShell {
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Session TTY \(tty) has shell '\(commandToKill)' (PGID: \(pgidToKill)). No process to kill."
                )
                return KillSessionResult(
                    killedSessionInfo: session,
                    killSuccess: false,
                    message: "No process to kill - session is idle at shell prompt"
                )
            }

            // Attempt to kill the process group
            // For now, always use SIGTERM. Force kill can be added as a parameter later
            let signal = SIGTERM
            let signalName = "SIGTERM"

            Logger.log(
                level: .info,
                "[AppleTerminalControl] Sending \(signalName) to process group \(pgidToKill)"
            )

            let killed = ProcessUtilities.killProcessGroup(pgid: pgidToKill, signal: signal)

            if killed {
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Successfully sent \(signalName) to process group \(pgidToKill)"
                )

                // Wait a moment for the process to die
                Thread.sleep(forTimeInterval: 0.5)

                // Check if the process is still running
                if ProcessUtilities.isProcessGroupRunning(pgid: pgidToKill) {
                    Logger.log(
                        level: .warn,
                        "[AppleTerminalControl] Process group \(pgidToKill) still running after SIGTERM."
                    )
                    return KillSessionResult(
                        killedSessionInfo: session,
                        killSuccess: false,
                        message: "Process did not terminate with SIGTERM"
                    )
                } else {
                    return KillSessionResult(
                        killedSessionInfo: session,
                        killSuccess: true,
                        message: "Process '\(commandToKill)' (PGID: \(pgidToKill)) killed successfully"
                    )
                }
            } else {
                throw TerminalControllerError.processControlError(
                    pgid: pgidToKill,
                    details: "Failed to send \(signalName) to process group"
                )
            }
        } else {
            Logger.log(
                level: .info,
                "[AppleTerminalControl] No foreground process found on TTY \(tty) for session with tag '\(params.tag)'"
            )

            return KillSessionResult(
                killedSessionInfo: session,
                killSuccess: false,
                message: "No process to kill - session is idle"
            )
        }
    }
    
    // MARK: - Session Management
    
    // Helper method to determine if Terminal should be focused based on preference
    func shouldFocus(focusPreference: AppConfig.FocusCLIArgument) -> Bool {
        switch focusPreference {
        case .forceFocus:
            true
        case .noFocus:
            false
        case .autoBehavior, .default:
            config.defaultFocusOnAction
        }
    }
    
    func findOrCreateSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        Logger.log(
            level: .debug,
            "[AppleTerminalControl] Finding or creating session for tag: \(tag), project: \(projectPath ?? "none")"
        )

        // Try to find existing session
        if let existingSession = try findExistingSession(projectPath: projectPath, tag: tag) {
            return existingSession
        }

        // No session found, create new one
        Logger.log(
            level: .info,
            "[AppleTerminalControl] No existing session for tag '\(tag)', creating new tab"
        )

        return try createNewSession(
            projectPath: projectPath,
            tag: tag,
            focusPreference: focusPreference
        )
    }

    private func findExistingSession(projectPath: String?, tag: String) throws -> TerminalSessionInfo? {
        let existingSessions = try listSessions(filterByTag: tag)

        Logger.log(
            level: .debug,
            "[AppleTerminalControl] Found \(existingSessions.count) existing sessions with tag '\(tag)'"
        )

        for (index, session) in existingSessions.enumerated() {
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Session \(index): sessionID=\(session.sessionIdentifier), title=\(session.fullTabTitle ?? "nil"), busy=\(session.isBusy)"
            )
        }

        var candidateSessions = existingSessions

        // Filter by project path if provided
        if let projectPath {
            let pathMatchingSessions = existingSessions.filter { session in
                session.projectPath == projectPath
            }
            if !pathMatchingSessions.isEmpty {
                candidateSessions = pathMatchingSessions
                Logger.log(
                    level: .debug,
                    "[AppleTerminalControl] Filtered to \(candidateSessions.count) sessions matching project path"
                )
            }
        }

        // Prefer non-busy sessions
        let nonBusySessions = candidateSessions.filter { !$0.isBusy }
        if !nonBusySessions.isEmpty {
            Logger.log(
                level: .info,
                "[AppleTerminalControl] Found \(nonBusySessions.count) non-busy sessions, selecting first"
            )
            return nonBusySessions.first
        }

        // All sessions are busy, return the first one
        if let firstSession = candidateSessions.first {
            Logger.log(
                level: .info,
                "[AppleTerminalControl] All \(candidateSessions.count) sessions are busy, selecting first"
            )
            return firstSession
        }

        return nil
    }

    private func createNewSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        Logger.log(
            level: .info,
            "[AppleTerminalControl] Creating new session for tag '\(tag)'"
        )

        let _ = SessionUtilities.generateProjectHash(projectPath: projectPath)

        let sessionTitle = SessionUtilities.generateSessionTitle(
            projectPath: projectPath,
            tag: tag,
            ttyDevicePath: "{TTY_PLACEHOLDER}",
            processId: nil
        )

        let shouldFocusNewTab = shouldFocus(focusPreference: focusPreference)

        // Find or create a window for the new tab
        let (windowID, _) = try findOrCreateWindow(tag: tag, shouldFocus: shouldFocusNewTab)

        // Create the tab in the window
        return try createTabInWindow(
            windowID: windowID,
            projectPath: projectPath,
            tag: tag,
            sessionTitle: sessionTitle,
            shouldFocus: shouldFocusNewTab
        )
    }

    private func findOrCreateWindow(tag: String, shouldFocus: Bool) throws -> (String, Bool) {
        let windowsData = try getExistingWindows()

        if let suitableWindow = findSuitableWindow(from: windowsData, tag: tag) {
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Found suitable existing window: \(suitableWindow.id)"
            )
            return (suitableWindow.id, false) // Not a new window
        }

        // Create new window
        let newWindowID = try createNewWindow(shouldFocus: shouldFocus)
        return (newWindowID, true) // Is a new window
    }

    private func getExistingWindows() throws -> [(id: String, tabs: [(id: String, title: String)])] {
        let script = AppleTerminalScripts.listWindowsAndTabsWithTitlesScript(appName: appName)
        let scriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch scriptResult {
        case let .success(resultData):
            return try parseWindowAndTabData(resultData)
        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to get windows: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    private func findSuitableWindow(
        from windowsData: [(id: String, tabs: [(id: String, title: String)])],
        tag: String
    ) -> (id: String, tabs: [(id: String, title: String)])? {
        // Window grouping logic based on config
        switch config.windowGrouping {
        case .off:
            // Always create new window
            return nil

        case .project:
            // Find windows with tabs from the same project
            let projectIdentifier = tag.components(separatedBy: ":").first ?? tag
            
            for window in windowsData {
                let hasProjectTab = window.tabs.contains { tabInfo in
                    let tabTag = SessionTitleParser.extractTag(from: tabInfo.title)
                    let tabProject = tabTag?.components(separatedBy: ":").first ?? ""
                    return tabProject == projectIdentifier
                }
                
                if hasProjectTab {
                    return window
                }
            }
            return nil

        case .smart:
            // Smart grouping: prefer windows with related tags
            // First try exact project match
            let projectIdentifier = tag.components(separatedBy: ":").first ?? tag
            
            for window in windowsData {
                let hasProjectTab = window.tabs.contains { tabInfo in
                    let tabTag = SessionTitleParser.extractTag(from: tabInfo.title)
                    let tabProject = tabTag?.components(separatedBy: ":").first ?? ""
                    return tabProject == projectIdentifier
                }
                
                if hasProjectTab {
                    return window
                }
            }
            
            // If no project match, use any existing window that's not too full
            let maxTabsPerWindow = 6
            for window in windowsData {
                if window.tabs.count < maxTabsPerWindow {
                    return window
                }
            }
            
            return nil
        }
    }

    private func createNewWindow(shouldFocus: Bool) throws -> String {
        let script = AppleTerminalScripts.createWindowScript(
            appName: appName,
            shouldActivateTerminal: shouldFocus
        )
        
        let scriptResult = AppleScriptBridge.runAppleScript(script: script)
        
        switch scriptResult {
        case let .success(result):
            guard let windowID = result as? String else {
                throw TerminalControllerError.appleScriptError(
                    message: "Create window script returned non-string: \(result)",
                    scriptContent: script
                )
            }
            
            Logger.log(
                level: .info,
                "[AppleTerminalControl] Created new window with ID: \(windowID)"
            )
            return windowID
            
        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create new window: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    private func createTabInWindow(
        windowID: String,
        projectPath: String?,
        tag: String,
        sessionTitle: String,
        shouldFocus: Bool
    ) throws -> TerminalSessionInfo {
        let createTabScript = AppleTerminalScripts.createTabInWindowScript(
            appName: appName,
            windowID: windowID,
            newSessionTitle: sessionTitle,
            shouldActivateTerminal: shouldFocus
        )

        let scriptResult = AppleScriptBridge.runAppleScript(script: createTabScript)

        switch scriptResult {
        case let .success(resultData):
            return try parseTabCreationResult(
                resultData: resultData,
                projectPath: projectPath,
                tag: tag,
                sessionTitle: sessionTitle,
                createTabScript: createTabScript
            )

        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create tab: \(error.localizedDescription)",
                scriptContent: createTabScript,
                underlyingError: error
            )
        }
    }

    private func parseTabCreationResult(
        resultData: Any,
        projectPath: String?,
        tag: String,
        sessionTitle: String,
        createTabScript: String
    ) throws -> TerminalSessionInfo {
        guard let resultArray = resultData as? [Any], resultArray.count == 4 else {
            throw TerminalControllerError.appleScriptError(
                message: "Create tab script returned unexpected format: \(resultData)",
                scriptContent: createTabScript
            )
        }

        guard let windowID = resultArray[0] as? String,
              let tabID = resultArray[1] as? String,
              let ttyPath = resultArray[2] as? String,
              let retrievedTitle = resultArray[3] as? String
        else {
            throw TerminalControllerError.appleScriptError(
                message: "Create tab script returned invalid data types: \(resultArray)",
                scriptContent: createTabScript
            )
        }

        Logger.log(
            level: .info,
            "[AppleTerminalControl] Created new tab: windowID=\(windowID), tabID=\(tabID), tty=\(ttyPath), title=\(retrievedTitle)"
        )

        let sessionID = "🤖💥 \(tag)"

        let sessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionID,
            projectPath: projectPath,
            tag: tag,
            fullTabTitle: retrievedTitle,
            tty: ttyPath,
            isBusy: false,
            windowIdentifier: windowID,
            tabIdentifier: tabID
        )

        Logger.log(
            level: .debug,
            "[AppleTerminalControl] New session created: \(sessionInfo)"
        )

        return sessionInfo
    }

    func parseWindowAndTabData(_ data: Any) throws -> [(id: String, tabs: [(id: String, title: String)])] {
        guard let windowList = data as? [[Any]] else {
            throw TerminalControllerError.internalError(
                details: "Invalid window data format: expected array of arrays"
            )
        }

        var result: [(id: String, tabs: [(id: String, title: String)])] = []

        for windowData in windowList {
            guard windowData.count >= 2,
                  let windowID = windowData[0] as? String,
                  let tabList = windowData[1] as? [[Any]]
            else {
                Logger.log(level: .warn, "Skipping invalid window data: \(windowData)")
                continue
            }

            var tabs: [(id: String, title: String)] = []
            for tabData in tabList {
                guard tabData.count >= 2,
                      let tabID = tabData[0] as? String,
                      let tabTitle = tabData[1] as? String
                else {
                    Logger.log(level: .warn, "Skipping invalid tab data: \(tabData)")
                    continue
                }
                tabs.append((id: tabID, title: tabTitle))
            }

            result.append((id: windowID, tabs: tabs))
        }

        return result
    }

    static func clearSessionScreen(appName: String, windowID: String, tabID: String) {
        let script = AppleTerminalScripts.clearSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: false
        )

        let scriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch scriptResult {
        case .success:
            Logger.log(level: .debug, "[AppleTerminalControl] Successfully cleared session screen")
        case let .failure(error):
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] Failed to clear session screen: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Utility Methods
    
    private func runAsyncBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = AsyncResultBox<T>()
        
        Task.detached {
            do {
                let value = try await operation()
                resultBox.store(.success(value))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch resultBox.load() {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw TerminalControllerError.internalError(details: "Async operation did not complete")
        }
    }
}

// MARK: - Configuration Extension

extension AppConfig {
    /// Whether to enrich AX session data with AppleScript data
    var enrichSessionInfo: Bool {
        return ProcessInfo.processInfo.environment["TERMINATOR_ENRICH_SESSIONS"] != "false"
    }
}

// Feature flags have been removed - we now always use Accessibility APIs where possible

// Helper structs for parsing AppleScript list output
struct AppleTerminalTabInfo {
    let id: String
    let title: String
}

struct AppleTerminalWindowInfo {
    let id: String
    let tabs: [AppleTerminalTabInfo]
}

// MARK: - String Extension

extension String {
    func escapingSingleQuotes() -> String {
        replacingOccurrences(of: "'", with: "'\\\\''")
    }
}
