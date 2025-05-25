import Foundation

// MARK: - Helper Functions for ITermParser

enum ITermParserHelpers {
    static func parseWindowListForGrouping(resultData: Any, scriptContent: String) throws -> [(
        windowID: String,
        windowName: String
    )] {
        Logger.log(level: .debug, "[ITermParser] Parsing window list for grouping. Data: \(resultData)")
        guard let windowList = resultData as? [[String]] else {
            if let errorStr = resultData as? String, errorStr.contains("ERROR") {
                Logger.log(
                    level: .error,
                    "[ITermParser] listWindowsForGroupingScript returned an error string: \(errorStr)"
                )
                throw TerminalControllerError.appleScriptError(
                    message: "iTerm listWindowsForGroupingScript failed: \(errorStr)",
                    scriptContent: scriptContent
                )
            }
            if let arrayData = resultData as? [Any], arrayData.isEmpty {
                return []
            }
            Logger.log(
                level: .error,
                "[ITermParser] listWindowsForGroupingScript did not return an array of arrays as expected. Output: \(resultData)"
            )
            throw TerminalControllerError.appleScriptError(
                message: "iTerm listWindowsForGroupingScript did not return an array of arrays. Output: \(resultData)",
                scriptContent: scriptContent
            )
        }

        var resultWindows: [(windowID: String, windowName: String)] = []
        for windowEntry in windowList {
            guard windowEntry.count == 2 else { continue }
            let windowID = windowEntry[0]
            let windowName = windowEntry[1]
            resultWindows.append((windowID: windowID, windowName: windowName))
        }
        return resultWindows
    }

    static func parseCreateTabResult(resultData: Any, scriptContent: String) throws -> (
        windowID: String,
        sessionID: String
    ) {
        Logger.log(level: .debug, "[ITermParser] Parsing create tab result. Data: \(resultData)")

        if let resultArray = resultData as? [String], resultArray.count == 2 {
            return (windowID: resultArray[0], sessionID: resultArray[1])
        }

        if let resultStr = resultData as? String, resultStr.contains("ERROR:") {
            let errorMessage = resultStr.replacingOccurrences(of: "ERROR:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw TerminalControllerError.appleScriptError(
                message: "iTerm createTabInWindowScript failed: \(errorMessage)",
                scriptContent: scriptContent
            )
        }

        throw TerminalControllerError.appleScriptError(
            message: "iTerm createTabInWindowScript returned unexpected data format. Result: \(resultData)",
            scriptContent: scriptContent
        )
    }

    static func parseCreateWindowResult(resultData: Any, scriptContent: String) throws -> String {
        Logger.log(level: .debug, "[ITermParser] Parsing create window result. Data: \(resultData)")

        if let windowID = resultData as? String, !windowID.isEmpty {
            if windowID.contains("ERROR:") {
                let errorMessage = windowID.replacingOccurrences(of: "ERROR:", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw TerminalControllerError.appleScriptError(
                    message: "iTerm createWindowScript failed: \(errorMessage)",
                    scriptContent: scriptContent
                )
            }
            return windowID
        }

        throw TerminalControllerError.appleScriptError(
            message: "iTerm createWindowScript did not return a valid window ID. Result: \(resultData)",
            scriptContent: scriptContent
        )
    }

    static func extractSessionID(from compositeTabID: String) -> String? {
        let parts = compositeTabID.split(separator: ":")
        guard parts.count == 2 else {
            Logger.log(
                level: .error,
                "[ITermParser] Invalid composite tab ID format: '\(compositeTabID)'. Expected 'windowID:sessionID'."
            )
            return nil
        }
        return String(parts[1])
    }

    static func parseCreateNewWindowWithProfile(
        resultData: Any,
        scriptContent: String
    ) throws -> ITermParser.NewWindowResult {
        Logger.log(level: .debug, "[ITermParser] Parsing createWindowWithProfile output. Data: \(resultData)")
        guard let parts = resultData as? [String], parts.count == 5 else {
            let errorMsg = "iTerm createWindowWithProfile script returned unexpected data format: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        let winID = parts[0]
        let tabID = parts[1]
        let sessionID = parts[2]
        let tty = parts[3]
        let status = parts[4]

        if status != "OK" || winID.isEmpty || tabID.isEmpty || sessionID.isEmpty || tty.isEmpty {
            let errorDetail = status
                .hasPrefix("ERROR:") ? status :
                "One or more identifiers were empty. Full response: \(parts.joined(separator: ", "))"
            Logger.log(
                level: .error,
                "[ITermParser] Failed to create new iTerm window (via profile) or get required IDs: \(errorDetail)"
            )
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create iTerm window (via profile) or parse its details: \(errorDetail)",
                scriptContent: scriptContent
            )
        }
        Logger.log(
            level: .info,
            "[ITermParser] Successfully parsed new iTerm window (via profile): WinID \(winID), TabID \(tabID), SessionID \(sessionID), TTY \(tty)"
        )
        return ITermParser.NewWindowResult(winID: winID, tabID: tabID, sessionID: sessionID, tty: tty)
    }

    static func parseCreateTabInWindowWithProfile(
        resultData: Any,
        scriptContent: String
    ) throws -> ITermParser.NewTabResult {
        Logger.log(level: .debug, "[ITermParser] Parsing createTabInWindowWithProfile output. Data: \(resultData)")
        guard let parts = resultData as? [String], parts.count == 4 else {
            let errorMsg = "iTerm createTabInWindowWithProfile script returned unexpected data format: \(resultData)"
            Logger.log(level: .error, "[ITermParser] \(errorMsg)")
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        let tabID = parts[0]
        let sessionID = parts[1]
        let tty = parts[2]
        let status = parts[3]

        if status != "OK" || tabID.isEmpty || sessionID.isEmpty || tty.isEmpty {
            let errorDetail = status
                .hasPrefix("ERROR:") ? status :
                "One or more identifiers were empty. Full response: \(parts.joined(separator: ", "))"
            Logger.log(
                level: .error,
                "[ITermParser] Failed to create new iTerm tab (via profile) or get required IDs: \(errorDetail)"
            )
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create iTerm tab (via profile) or parse its details: \(errorDetail)",
                scriptContent: scriptContent
            )
        }
        Logger.log(
            level: .info,
            "[ITermParser] Successfully parsed new iTerm tab (via profile): TabID \(tabID), SessionID \(sessionID), TTY \(tty)"
        )
        return ITermParser.NewTabResult(tabID: tabID, sessionID: sessionID, tty: tty)
    }
}
