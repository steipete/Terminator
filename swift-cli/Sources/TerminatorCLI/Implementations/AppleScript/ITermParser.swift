import Foundation

// ITermParser.swift
// Parses AppleScript results for iTerm2 interactions.

struct ITermParser {

    static func parseListSessionsOutput(resultData: Any, scriptContent: String, filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .debug, "[ITermParser] Parsing list sessions output. Data: \(resultData)")
        guard let outerList = resultData as? [[String]] else {
            if let errorStr = resultData as? String, errorStr.contains("error") {
                 Logger.log(level: .error, "[ITermParser] List sessions script returned an error string: \(errorStr)")
                 throw TerminalControllerError.appleScriptError(message: "iTerm list sessions script failed: \(errorStr)", scriptContent: scriptContent)
            }
            Logger.log(level: .error, "[ITermParser] List sessions script did not return an array of arrays as expected. Output: \(resultData)")
            throw TerminalControllerError.appleScriptError(message: "iTerm list sessions script did not return an array of arrays. Output: \(resultData)", scriptContent: scriptContent)
        }

        var sessions: [TerminalSessionInfo] = []
        for propertyList in outerList {
            var properties: [String: String] = [:]
            for item in propertyList {
                let parts = item.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    properties[parts[0]] = parts[1]
                }
            }

            guard let winID = properties["win_id"],
                  let tabID = properties["tab_id"],
                  let sessionID = properties["session_id"], // This is iTerm's internal session ID
                  let tty = properties["tty"],
                  let name = properties["name"] else {
                Logger.log(level: .warn, "[ITermParser] Skipping session, missing one or more required properties: \(properties)")
                continue
            }
            
            let (parsedProj, parsedTag, parsedPID, parsedTTYFromTitle) = SessionUtilities.parseSessionTitle(name)
            
            // Apply tag filter if provided
            if let filterTag = filterByTag, !filterTag.isEmpty, parsedTag != filterTag {
                Logger.log(level: .debug, "[ITermParser] Filtering out session with tag '\(parsedTag ?? "nil")' as it does not match '\(filterTag)'. Title: \(name)")
                continue
            }

            let uniqueIdentifier = SessionUtilities.generateSessionIdentifier(projectPath: parsedProj, tag: parsedTag ?? filterByTag, baseTTY: tty, iTermSessionID: sessionID)
            
            let sessionInfo = TerminalSessionInfo(
                sessionIdentifier: uniqueIdentifier,
                projectPath: parsedProj,
                tag: parsedTag ?? filterByTag, // Prefer tag from title, fallback to explicitly passed tag if any (e.g., during creation)
                fullTabTitle: name, // iTerm session name is the title
                tty: tty,
                isBusy: ProcessUtilities.getTTYBusyStatus(tty: tty), // Check actual TTY busy status
                windowIdentifier: winID,
                tabIdentifier: tabID,
                iTermSessionID: sessionID, // Store iTerm's own session ID
                pidFromTitle: parsedPID,
                ttyFromTitle: parsedTTYFromTitle
            )
            sessions.append(sessionInfo)
        }
        Logger.log(level: .info, "[ITermParser] Successfully parsed \(sessions.count) iTerm sessions.")
        return sessions
    }


    // Parses result from createNewWindowWithSessionScript: {win_id, tab_id, session_id, session_tty, "OK" | "ERROR:..."}
    static func parseNewWindowOutput(resultData: Any, scriptContent: String) throws -> (winID: String, tabID: String, sessionID: String, tty: String) {
        Logger.log(level: .debug, "[ITermParser] Parsing new window output. Data: \(resultData)")
        guard let parts = resultData as? [String], parts.count == 5 else {
            let errorMsg = "iTerm new window script returned unexpected data format: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        let winID = parts[0]
        let tabID = parts[1]
        let sessionID = parts[2]
        let tty = parts[3]
        let status = parts[4]

        if status != "OK" || winID.isEmpty || tabID.isEmpty || sessionID.isEmpty || tty.isEmpty {
            let errorDetail = status.hasPrefix("ERROR:") ? status : "One or more identifiers were empty. Full response: \(parts.joined(separator: ", "))"
            Logger.log(level: .error, "[ITermParser] Failed to create new iTerm window or get required IDs: \(errorDetail)")
            throw TerminalControllerError.appleScriptError(message: "Failed to create iTerm window or parse its details: \(errorDetail)", scriptContent: scriptContent)
        }
        Logger.log(level: .info, "[ITermParser] Successfully parsed new iTerm window: WinID \(winID), TabID \(tabID), SessionID \(sessionID), TTY \(tty)")
        return (winID, tabID, sessionID, tty)
    }

    // Parses result from createNewTabInWindowScript: {tab_id, session_id, session_tty, "OK" | "ERROR:..."}
    static func parseNewTabOutput(resultData: Any, scriptContent: String) throws -> (tabID: String, sessionID: String, tty: String) {
        Logger.log(level: .debug, "[ITermParser] Parsing new tab output. Data: \(resultData)")
        guard let parts = resultData as? [String], parts.count == 4 else {
            let errorMsg = "iTerm new tab script returned unexpected data format: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        let tabID = parts[0]
        let sessionID = parts[1]
        let tty = parts[2]
        let status = parts[3]

        if status != "OK" || tabID.isEmpty || sessionID.isEmpty || tty.isEmpty {
            let errorDetail = status.hasPrefix("ERROR:") ? status : "One or more identifiers were empty. Full response: \(parts.joined(separator: ", "))"
            Logger.log(level: .error, "[ITermParser] Failed to create new iTerm tab or get required IDs: \(errorDetail)")
            throw TerminalControllerError.appleScriptError(message: "Failed to create iTerm tab or parse its details: \(errorDetail)", scriptContent: scriptContent)
        }
        Logger.log(level: .info, "[ITermParser] Successfully parsed new iTerm tab: TabID \(tabID), SessionID \(sessionID), TTY \(tty)")
        return (tabID, sessionID, tty)
    }
    
    static func parseSetTitleOutput(resultData: Any, scriptContent: String) throws {
        Logger.log(level: .debug, "[ITermParser] Parsing set title output. Data: \(resultData)")
        guard let status = resultData as? String else {
            let errorMsg = "iTerm set title script returned non-string data: \(resultData)"
             Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        if status != "OK" {
            Logger.log(level: .error, "[ITermParser] Failed to set iTerm title: \(status)")
            throw TerminalControllerError.appleScriptError(message: "Set iTerm title failed: \(status)", scriptContent: scriptContent)
        }
        Logger.log(level: .info, "[ITermParser] iTerm title set successfully.")
    }

    static func parseReadSessionOutput(resultData: Any, scriptContent: String, linesToRead: Int) throws -> String {
        Logger.log(level: .debug, "[ITermParser] Parsing read session output for iTerm. Data type: \(type(of: resultData))")
        guard let content = resultData as? String else {
            if let errorStr = resultData as? String, errorStr.lowercased().hasPrefix("error:") {
                Logger.log(level: .error, "[ITermParser] Read iTerm session script returned error: \(errorStr)")
                throw TerminalControllerError.appleScriptError(message: "Read iTerm session failed: \(errorStr)", scriptContent: scriptContent)
            }
            let errorMsg = "iTerm read session script did not return string content. Output: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        
        var lines = content.components(separatedBy: .newlines)
        if linesToRead > 0 && lines.count > linesToRead {
            lines = Array(lines.suffix(linesToRead))
        }
        let processedOutput = lines.joined(separator: "\n")
        Logger.log(level: .info, "[ITermParser] Successfully parsed \(lines.count) lines from iTerm session output.")
        return processedOutput
    }
    
    static func parseSimpleOkErrorResult(resultData: Any, scriptContent: String, actionName: String) throws {
        Logger.log(level: .debug, "[ITermParser] Parsing simple OK/Error for \(actionName). Data: \(resultData)")
        guard let status = resultData as? String else {
            let errorMsg = "iTerm \(actionName) script returned non-string data: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        if status != "OK" && !status.contains("OK_") { // Check for OK or OK_VARIANT
            Logger.log(level: .error, "[ITermParser] iTerm \(actionName) failed: \(status)")
            throw TerminalControllerError.appleScriptError(message: "iTerm \(actionName) failed: \(status)", scriptContent: scriptContent)
        }
        Logger.log(level: .info, "[ITermParser] iTerm \(actionName) reported success: \(status)")
    }

    // New parser for PGID script result
    static func parsePgidOutput(resultData: Any, scriptContent: String, tty: String) throws -> pid_t? {
        Logger.log(level: .debug, "[ITermParser] Parsing PGID output for TTY \(tty). Data: \(resultData)")
        guard let resultStr = resultData as? String else {
            let errorMsg = "PGID script for TTY \(tty) did not return a string. Output: \(resultData)"
            Logger.log(level: .warn, "[ITermParser] \(errorMsg)")
            // Not throwing an error, as an empty or non-string result might mean no process/PGID found.
            // The caller (kill command) will decide how to handle a nil PGID.
            return nil
        }

        let trimmedPgidString = resultStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPgidString.isEmpty {
            Logger.log(level: .info, "[ITermParser] No PGID returned by script for TTY \(tty) (empty string).")
            return nil
        }
        
        if let parsedPgid = pid_t(trimmedPgidString), parsedPgid > 0 {
            Logger.log(level: .info, "[ITermParser] Successfully parsed PGID \(parsedPgid) for TTY \(tty).")
            return parsedPgid
        } else {
            Logger.log(level: .warn, "[ITermParser] Invalid PGID string '\(trimmedPgidString)' received for TTY \(tty).")
            return nil
        }
    }

    static func parseExecuteCommandOutput(
        appleScriptResultData: Any,
        scriptContent: String,
        logFilePath: String,
        completionMarker: String,
        isForeground: Bool,
        linesToCapture: Int,
        commandTimeout: Int, // Timeout for the command itself (foreground tailing / background initial read)
        backgroundStartupTimeout: Int // Specific timeout for background initial output capture
    ) throws -> (status: String, output: String, pid: String?) {
        Logger.log(level: .debug, "[ITermParser] Parsing iTerm execute command output. AS Data: \(appleScriptResultData), Log: \(logFilePath)")

        guard let resultParts = appleScriptResultData as? [String], resultParts.count >= 2 else {
            let errorMsg = "iTerm execute script returned unexpected data format: \(appleScriptResultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }

        let appleScriptStatus = resultParts[0]
        let appleScriptMessage = resultParts[1]
        // let appleScriptPID = resultParts.count > 2 ? resultParts[2] : nil // PID from AS not used currently

        if appleScriptStatus != "OK" {
            Logger.log(level: .error, "[ITermParser] iTerm execute AppleScript failed: \(appleScriptMessage)")
            return ("ERROR", appleScriptMessage, nil)
        }

        var finalStatus = "UNKNOWN"
        var outputText = ""

        if isForeground {
            Logger.log(level: .debug, "[ITermParser] Foreground command for iTerm. Tailing log \(logFilePath) for marker with timeout \(commandTimeout)s.")
            let tailResult = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: completionMarker,
                timeoutSeconds: commandTimeout > 0 ? commandTimeout : 60, // Default from AppConfig.foregroundCompletionSeconds if not specified
                linesToCapture: linesToCapture,
                controlIdentifier: "iTermFG"
            )
            outputText = tailResult.output

            if tailResult.timedOut {
                finalStatus = "TIMEOUT"
                outputText = outputText.replacingOccurrences(of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "") // Clean if present
                outputText += "\n---[ITERM_CMD_TIMEOUT_MARKER_NOT_FOUND]---"
                Logger.log(level: .warn, "[ITermParser] Foreground iTerm command timed out waiting for marker in \(logFilePath).")
            } else {
                finalStatus = "OK_COMPLETED_FG"
                outputText = outputText.replacingOccurrences(of: completionMarker, with: "") // Remove marker
                Logger.log(level: .info, "[ITermParser] Foreground iTerm command completed. Log: \(logFilePath).")
                // try? FileManager.default.removeItem(atPath: logFilePath) // Optional: remove log on success
            }
        } else { // Background
            finalStatus = "OK_SUBMITTED_BG"
            Logger.log(level: .debug, "[ITermParser] Background command for iTerm. Capturing initial output from \(logFilePath) with timeout \(backgroundStartupTimeout)s.")
            let initialOutputTail = ProcessUtilities.tailLogFileForMarker(
                logFilePath: logFilePath,
                marker: "TERMINATOR_ITERM_BG_NON_EXISTENT_MARKER_\(UUID().uuidString)", // Marker not expected to be found
                timeoutSeconds: backgroundStartupTimeout > 0 ? backgroundStartupTimeout : 2, // Default from AppConfig.backgroundStartupSeconds
                linesToCapture: linesToCapture,
                controlIdentifier: "iTermBGInitial"
            )
            let initialOutput = initialOutputTail.output.replacingOccurrences(of: "\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---", with: "")
            if !initialOutput.isEmpty {
                 outputText = "Initial output (up to \(linesToCapture) lines):\n\(initialOutput)"
            } else {
                outputText = "No initial output captured for background command."
            }
            Logger.log(level: .info, "[ITermParser] Background iTerm command submitted. Initial output check complete.")
        }
        return (finalStatus, outputText.trimmingCharacters(in: .whitespacesAndNewlines), nil) // PID not robustly available yet
    }
} 