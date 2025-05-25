import Foundation

extension AppleTerminalControl {
    // swiftlint:disable:next function_body_length
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

        // Clear the session screen before any command execution
        // This internal clear might also handle activation if shouldActivateForCommand is true.
        Self.clearSessionScreen(
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

            Logger.log(
                level: .info,
                "[AppleTerminalControl] Session TTY \(tty) for tag \(params.tag) is busy with command '\(foundCommand)' (PGID: \(foundPgid)). Attempting to interrupt."
            )

            _ = ProcessUtilities.killProcessGroup(pgid: foundPgid, signal: SIGINT)
            Logger.log(level: .debug, "[AppleTerminalControl] Sent SIGINT to PGID \(foundPgid) on TTY \(tty).")

            Thread.sleep(forTimeInterval: Double(config.sigintWaitSeconds)) // Use configured wait time, CASTED

            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Waited \(config.sigintWaitSeconds) seconds for process to terminate."
            )
        }

        // Determine if we need to change directory
        guard let command = params.command else {
            throw TerminalControllerError.missingCommandError
        }

        var fullCommand = command
        if let projectPath = params.projectPath {
            let cdCommand = "cd \(projectPath.escapedForShell()) && clear"
            fullCommand = "\(cdCommand) && \(command)"
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Prepending cd command to set project path. Full command: \(fullCommand)"
            )
        }

        // Send the command to the Terminal.app session
        let script = AppleTerminalScripts.simpleExecuteShellCommandInTabScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            command: fullCommand,
            shouldActivateTerminal: shouldActivateForCommand
        )
        let scriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch scriptResult {
        case let .success(result):
            Logger.log(
                level: .info,
                "[AppleTerminalControl] Command executed successfully in Terminal.app session."
            )

            // TODO: Implement file logging
            // let logManager = FileLogManager(sessionInfo: sessionToUse, config: config)

            return try _processExecuteCommandResult(
                result: result,
                expectedWindow: windowID,
                expectedTab: tabID,
                expectedTTY: tty,
                sessionInfo: sessionToUse,
                params: params,
                command: command
            )

        case let .failure(error):
            Logger.log(
                level: .error,
                "[AppleTerminalControl] Failed to execute command: \(error.localizedDescription)"
            )
            throw TerminalControllerError.appleScriptError(
                message: "Command execution failed: \(error.localizedDescription)",
                scriptContent: script,
                underlyingError: error
            )
        }
    }

    private func _processExecuteCommandResult(
        result: Any,
        expectedWindow: String,
        expectedTab: String,
        expectedTTY: String,
        sessionInfo: TerminalSessionInfo,
        params: ExecuteCommandParams,
        command _: String
    ) throws -> ExecuteCommandResult {
        // The AppleScript for sendCommandToTabScript returns {windowID, tabID, tty, startMarker}
        guard let resultArray = result as? [Any], resultArray.count >= 4 else {
            throw TerminalControllerError.appleScriptError(
                message: "Execute command script returned unexpected data: \(result)",
                scriptContent: "N/A",
                underlyingError: nil
            )
        }

        let actualWindow = resultArray[0] as? String ?? "unknown"
        let actualTab = resultArray[1] as? String ?? "unknown"
        let actualTTY = resultArray[2] as? String ?? "unknown"
        _ = resultArray[3] as? String ?? "unknown" // startMarker - not used currently

        // Verify the execution happened in the expected session
        if actualWindow != expectedWindow || actualTab != expectedTab {
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] Command executed in different session than expected. Expected: \(expectedWindow):\(expectedTab), Actual: \(actualWindow):\(actualTab)"
            )
        }

        if actualTTY != expectedTTY {
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] TTY changed during execution. Expected: \(expectedTTY), Actual: \(actualTTY)"
            )
        }

        var pgid: Int32?

        // If execution mode is foreground, we need to monitor for process completion
        if params.executionMode == .foreground {
            Logger.log(level: .info, "[AppleTerminalControl] Waiting for command completion...")

            // Wait a moment for the process to start
            Thread.sleep(forTimeInterval: 0.5)

            // Get the foreground process group
            if let processInfo = ProcessUtilities.getForegroundProcessInfo(forTTY: actualTTY) {
                pgid = processInfo.pgid
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Found foreground process for command: \(processInfo.command) (PGID: \(processInfo.pgid))"
                )

                // Wait for the process group to complete
                var waitTime = 0.0
                let checkInterval = 0.5
                let maxWaitTime = Double(params.timeout)

                while waitTime < maxWaitTime {
                    Thread.sleep(forTimeInterval: checkInterval)
                    waitTime += checkInterval

                    // Check if the process group is still active
                    if ProcessUtilities.isProcessGroupRunning(pgid: processInfo.pgid) {
                        Logger.log(
                            level: .debug,
                            "[AppleTerminalControl] Process group \(processInfo.pgid) still active after \(waitTime)s"
                        )
                    } else {
                        Logger.log(
                            level: .info,
                            "[AppleTerminalControl] Process group \(processInfo.pgid) completed after \(waitTime)s"
                        )
                        break
                    }
                }

                if waitTime >= maxWaitTime {
                    Logger.log(
                        level: .warn,
                        "[AppleTerminalControl] Command did not complete within \(maxWaitTime)s timeout"
                    )
                }
            } else {
                Logger.log(
                    level: .warn,
                    "[AppleTerminalControl] Could not find foreground process for wait monitoring"
                )
                // Still wait a bit to let the command potentially complete
                Thread.sleep(forTimeInterval: 2.0)
            }
        }

        // TODO: Implement file logging
        // Log the command execution
        // if config.logToFile && logManager.shouldLogToFile {
        //     do {
        //         try logManager.logEntry(
        //             type: .command,
        //             content: command,
        //             metadata: [
        //                 "tag": params.tag,
        //                 "projectPath": params.projectPath ?? "none",
        //                 "executionMode": "\(params.executionMode)",
        //                 "pgid": pgid != nil ? String(pgid!) : "unknown",
        //                 "startMarker": startMarker
        //             ]
        //         )
        //     } catch {
        //         Logger.log(
        //             level: .error,
        //             "[AppleTerminalControl] Failed to log command to file: \(error.localizedDescription)"
        //         )
        //     }
        // }

        return ExecuteCommandResult(
            sessionInfo: sessionInfo,
            output: nil, // Output capture not implemented for Terminal.app
            exitCode: nil, // Exit code not available for Terminal.app
            pid: pgid,
            wasKilledByTimeout: false
        )
    }

    static func clearSessionScreen(
        appName: String,
        windowID: String,
        tabID: String,
        tag: String,
        shouldActivate: Bool
    ) {
        let clearScript = AppleTerminalScripts.clearSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: shouldActivate
        )
        let clearResult = AppleScriptBridge.runAppleScript(script: clearScript)

        switch clearResult {
        case .success:
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Successfully cleared session screen for tag '\(tag)'"
            )
        case let .failure(error):
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] Failed to clear session screen: \(error.localizedDescription)"
            )
        }
    }
}
