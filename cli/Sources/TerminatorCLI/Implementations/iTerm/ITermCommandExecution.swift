import Foundation

// MARK: - Command Execution Extension for ITermControl

extension ITermControl {
    // MARK: - Main Execute Command Function

    // swiftlint:disable:next function_body_length
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(
            level: .info,
            "[ITermControl] Attempting to execute command for tag: \(params.tag), project: \(params.projectPath ?? "nil")",
            file: #file,
            line: #line,
            function: #function
        )

        let sessionToUse = try findOrCreateSessionForITerm(
            projectPath: params.projectPath,
            tag: params.tag,
            focusPreference: params.focusPreference // Initial focus applied here
        )

        let (_, sessionID, tty) = try validateSessionIdentifiers(sessionToUse)

        // Clear the session screen before any command execution
        Self.clearSessionScreen(appName: appName, sessionID: sessionID, tag: params.tag)

        // SDD 3.2.5: Pre-execution Step: Busy Check & Stop
        try handleBusySession(tty: tty, tag: params.tag)
        // End of Busy Check

        // Handle session preparation if command is nil or empty
        if params.command == nil || params.command!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Logger.log(
                level: .info,
                "[ITermControl] No command provided. Preparing session (focus/clear) for tag: \(params.tag)",
                file: #file,
                function: #function
            )
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

        let logFilePathURL = try prepareLogFile(tty: tty)
        let completionMarker = "TERMINATOR_CMD_DONE_\(UUID().uuidString)"
        let isForeground = params.executionMode == .foreground

        // Construct the shell command string in Swift
        let shellCommandToExecuteInTerminal = constructShellCommand(
            command: trimmedCommandToExecute,
            logFilePath: logFilePathURL.path,
            completionMarker: completionMarker,
            isForeground: isForeground
        )

        // Escape the entire shell command for AppleScript
        let appleScriptSafeShellCommand = shellCommandToExecuteInTerminal
            .replacingOccurrences(of: "\\", with: "\\\\") // Escape backslashes first
            .replacingOccurrences(of: "\"", with: "\\\"") // Then escape quotes

        let shouldActivateITermForCommand = attentesFocus(
            focusPreference: params.focusPreference,
            defaultFocusSetting: config.defaultFocusOnAction
        )

        let script = ITermScripts.simpleExecuteShellCommandInSessionScript(
            appName: appName,
            sessionID: sessionID,
            shellCommandToExecuteEscapedForAppleScript: appleScriptSafeShellCommand,
            shouldActivateITerm: shouldActivateITermForCommand
        )

        Logger.log(
            level: .debug,
            "[ITermCtrl] Executing in session ([iTermSessID: \(sessionID), TTY: \(tty)]): \(appleScriptSafeShellCommand). Log: \(logFilePathURL.path). Marker: \(completionMarker)",
            file: #file,
            function: #function
        )

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData): // resultData is now a simple status string
            return try processExecuteCommandWithFileLogging(
                appleScriptStatusString: resultData,
                // resultData is already a String from Result<String, AppleScriptError>
                scriptContent: script,
                sessionInfo: sessionToUse,
                params: params,
                commandToExecute: trimmedCommandToExecute, // For logging/timeout messages
                logFilePath: logFilePathURL.path,
                completionMarker: completionMarker
            )
        case let .failure(error):
            let errorMsg = "Failed to execute iTerm command for tag \(params.tag): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg, file: #file, function: #function)
            // Attempt to clean up log file if script submission failed.
            try? FileManager.default.removeItem(atPath: logFilePathURL.path)
            throw TerminalControllerError.appleScriptError(
                message: errorMsg,
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    // MARK: - Process Execute Command with File Logging

    // swiftlint:disable:next function_body_length
    private func processExecuteCommandWithFileLogging(
        appleScriptStatusString: Any, // Changed from resultData
        scriptContent: String,
        sessionInfo: TerminalSessionInfo,
        params: ExecuteCommandParams,
        commandToExecute _: String, // Renamed for clarity
        logFilePath: String,
        completionMarker: String
    ) throws -> ExecuteCommandResult {
        // Handle AppleScript errors directly from the status string
        guard let statusString = appleScriptStatusString as? String else {
            Logger.log(
                level: .error,
                "[ITermControl] iTerm execute command AppleScript result is not a string: \(type(of: appleScriptStatusString))",
                file: #file,
                function: #function
            )
            throw TerminalControllerError.appleScriptError(
                message: "iTerm execute script returned unexpected type",
                scriptContent: scriptContent
            )
        }

        if !statusString.uppercased().contains("OK") { // e.g. "OK_COMMAND_SUBMITTED" or just "OK"
            Logger.log(
                level: .error,
                "[ITermControl] iTerm execute command AppleScript reported error: \(statusString)",
                file: #file,
                function: #function
            )
            // Attempt to clean up log file if script submission failed.
            try? FileManager.default.removeItem(atPath: logFilePath)
            throw TerminalControllerError.appleScriptError(
                message: "iTerm execute script error: \(statusString)",
                scriptContent: scriptContent
            )
        }

        var output = ""
        var exitCode: Int? // For foreground, successful completion implies 0 unless timeout
        let pid: pid_t? = nil // PID is not reliably obtained from this script structure.
        var wasKilledByTimeout = false

        let isForeground = params.executionMode == .foreground
        // Use params.timeout for foreground, config.backgroundStartupSeconds for background's initial read
        _ = isForeground ? params.timeout : Int(config.backgroundStartupSeconds)

        if isForeground {
            let result = processForegroundCommand(
                params: params,
                logFilePath: logFilePath,
                completionMarker: completionMarker,
                sessionInfo: sessionInfo
            )
            output = result.output
            wasKilledByTimeout = result.wasKilledByTimeout
            exitCode = result.exitCode
        } else { // Background
            let result = processBackgroundCommand(
                params: params,
                logFilePath: logFilePath
            )
            output = result.output
            wasKilledByTimeout = result.wasKilledByTimeout
            exitCode = result.exitCode
        }

        // Clean up log file for successful foreground commands OR if it's a background command (log might grow large).
        // For timed-out foreground commands, keep the log for inspection.
        if (isForeground && !wasKilledByTimeout) || !isForeground {
            if FileManager.default.fileExists(atPath: logFilePath) {
                do {
                    try FileManager.default.removeItem(atPath: logFilePath)
                    Logger.log(
                        level: .debug,
                        "[ITermControl] Removed log file: \(logFilePath)",
                        file: #file,
                        function: #function
                    )
                } catch {
                    // Log error but don't fail the operation
                    Logger.log(
                        level: .warn,
                        "[ITermControl] Failed to remove log file \(logFilePath): \(error.localizedDescription)",
                        file: #file,
                        function: #function
                    )
                }
            }
        }

        let finalSessionInfo = TerminalSessionInfo(
            sessionIdentifier: sessionInfo.sessionIdentifier,
            projectPath: sessionInfo.projectPath,
            tag: sessionInfo.tag,
            fullTabTitle: sessionInfo.fullTabTitle, // Title might have been updated by findOrCreate
            tty: sessionInfo.tty,
            isBusy: params.executionMode == .background ? ProcessUtilities
                .getTTYBusyStatus(tty: sessionInfo.tty ?? "") : false,
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

    // MARK: - Helper Methods for Command Execution

    func handleBusySession(tty: String, tag: String) throws {
        if !config.reuseBusySessions,
           let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
            let foundPgid = processInfo.pgid

            Logger.log(
                level: .info,
                "[ITermControl] Session TTY \(tty) for tag \(tag) is busy with command '\(processInfo.command)' (PGID: \(foundPgid)). Attempting to interrupt.",
                file: #file,
                line: #line,
                function: #function
            )

            _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(
                level: .debug,
                "[ITermControl] Sent SIGINT to PGID \(foundPgid) on TTY \(tty).",
                file: #file,
                function: #function
            )

            Thread.sleep(forTimeInterval: TimeInterval(config.sigintWaitSeconds))

            if let stillBusyInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: tty) {
                Logger.log(
                    level: .error,
                    "[ITermControl] Session TTY \(tty) for tag \(tag) remained busy with command '\(stillBusyInfo.command)' after interrupt attempt.",
                    file: #file,
                    function: #function
                )
                throw TerminalControllerError.busy(tty: tty, processDescription: stillBusyInfo.command)
            } else {
                Logger.log(
                    level: .info,
                    "[ITermControl] Process on TTY \(tty) was successfully interrupted.",
                    file: #file,
                    function: #function
                )
            }
        }
    }

    func prepareLogFile(tty: String) throws -> URL {
        let logFileName =
            "terminator_output_iterm_\((tty as NSString).lastPathComponent)_\(Int(Date().timeIntervalSince1970)).log"
        let logFilePathURL = config.logDir.appendingPathComponent("cli_command_outputs")
            .appendingPathComponent(logFileName)

        do {
            try FileManager.default.createDirectory(
                at: logFilePathURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            Logger.log(
                level: .error,
                "[ITermControl] Could not create directory for command output logs: \(error.localizedDescription)",
                file: #file,
                function: #function
            )
            throw TerminalControllerError
                .internalError(details: "Failed to create output log directory: \(error.localizedDescription)")
        }

        return logFilePathURL
    }

    func constructShellCommand(
        command: String,
        logFilePath: String,
        completionMarker: String,
        isForeground: Bool
    ) -> String {
        let quotedLogFilePathForShell = ProcessUtilities.escapePathForShell(logFilePath)
        let escapedCommandForShell = ProcessUtilities.escapeCommandForShell(command)

        if isForeground {
            return "((\(escapedCommandForShell)) > \(quotedLogFilePathForShell) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePathForShell))"
        } else {
            return "((\(escapedCommandForShell)) > \(quotedLogFilePathForShell) 2>&1) & disown"
        }
    }

    func processForegroundCommand(
        params: ExecuteCommandParams,
        logFilePath: String,
        completionMarker: String,
        sessionInfo: TerminalSessionInfo
    ) -> (output: String, wasKilledByTimeout: Bool, exitCode: Int?) {
        Logger.log(
            level: .debug,
            "[ITermControl] Foreground command. Tailing log file \(logFilePath) for completion marker with timeout \(params.timeout)s",
            file: #file,
            function: #function
        )

        let tailResult = ProcessUtilities.tailLogFileForMarker(
            logFilePath: logFilePath,
            marker: completionMarker,
            timeoutSeconds: params.timeout,
            linesToCapture: params.linesToCapture,
            controlIdentifier: "ITermFG-\(params.tag)"
        )

        var output = tailResult.output
        let wasKilledByTimeout = tailResult.timedOut
        var exitCode: Int?

        if wasKilledByTimeout {
            Logger.log(
                level: .warn,
                "[ITermControl] Command for tag \(params.tag) timed out after \(params.timeout)s waiting for marker.",
                file: #file,
                function: #function
            )
            output = output.replacingOccurrences(of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
            output += handleTimeoutKill(sessionInfo: sessionInfo, params: params)
        } else {
            output = output.replacingOccurrences(of: completionMarker, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            exitCode = 0 // Success if marker was found and not timed out
            Logger.log(
                level: .info,
                "[ITermControl] Foreground iTerm command completed. Log: \(logFilePath).",
                file: #file,
                function: #function
            )
        }

        return (output, wasKilledByTimeout, exitCode)
    }

    func processBackgroundCommand(
        params: ExecuteCommandParams,
        logFilePath: String
    ) -> (output: String, wasKilledByTimeout: Bool, exitCode: Int?) {
        Logger.log(
            level: .info,
            "[ITermControl] Background command '\(params.command ?? "<no command>")' submitted for tag \(params.tag). Capturing initial output from \(logFilePath) with timeout \(Int(config.backgroundStartupSeconds))s.",
            file: #file,
            function: #function
        )

        let initialOutputTail = ProcessUtilities.tailLogFileForMarker(
            logFilePath: logFilePath,
            marker: "TERMINATOR_ITERM_BG_NON_EXISTENT_MARKER_\(UUID().uuidString)", // Marker not expected
            timeoutSeconds: Int(config.backgroundStartupSeconds),
            linesToCapture: params.linesToCapture,
            controlIdentifier: "ITermBGInitial-\(params.tag)"
        )

        var output = initialOutputTail.output.replacingOccurrences(
            of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---",
            with: ""
        )

        if output.isEmpty {
            output =
                "Background command submitted. (No initial output captured within \(Int(config.backgroundStartupSeconds))s or output log is empty)"
        } else {
            output = "Initial output (up to \(params.linesToCapture) lines):\n\(output)"
        }

        return (output, false, 0) // Background submission is considered successful
    }

    func handleTimeoutKill(sessionInfo: TerminalSessionInfo, params: ExecuteCommandParams) -> String {
        var killMessage = ""
        guard let tty = sessionInfo.tty else {
            return "\n--- COULD NOT IDENTIFY TTY FOR TIMEOUT KILL ---"
        }

        let ttyNameOnly = (tty as NSString).lastPathComponent
        let pgidFindScript = ITermScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
        let pgidFindResult = AppleScriptBridge.runAppleScript(script: pgidFindScript)

        if case let .success(pgidData) = pgidFindResult {
            let parseResult = parsePgidFromResult(resultStringOrArray: pgidData, tty: tty, tag: params.tag)
            if let pgidToKill = parseResult.pgid {
                Logger.log(
                    level: .info,
                    "[ITermControl] Timeout: Attempting to kill process group \(pgidToKill) for TTY \(tty)",
                    file: #file,
                    function: #function
                )
                _ = ProcessUtilities.attemptGracefulKill(
                    pgid: pgidToKill,
                    config: config,
                    message: &killMessage
                )
                Logger.log(
                    level: .debug,
                    "[ITermControl] Timeout kill attempt result: \(killMessage)",
                    file: #file,
                    function: #function
                )
                return "\n---[ITERM_CMD_TIMEOUT_MARKER_NOT_FOUND]---\n\(killMessage)"
            }
        }
        return "\n---[ITERM_CMD_TIMEOUT_MARKER_NOT_FOUND]---"
    }
}
