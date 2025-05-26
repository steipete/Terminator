import Foundation

extension AppleTerminalControl {
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
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
        let quotedLogFilePathForShell = "'\\(logFilePath.escapingSingleQuotes())'"
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
        var pgidToReturn: pid_t? = nil
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
                        outputText = outputText?.replacingOccurrences(of: completionMarker, with: "")
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
}

extension String {
    func escapingSingleQuotes() -> String {
        replacingOccurrences(of: "'", with: "'\\\\''")
    }
}
