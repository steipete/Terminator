import Foundation

extension AppleTerminalControl {
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
            candidateSessions = existingSessions.filter { $0.projectPath == projectPath }
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] After filtering by project path '\(projectPath)': \(candidateSessions.count) candidates"
            )
        }

        // Find a non-busy session if available
        if let nonBusySession = candidateSessions.first(where: { !$0.isBusy }) {
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Using existing non-busy session: \(nonBusySession.sessionIdentifier)"
            )
            return nonBusySession
        }

        // If all are busy, take the first one
        if let busySession = candidateSessions.first {
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] All sessions busy, using first one: \(busySession.sessionIdentifier)"
            )
            return busySession
        }

        return nil
    }

    private func createNewSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        let newSessionTitle = SessionUtilities.generateSessionTitle(
            projectPath: projectPath,
            tag: tag,
            ttyDevicePath: nil,
            processId: nil
        )

        let shouldFocusNewTab = shouldFocus(focusPreference: focusPreference)

        // Find or create window
        let windowID = try findOrCreateWindow(tag: tag, shouldFocus: shouldFocusNewTab)

        // Create tab in window
        return try createTabInWindow(
            windowID: windowID,
            projectPath: projectPath,
            tag: tag,
            sessionTitle: newSessionTitle,
            shouldFocus: shouldFocusNewTab
        )
    }

    private func findOrCreateWindow(tag: String, shouldFocus: Bool) throws -> String {
        // Get existing windows
        let windowData = getExistingWindows()

        // Find suitable window
        if let windowID = findSuitableWindow(from: windowData, tag: tag) {
            return windowID
        }

        // Create new window
        return try createNewWindow(shouldFocus: shouldFocus)
    }

    private func getExistingWindows() -> [AppleTerminalWindowInfo] {
        let listWindowsScript = AppleTerminalScripts.listWindowsAndTabsWithTitlesScript(appName: appName)
        let listResult = AppleScriptBridge.runAppleScript(script: listWindowsScript)

        switch listResult {
        case let .success(data):
            let windows = parseWindowAndTabData(data)
            Logger.log(
                level: .debug,
                "[AppleTerminalControl] Found \(windows.count) windows with tabs"
            )
            return windows
        case let .failure(error):
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] Failed to list windows: \(error.localizedDescription). Will create new window."
            )
            return []
        }
    }

    private func findSuitableWindow(from windowData: [AppleTerminalWindowInfo], tag: String) -> String? {
        guard !windowData.isEmpty else { return nil }

        // Prefer a window with a tag that matches
        for window in windowData {
            for tab in window.tabs {
                if let parsedInfo = SessionUtilities.parseSessionTitle(title: tab.title), parsedInfo.tag == tag {
                    Logger.log(
                        level: .debug,
                        "[AppleTerminalControl] Found window \(window.id) with matching tag '\(tag)'"
                    )
                    return window.id
                }
            }
        }

        // If no matching window, use the first one
        let firstWindowID = windowData.first?.id
        Logger.log(
            level: .debug,
            "[AppleTerminalControl] No window with matching tag, using first window: \(firstWindowID ?? "none")"
        )
        return firstWindowID
    }

    private func createNewWindow(shouldFocus: Bool) throws -> String {
        let createWindowScript = AppleTerminalScripts.createWindowScript(
            appName: appName,
            shouldActivateTerminal: shouldFocus
        )
        let createWindowResult = AppleScriptBridge.runAppleScript(script: createWindowScript)

        switch createWindowResult {
        case let .success(data):
            if let windowIDStr = data as? String {
                Logger.log(
                    level: .info,
                    "[AppleTerminalControl] Created new window with ID: \(windowIDStr)"
                )
                return windowIDStr
            } else {
                throw TerminalControllerError.appleScriptError(
                    message: "Create window script returned non-string: \(data)",
                    scriptContent: createWindowScript,
                    underlyingError: nil
                )
            }
        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create new window: \(error.localizedDescription)",
                scriptContent: createWindowScript,
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
        let createTabResult = AppleScriptBridge.runAppleScript(script: createTabScript)

        switch createTabResult {
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
                message: "Failed to create new tab in window \(windowID): \(error.localizedDescription)",
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
        guard let resultArray = resultData as? [Any], resultArray.count >= 4 else {
            throw TerminalControllerError.appleScriptError(
                message: "Create tab script returned unexpected data: \(resultData)",
                scriptContent: createTabScript,
                underlyingError: nil
            )
        }

        let winID = resultArray[0] as? String
        let tabID = resultArray[1] as? String
        let tty = resultArray[2] as? String
        let title = resultArray[3] as? String

        guard let wID = winID, let tID = tabID, let ttyPath = tty else {
            throw TerminalControllerError.appleScriptError(
                message: "Create tab script returned array with non-string elements: \(resultArray)",
                scriptContent: createTabScript,
                underlyingError: nil
            )
        }

        Logger.log(
            level: .info,
            "[AppleTerminalControl] Successfully created new tab. Window: \(wID), Tab: \(tID), TTY: \(ttyPath), Title: \(title ?? "N/A")"
        )

        return TerminalSessionInfo(
            sessionIdentifier: "\(wID):\(tID)",
            projectPath: projectPath,
            tag: tag,
            fullTabTitle: sessionTitle,
            tty: ttyPath,
            isBusy: false,
            windowIdentifier: wID,
            tabIdentifier: tID,
            ttyFromTitle: nil,
            pidFromTitle: nil
        )
    }

    func parseWindowAndTabData(_ data: Any) -> [AppleTerminalWindowInfo] {
        guard let windowList = data as? [[Any]] else {
            Logger.log(
                level: .warn,
                "[AppleTerminalControl] Could not parse window list from AppleScript: Data is not [[Any]]. Got: \(data)"
            )
            return []
        }

        var result: [AppleTerminalWindowInfo] = []
        for windowEntry in windowList {
            guard windowEntry.count == 2,
                  let tabList = windowEntry[1] as? [[Any]]
            else {
                Logger.log(level: .warn, "[AppleTerminalControl] Skipping invalid window entry: \(windowEntry)")
                continue
            }

            // Window ID can be either String or Int
            let windowID: String
            if let winIDStr = windowEntry[0] as? String {
                windowID = winIDStr
            } else if let winIDInt = windowEntry[0] as? Int {
                windowID = String(winIDInt)
            } else if let winIDInt32 = windowEntry[0] as? Int32 {
                windowID = String(winIDInt32)
            } else {
                Logger.log(
                    level: .warn,
                    "[AppleTerminalControl] Skipping window with invalid ID type: \(type(of: windowEntry[0])) value: \(windowEntry[0])"
                )
                continue
            }

            var tabs: [AppleTerminalTabInfo] = []
            for tabEntry in tabList {
                guard tabEntry.count == 2 else {
                    Logger.log(
                        level: .warn,
                        "[AppleTerminalControl] Skipping invalid tab entry for window \(windowID): \(tabEntry)"
                    )
                    continue
                }

                // Tab ID can be either String or Int
                let tabID: String
                if let tidStr = tabEntry[0] as? String {
                    tabID = tidStr
                } else if let tidInt = tabEntry[0] as? Int {
                    tabID = String(tidInt)
                } else {
                    Logger.log(level: .warn, "[AppleTerminalControl] Skipping tab with invalid ID type: \(tabEntry[0])")
                    continue
                }

                let tabTitle = (tabEntry[1] as? String) ?? ""
                tabs.append(AppleTerminalTabInfo(id: tabID, title: tabTitle))
            }
            result.append(AppleTerminalWindowInfo(id: windowID, tabs: tabs))
        }
        return result
    }

    func attentesFocus(focusPreference: AppConfig.FocusCLIArgument, defaultFocusSetting: Bool) -> Bool {
        switch focusPreference {
        case .forceFocus:
            true
        case .noFocus:
            false
        case .default:
            defaultFocusSetting
        case .autoBehavior:
            defaultFocusSetting
        }
    }
}
