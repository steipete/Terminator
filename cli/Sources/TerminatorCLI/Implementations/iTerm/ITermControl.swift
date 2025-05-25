import Foundation

// MARK: - Supporting Types

private struct SessionData {
    let winID: String
    let tabID: String
    let sessionID: String
    let tty: String
}

// MARK: - ITermControl

/// Main controller for iTerm2 terminal integration
struct ITermControl: TerminalControlling {
    // MARK: - Properties

    let config: AppConfig
    let appName: String

    // MARK: - Initialization

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .info, "[ITermControl] Initialized with app name: \(appName)")
    }

    // MARK: - Session Finding and Creation

    /// Find an existing session or create a new one based on project path and tag
    func findOrCreateSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        Logger.log(
            level: .info,
            "[ITermControl] Finding or creating session for tag '\(tag)' with project path '\(projectPath ?? "N/A")'"
        )

        // Check for existing session
        Logger.log(level: .debug, "[ITermControl] About to call listSessions")
        let existingSessions = try listSessions(filterByTag: tag)
        Logger.log(level: .debug, "[ITermControl] listSessions returned \(existingSessions.count) sessions")

        if let existingSession = findMatchingSession(
            sessions: existingSessions,
            tag: tag,
            projectPath: projectPath
        ) {
            Logger.log(
                level: .info,
                "[ITermControl] Found existing session for tag '\(tag)'"
            )

            // Focus if needed
            if shouldFocus(focusPreference: focusPreference) {
                _ = try focusSession(params: FocusSessionParams(
                    projectPath: projectPath,
                    tag: tag
                ))
            }

            return existingSession
        }

        // Create new session
        return try createNewSession(
            projectPath: projectPath,
            tag: tag,
            focusPreference: focusPreference
        )
    }

    /// Wrapper for findOrCreateSession that matches the expected method name in extensions
    func findOrCreateSessionForITerm(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        try findOrCreateSession(
            projectPath: projectPath,
            tag: tag,
            focusPreference: focusPreference
        )
    }

    // MARK: - Private Session Creation Methods

    private func createNewSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        Logger.log(
            level: .info,
            "[ITermControl] Creating new session for tag '\(tag)'"
        )

        let newSessionTitle = SessionUtilities.generateSessionTitle(
            projectPath: projectPath,
            tag: tag,
            ttyDevicePath: nil,
            processId: nil
        )

        let shouldActivate = shouldFocus(focusPreference: focusPreference)

        // Create the session based on window grouping strategy
        let result = try createSessionWithGroupingStrategy(
            projectPath: projectPath,
            tag: tag,
            newSessionTitle: newSessionTitle,
            shouldActivate: shouldActivate
        )

        // Parse the result
        return try parseNewSessionResult(
            result: result,
            projectPath: projectPath,
            tag: tag,
            newSessionTitle: newSessionTitle
        )
    }

    private func createSessionWithGroupingStrategy(
        projectPath: String?,
        tag _: String,
        newSessionTitle _: String,
        shouldActivate: Bool
    ) throws -> Any {
        var targetWindowID: String?

        // Determine target window based on grouping strategy
        if config.windowGrouping == .project,
           let projPath = projectPath {
            targetWindowID = try findWindowForProject(projectPath: projPath)
        } else if config.windowGrouping == .smart {
            targetWindowID = try findFirstAvailableWindow()
        }

        // Create session script
        let createScript: String
        if let windowID = targetWindowID {
            createScript = ITermScripts.createTabInWindowWithProfileScript(
                appName: appName,
                windowID: windowID,
                profileName: config.iTermProfileName ?? "Default",
                shouldActivate: shouldActivate,
                selectTab: shouldActivate
            )
        } else {
            createScript = ITermScripts.createWindowWithProfileScript(
                appName: appName,
                profileName: config.iTermProfileName ?? "Default",
                shouldActivate: shouldActivate
            )
        }

        // Execute creation script
        let executionResult = AppleScriptBridge.runAppleScript(script: createScript)

        switch executionResult {
        case let .success(result):
            return result

        case let .failure(error):
            throw TerminalControllerError.appleScriptError(
                message: "Failed to create new iTerm2 session: \(error.localizedDescription)",
                scriptContent: createScript,
                underlyingError: error
            )
        }
    }

    private func parseNewSessionResult(
        result: Any,
        projectPath: String?,
        tag: String,
        newSessionTitle: String
    ) throws -> TerminalSessionInfo {
        // Parse based on whether we created a window or tab
        let sessionData: SessionData

        if let windowResult = try? ITermParser.parseCreateNewWindowWithProfile(
            resultData: result,
            scriptContent: ""
        ) {
            sessionData = SessionData(
                winID: windowResult.winID,
                tabID: windowResult.tabID,
                sessionID: windowResult.sessionID,
                tty: windowResult.tty
            )
        } else if let tabResult = try? ITermParser.parseCreateTabInWindowWithProfile(
            resultData: result,
            scriptContent: ""
        ) {
            // For tab creation, we need to get the window ID from existing sessions
            let sessions = try listSessions(filterByTag: nil)
            let windowID = sessions.first?.windowIdentifier ?? "unknown"
            sessionData = SessionData(
                winID: windowID,
                tabID: tabResult.tabID,
                sessionID: tabResult.sessionID,
                tty: tabResult.tty
            )
        } else {
            throw TerminalControllerError.internalError(
                details: "Failed to parse iTerm session creation result"
            )
        }

        let compositeTabIdentifier = "\(sessionData.tabID):\(sessionData.sessionID)"
        let userFriendlyIdentifier = SessionUtilities.generateUserFriendlySessionIdentifier(
            projectPath: projectPath,
            tag: tag
        )

        let sessionInfo = TerminalSessionInfo(
            sessionIdentifier: userFriendlyIdentifier,
            projectPath: projectPath,
            tag: tag,
            fullTabTitle: newSessionTitle,
            tty: sessionData.tty,
            isBusy: false,
            windowIdentifier: sessionData.winID,
            tabIdentifier: compositeTabIdentifier,
            ttyFromTitle: nil,
            pidFromTitle: nil
        )

        Logger.log(
            level: .info,
            "[ITermControl] Successfully created new session: \(sessionInfo.sessionIdentifier)"
        )

        return sessionInfo
    }

    // MARK: - Window Finding Methods

    private func findWindowForProject(projectPath: String) throws -> String? {
        let projectHash = SessionUtilities.generateProjectHash(projectPath: projectPath)
        let searchPrefix = "\(SessionUtilities.sessionPrefix)PROJECT_HASH=\(projectHash)::"

        let sessions = try listSessions(filterByTag: nil)

        for session in sessions {
            if let sessionTitle = session.fullTabTitle,
               sessionTitle.hasPrefix(searchPrefix),
               let windowID = session.windowIdentifier {
                Logger.log(
                    level: .debug,
                    "[ITermControl] Found window \(windowID) for project: \(projectPath)"
                )
                return windowID
            }
        }

        return nil
    }

    private func findFirstAvailableWindow() throws -> String? {
        let sessions = try listSessions(filterByTag: nil)

        if let firstSession = sessions.first,
           let windowID = firstSession.windowIdentifier {
            Logger.log(
                level: .debug,
                "[ITermControl] Using first available window: \(windowID)"
            )
            return windowID
        }

        return nil
    }

    // MARK: - Session Matching Methods

    private func findMatchingSession(
        sessions: [TerminalSessionInfo],
        tag: String,
        projectPath: String?
    ) -> TerminalSessionInfo? {
        for session in sessions where session.tag == tag {
            if let projectPath {
                if session.projectPath == projectPath {
                    return session
                }
            } else {
                return session
            }
        }
        return nil
    }

    // MARK: - Focus Preference Methods

    private func shouldFocus(focusPreference: AppConfig.FocusCLIArgument) -> Bool {
        switch focusPreference {
        case .forceFocus:
            true
        case .noFocus:
            false
        case .default, .autoBehavior:
            config.defaultFocusOnAction
        }
    }
}
