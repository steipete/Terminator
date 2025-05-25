import Foundation

// GhostyParser.swift
// This struct will be responsible for parsing the results of AppleScript commands
// executed against the Ghosty terminal application.

enum GhostyParser {
    static func parseGhostySessionListOutput(
        resultStringOrArray: Any,
        scriptContent _: String,
        filterByTag _: String?
    ) throws -> [TerminalSessionInfo] {
        Logger.log(level: .debug, "[GhostyParser] Parsing session list output for Ghosty. Data: \(resultStringOrArray)")
        // Ghosty list script is very basic, likely doesn't return usable session info.
        // For V1, we return an empty list as per best-effort spec.
        if let resStr = resultStringOrArray as? String, resStr == "GHOSTY_LIST_PLACEHOLDER" {
            Logger.log(level: .info, "[GhostyParser] Ghosty list placeholder confirmed. Returning empty session list.")
        } else {
            Logger.log(
                level: .warn,
                "[GhostyParser] Unexpected output from Ghosty list script: \(resultStringOrArray). Returning empty list."
            )
        }
        return []
    }

    // Ghosty create session is not really a distinct operation with identifiable output yet.
    // The executeCommand will handle the "creation" which is likely just using Ghosty's current context.
    // This function might not be directly called if GhostyControl.executeCommand handles session prep directly.
    // However, if a script *were* to return something like a TTY (highly speculative):
    static func parseCreateNewSessionGhostyOutput(_: String, projectPath: String?, tag: String) -> TerminalSessionInfo {
        // Default placeholder session info, as Ghosty is unlikely to return detailed creation data.
        TerminalSessionInfo(
            sessionIdentifier: SessionUtilities.generateUserFriendlySessionIdentifier(
                projectPath: projectPath,
                tag: tag
            ),
            projectPath: projectPath,
            tag: tag,
            fullTabTitle: "Ghosty Session: \(tag)", // Placeholder title
            tty: nil, // Ghosty might not expose this easily
            isBusy: false, // Assume not busy initially
            windowIdentifier: nil, // Ghosty might not have scriptable windows/tabs
            tabIdentifier: nil, // Ghosty might not have scriptable tabs
            ttyFromTitle: nil, // Correct order
            pidFromTitle: nil // Correct order
        )
    }

    // swiftlint:disable:next function_body_length
    static func parseExecuteCommandGhostyOutput(
        appleScriptResultData: Any,
        scriptContent _: String,
        logFilePath: String,
        completionMarker: String,
        isForeground: Bool,
        linesToCapture: Int,
        commandTimeout: Int // Pass command specific timeout for tailing
    ) throws -> (status: String, output: String, pid: String?) {
        Logger.log(
            level: .debug,
            "[GhostyParser] Parsing execute command output for Ghosty. Data: \(appleScriptResultData), Log: \(logFilePath)"
        )

        var status = "OK_SUBMITTED_UNKNOWN"
        var resultMessage = "Ghosty command submitted."
        let pidStr: String? = nil // PID not discoverable for Ghosty via these simple scripts

        if let resStr = appleScriptResultData as? String {
            if resStr.hasPrefix("ERROR:") {
                status = "ERROR"
                resultMessage = resStr
                Logger.log(level: .error, "[GhostyParser] Ghosty execute script reported error: \(resultMessage)")
                return (status, resultMessage, pidStr) // Output is the error message itself
            } else if resStr == "OK_COMMAND_SUBMITTED" {
                // This is the expected success from the script
                status = isForeground ? "PENDING_FOREGROUND" : "OK_SUBMITTED_BG"
                resultMessage = "Ghosty command submitted via AppleScript."
                Logger.log(level: .info, "[GhostyParser] Ghosty execute script returned: \(resStr)")
            } else {
                // Unexpected string from AppleScript
                status = "UNKNOWN_AS_RESPONSE"
                resultMessage = "Ghosty execute script returned unexpected data: \(resStr)"
                Logger.log(level: .warn, resultMessage)
            }
        } else {
            status = "ERROR"
            resultMessage = "Ghosty execute script returned non-string data: \(appleScriptResultData)"
            Logger.log(level: .error, resultMessage)
            return (status, resultMessage, pidStr)
        }

        var outputText = ""
        if status == "ERROR" {
            outputText = resultMessage
        } else if isForeground {
            Logger.log(
                level: .debug,
                "[GhostyParser] Foreground command for Ghosty. Tailing log \(logFilePath) for marker with timeout \(commandTimeout)s."
            )
            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: completionMarker,
                timeoutSeconds: commandTimeout > 0 ? commandTimeout : 10, // Use command timeout or default for Ghosty
                linesToCapture: linesToCapture,
                controlIdentifier: "GhostyFG"
            )
            outputText = tailResult.output

            if tailResult.timedOut {
                status = "TIMEOUT"
                resultMessage = "Ghosty command timed out waiting for marker in log file: \(logFilePath)."
                outputText = outputText.replacingOccurrences(
                    of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---",
                    with: ""
                ) // Clean if present
                outputText += "\n---[GHOSTY_CMD_TIMEOUT_MARKER_NOT_FOUND]---"
                Logger.log(level: .warn, "[GhostyParser] \(resultMessage)")
            } else {
                status = "OK_COMPLETED_FG"
                resultMessage = "Ghosty foreground command completed (marker found)."
                outputText = outputText.replacingOccurrences(of: "\(completionMarker)", with: "") // Remove marker
                Logger.log(level: .info, "[GhostyParser] \(resultMessage) Log: \(logFilePath).")
                // try? FileManager.default.removeItem(atPath: logFilePath) // Optional: remove log on success
            }
        } else { // Background
            status = "OK_SUBMITTED_BG"
            resultMessage = "Ghosty background command submitted. Output logged to: \(logFilePath)"
            // Capture initial output for background commands as per SDD best-effort
            let initialOutputTail = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: "TERMINATOR_GHOSTY_BG_NON_EXISTENT_MARKER_\(UUID().uuidString)",
                // Marker not expected to be found
                timeoutSeconds: commandTimeout > 0 ? commandTimeout : 2,
                // Use background startup timeout from params or default
                linesToCapture: linesToCapture,
                controlIdentifier: "GhostyBGInitial"
            )
            let initialOutput = initialOutputTail.output.replacingOccurrences(
                of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---",
                with: ""
            )
            if !initialOutput.isEmpty {
                outputText = "Initial output (up to \(linesToCapture) lines):\n\(initialOutput)"
            } else {
                outputText = "No initial output captured for background command."
            }
            Logger.log(level: .info, "[GhostyParser] \(resultMessage) Initial output check complete.")
        }

        return (status, outputText.trimmingCharacters(in: .whitespacesAndNewlines), pidStr)
    }

    static func parseReadSessionOutput(
        resultData: Any,
        scriptContent: String,
        sessionInfo: TerminalSessionInfo, // Provided by GhostyControl, likely a placeholder
        linesToRead: Int
    ) throws -> ReadSessionResult {
        Logger.log(level: .debug, "[GhostyParser] Parsing read session output for Ghosty. Data: \(resultData)")

        if let errorStr = resultData as? String, errorStr.hasPrefix("ERROR:") {
            Logger.log(level: .error, "[GhostyParser] Ghosty read script reported error: \(errorStr)")
            throw TerminalControllerError.appleScriptError(message: errorStr, scriptContent: scriptContent)
        }

        guard let content = resultData as? String else {
            let errorMsg =
                "Failed to read Ghosty session: AppleScript did not return a string as expected. Output: \(resultData)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }

        var lines = content.components(separatedBy: .newlines)
        if linesToRead > 0 && lines.count > linesToRead {
            lines = Array(lines.suffix(linesToRead))
        }
        let processedOutput = lines.joined(separator: "\n")

        Logger.log(
            level: .info,
            "[GhostyParser] Successfully read content from Ghosty. Length: \(processedOutput.count) chars, Lines: \(lines.count)"
        )
        return ReadSessionResult(sessionInfo: sessionInfo, output: processedOutput)
    }

    // For focus, kill, clear - they might just return simple "OK" or error strings.
    // The parser might not need to do much other than pass through or check for "ERROR:".
    static func parseSimpleGhostyOkErrorResponse(
        resultData: Any,
        scriptContent: String,
        actionName: String
    ) throws -> String {
        if let errorStr = resultData as? String, errorStr.hasPrefix("ERROR:") {
            Logger.log(level: .error, "[GhostyParser] Ghosty \(actionName) script reported error: \(errorStr)")
            throw TerminalControllerError.appleScriptError(message: errorStr, scriptContent: scriptContent)
        }
        guard let okStr = resultData as? String, okStr.contains("OK") else {
            let errorMsg = "Ghosty \(actionName) script returned unexpected response: \(resultData)"
            Logger.log(level: .warn, "[GhostyParser] \(errorMsg)")
            // Even if not an explicit ERROR prefix, if it's not an expected OK, treat as an issue.
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        Logger.log(level: .info, "[GhostyParser] Ghosty \(actionName) successful. Response: \(okStr)")
        return okStr // Return the success message (e.g., "OK_FOCUSED")
    }
}
