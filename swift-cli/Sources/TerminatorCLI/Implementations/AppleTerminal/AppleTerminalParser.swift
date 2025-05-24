import Foundation

enum AppleTerminalParser {
    static func parseSessionListOutput(resultStringOrArray: Any, scriptContent: String, filterByTag: String?) throws -> [TerminalSessionInfo] {
        var sessions: [TerminalSessionInfo] = []

        guard let resultArray = resultStringOrArray as? [[String]] else {
            let errorMsg = "AppleScript for listSessions (AppleTerminal) did not return the expected array of arrays structure."
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }

        for itemArray in resultArray {
            var sessionData: [String: String] = [:]
            for item in itemArray {
                let parts = item.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    sessionData[String(parts[0])] = String(parts[1])
                }
            }

            guard let windowIdentifier = sessionData["win_id"],
                  let tabIdentifier = sessionData["tab_id"],
                  let tty = sessionData["tty"],
                  let title = sessionData["title"]
            else {
                Logger.log(level: .warn, "Skipping malformed item from AppleScript (Terminal.app list): \\(itemArray)")
                continue
            }

            let parsedInfo = SessionUtilities.parseSessionTitle(title: title)
            let projectHash = parsedInfo?.projectHash
            let parsedTag = parsedInfo?.tag

            guard let tag = parsedTag else {
                Logger.log(level: .warn, "[AppleTerminalParser] Could not parse tag from session title: \\(title)")
                continue
            }

            if let filter = filterByTag, !filter.isEmpty, tag != filter {
                Logger.log(level: .debug, "Skipping session due to tag filter. Session tag: \\(tag), Filter: \\(filter)")
                continue
            }

            let sessionIdentifier = SessionUtilities.generateUserFriendlySessionIdentifier(projectPath: projectHash, tag: tag)
            let isBusy = ProcessUtilities.getTTYBusyStatus(tty: tty)

            let sessionInfo = TerminalSessionInfo(
                sessionIdentifier: sessionIdentifier,
                projectPath: projectHash,
                tag: tag,
                fullTabTitle: title,
                tty: tty.isEmpty ? nil : tty,
                isBusy: isBusy,
                windowIdentifier: windowIdentifier,
                tabIdentifier: tabIdentifier
            )
            sessions.append(sessionInfo)
        }
        return sessions
    }

    static func parseExecuteCommandResult(resultData: Any, scriptContent: String) throws -> (status: String, rawOutputOrMessage: String, pidString: String) {
        guard let resultArray = resultData as? [String], resultArray.count == 3 else {
            let errorMsg = "AppleScript for execute (AppleTerminal) did not return [String] with 3 elements. Result: \\(resultData)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        return (status: resultArray[0], rawOutputOrMessage: resultArray[1], pidString: resultArray[2])
    }

    static func parseCreateNewSessionOutput(resultData: Any, scriptContent: String, projectPath: String?, tag: String) throws -> TerminalSessionInfo {
        guard let resultArray = resultData as? [String], resultArray.count == 4 else {
            let errorMsg = "AppleScript for creating tab (AppleTerminal) did not return the expected [String] with 4 elements. Result: \\(resultData)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }
        let windowID = resultArray[0]
        let tabID = resultArray[1]
        let tty = resultArray[2]
        let actualTitleSet = resultArray[3]

        Logger.log(level: .info, "[AppleTerminalParser] Successfully parsed new tab. WindowID: \\(windowID), TabID: \\(tabID), TTY: \\(tty), Title: \\(actualTitleSet)")

        let parsedInfoAfterCreation = SessionUtilities.parseSessionTitle(title: actualTitleSet)
        let parsedProjectHash = parsedInfoAfterCreation?.projectHash
        let parsedTag = parsedInfoAfterCreation?.tag

        guard let finalTag = parsedTag, finalTag == tag else {
            let errorMsg = "Tag parsed from newly created tab ('\(parsedTag ?? "unknown_parsed_tag")') does not match requested tag ('\(tag)'). Full title set: '\(actualTitleSet)'"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.internalError(details: errorMsg)
        }

        // Determine the projectPath to store in TerminalSessionInfo.
        // If a projectPath was provided to create the session, use its hash.
        // Otherwise, use the hash parsed from the title (which might be NO_PROJECT_HASH).
        let sessionProjectPath = projectPath != nil ? SessionUtilities.generateProjectHash(projectPath: projectPath) : parsedProjectHash

        let sessionInfo = TerminalSessionInfo(
            sessionIdentifier: SessionUtilities.generateUserFriendlySessionIdentifier(projectPath: projectPath, tag: finalTag),
            projectPath: sessionProjectPath,
            tag: finalTag,
            fullTabTitle: actualTitleSet,
            tty: tty.isEmpty ? nil : tty,
            isBusy: false, // New tab is assumed not busy initially
            windowIdentifier: windowID,
            tabIdentifier: tabID
        )
        return sessionInfo
    }

    static func parseReadSessionOutput(resultData: Any, scriptContent: String, sessionInfo: TerminalSessionInfo, linesToRead: Int) throws -> ReadSessionResult {
        guard let historyOutput = resultData as? String else {
            let errorMsg = "AppleScript for reading session output (AppleTerminal) did not return a String. Result: \\(resultData)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(message: errorMsg, scriptContent: scriptContent)
        }

        var outputToReturn = historyOutput
        if linesToRead > 0 {
            let lines = historyOutput.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count > linesToRead {
                outputToReturn = lines.suffix(linesToRead).joined(separator: "\n")
            }
        }
        return ReadSessionResult(sessionInfo: sessionInfo, output: outputToReturn)
    }
}
