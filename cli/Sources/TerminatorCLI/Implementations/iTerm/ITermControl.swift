import Foundation
@preconcurrency import ApplicationServices

/// Implementation for iTerm2 that uses Accessibility APIs where possible
final class ITermControl: TerminalControlBase, @unchecked Sendable {
    
    required init(config: AppConfig, appName: String) {
        super.init(config: config, appName: appName)
    }
    
    // MARK: - AppleScript Operations (required for terminal functionality)
    
    override func executeCommandViaAppleScript(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        // Delegate to the extension implementation
        return try executeCommandImpl(params: params)
    }
    
    override func readSessionOutputViaAppleScript(params: ReadSessionParams) throws -> ReadSessionResult {
        // This is implemented in ITermWindowAndTabManagement extension
        // We need to reimplement here since we can't override from extension
        Logger.log(
            level: .info,
            "[ITermControl] Reading session output for tag: \(params.tag), project: \(params.projectPath ?? "nil")"
        )

        let existingSessions = try listSessionsViaAppleScript(filterByTag: params.tag)
        let targetProjectHash = params.projectPath != nil ? SessionUtilities
            .generateProjectHash(projectPath: params.projectPath) : "NO_PROJECT"

        guard let sessionInfo = existingSessions
            .first(where: { ($0.projectPath ?? "NO_PROJECT") == targetProjectHash }) else {
            throw TerminalControllerError.sessionNotFound(projectPath: params.projectPath, tag: params.tag)
        }

        guard let compositeTabID = sessionInfo.tabIdentifier,
              let sessionID = ITermControl.extractSessionID(from: compositeTabID),
              sessionInfo.windowIdentifier != nil
        else {
            throw TerminalControllerError
                .internalError(
                    details: "iTerm session found for reading is missing sessionID or windowID. Session: \(sessionInfo)"
                )
        }

        let shouldActivateITermForRead = attentesFocus(
            focusPreference: params.focusPreference,
            defaultFocusSetting: config.defaultFocusOnAction
        )

        let script = ITermScripts.readSessionOutputScript(
            appName: appName,
            sessionID: sessionID,
            linesToRead: params.linesToRead,
            shouldActivateITerm: shouldActivateITermForRead
        )

        let appleScriptResult = AppleScriptBridge.runAppleScript(script: script)

        switch appleScriptResult {
        case let .success(resultData):
            let outputString = try ITermParser.parseReadSessionOutput(
                resultData: resultData,
                scriptContent: script,
                linesToRead: params.linesToRead
            )
            return ReadSessionResult(sessionInfo: sessionInfo, output: outputString)

        case let .failure(error):
            let errorMsg = "Failed to read iTerm session output for tag \(params.tag): \(error.localizedDescription)"
            Logger.log(level: .error, errorMsg)
            throw TerminalControllerError.appleScriptError(
                message: errorMsg,
                scriptContent: script,
                underlyingError: error
            )
        }
    }
    
    override func killProcessInSessionViaAppleScript(params: KillSessionParams) throws -> KillSessionResult {
        // Delegate to the extension implementation
        return try killProcessInSessionImpl(params: params)
    }
    
    // MARK: - iTerm2 Specific Accessibility Operations
    
    private func listSessionsViaAccessibilityEnhanced(filterByTag: String?) throws -> [TerminalSessionInfo] {
        let startTime = Date()
        
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        let sessions = try runAsyncBlocking { [self] in
            var allSessions: [TerminalSessionInfo] = []
            
            // iTerm2 window structure is different from Terminal.app
            let windows = try await axProvider.findWindows(for: bundleIdentifier)
            
            for (windowIndex, window) in windows.enumerated() {
                // iTerm2 uses a different tab structure
                let tabs = try await findITermTabs(in: window)
                
                for (tabIndex, tab) in tabs.enumerated() {
                    // Get tab title
                    if let title = try await getITermTabTitle(tab: tab, window: window) {
                        if let sessionInfo = SessionTitleParser.parseSessionInfo(
                            from: title,
                            windowIndex: windowIndex + 1,
                            tabIndex: tabIndex + 1
                        ) {
                            if filterByTag == nil || sessionInfo.tag == filterByTag {
                                allSessions.append(sessionInfo)
                            }
                        }
                    }
                }
            }
            
            return allSessions
        }
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        Logger.log(level: .info, "Enhanced AX enumeration for iTerm2 completed in \(String(format: "%.1f", duration))ms, found \(sessions.count) sessions")
        
        return sessions
    }
    
    private func focusSessionViaAccessibilityEnhanced(params: FocusSessionParams) throws -> FocusSessionResult {
        let startTime = Date()
        
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        let result = try runAsyncBlocking { [self] in
            // Find all windows
            let windows = try await axProvider.findWindows(for: bundleIdentifier)
            
            for (windowIndex, window) in windows.enumerated() {
                let tabs = try await findITermTabs(in: window)
                
                for (tabIndex, tab) in tabs.enumerated() {
                    if let title = try await getITermTabTitle(tab: tab, window: window),
                       SessionTitleParser.sessionMatches(title: title, tag: params.tag) {
                        
                        // Activate iTerm2
                        try await axProvider.activateApplication(bundleID: bundleIdentifier)
                        
                        // Raise and focus the window
                        try await axProvider.raiseWindow(window)
                        try await axProvider.focusElement(window)
                        
                        // Select the tab
                        try await selectITermTab(tab: tab, window: window)
                        
                        let duration = Date().timeIntervalSince(startTime) * 1000
                        Logger.log(level: .debug, "AX focus operation for iTerm2 took \(String(format: "%.1f", duration))ms")
                        
                        // Create a session info for the result
                        let sessionInfo = TerminalSessionInfo(
                            sessionIdentifier: "🤖💥 \(params.tag)",
                            projectPath: nil,
                            tag: params.tag,
                            fullTabTitle: title,
                            tty: nil,
                            isBusy: false,
                            windowIdentifier: "window_\(windowIndex + 1)",
                            tabIdentifier: "tab_\(tabIndex + 1)"
                        )
                        
                        return FocusSessionResult(
                            focusedSessionInfo: sessionInfo
                        )
                    }
                }
            }
            
            throw TerminalControllerError.sessionNotFound(projectPath: params.tag, tag: params.tag)
        }
        
        return result
    }
    
    private func findITermTabs(in window: AXUIElement) async throws -> [AXUIElement] {
        // iTerm2 structure: Window -> AXTabGroup -> AXRadioButton (tabs)
        // Similar to Terminal but may have additional UI elements
        var tabs: [AXUIElement] = []
        
        // First try to find tab group directly
        if let children = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: window) as? [AXUIElement] {
            for child in children {
                if let role = try await axProvider.getAttribute(kAXRoleAttribute as String, of: child) as? String {
                    if role == "AXTabGroup" {
                        // Found tab group, get tabs
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
        }
        
        // If no tabs found in tab group, iTerm might be in a different mode
        // Try to find tabs in the window's toolbar
        if tabs.isEmpty {
            tabs = try await findITermTabsInToolbar(window: window)
        }
        
        return tabs
    }
    
    private func findITermTabsInToolbar(window: AXUIElement) async throws -> [AXUIElement] {
        var tabs: [AXUIElement] = []
        
        // Look for toolbar
        if let children = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: window) as? [AXUIElement] {
            for child in children {
                if let role = try await axProvider.getAttribute(kAXRoleAttribute as String, of: child) as? String,
                   role == "AXToolbar" {
                    // Search toolbar for tab-like elements
                    if let toolbarChildren = try await axProvider.getAttribute(kAXChildrenAttribute as String, of: child) as? [AXUIElement] {
                        for toolbarChild in toolbarChildren {
                            if let childRole = try await axProvider.getAttribute(kAXRoleAttribute as String, of: toolbarChild) as? String,
                               (childRole == "AXButton" || childRole == "AXRadioButton") {
                                // Check if this looks like a tab
                                if let title = try await axProvider.getTitle(of: toolbarChild),
                                   title.contains("::TERMINATOR_SESSION::") {
                                    tabs.append(toolbarChild)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        return tabs
    }
    
    private func getITermTabTitle(tab: AXUIElement, window: AXUIElement) async throws -> String? {
        // First try to get title directly from tab
        if let title = try await axProvider.getTitle(of: tab) {
            return title
        }
        
        // If tab is selected, we might be able to get it from window title
        if let isSelected = try await axProvider.getAttribute(kAXValueAttribute as String, of: tab) as? Int,
           isSelected == 1 {
            // Get window title which might contain session info
            if let windowTitle = try await axProvider.getTitle(of: window) {
                // iTerm window title often includes the current tab's title
                return windowTitle
            }
        }
        
        return nil
    }
    
    private func selectITermTab(tab: AXUIElement, window: AXUIElement) async throws {
        // Try to click/select the tab
        let pressResult = AXUIElementPerformAction(tab, kAXPressAction as CFString)
        
        if pressResult != .success {
            // Try setting it as selected
            let selectResult = AXUIElementSetAttributeValue(tab, kAXValueAttribute as CFString, 1 as CFNumber)
            
            if selectResult != .success {
                throw AccessibilityError.actionFailed("select iTerm tab")
            }
        }
    }
    
    private func enrichSessionsWithAppleScriptData(_ axSessions: [TerminalSessionInfo]) throws -> [TerminalSessionInfo] {
        // Get full session data via AppleScript
        // TODO: Implement AppleScript enrichment for iTerm
        let scriptSessions: [TerminalSessionInfo] = []
        
        // Create maps for lookup
        var scriptSessionByTag: [String: TerminalSessionInfo] = [:]
        var scriptSessionByPosition: [String: TerminalSessionInfo] = [:]
        
        for session in scriptSessions {
            scriptSessionByTag[session.tag] = session
            // Extract window and tab indices from identifiers if available
            if let windowId = session.windowIdentifier,
               let tabId = session.tabIdentifier {
                let posKey = "\(windowId)-\(tabId)"
                scriptSessionByPosition[posKey] = session
            }
        }
        
        // Enrich AX sessions
        return axSessions.map { axSession in
            // Try to match by tag first (more reliable)
            if let scriptSession = scriptSessionByTag[axSession.tag] {
                // Create enriched session with additional data
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
            
            // Fall back to position matching
            if let windowId = axSession.windowIdentifier,
               let tabId = axSession.tabIdentifier {
                let posKey = "\(windowId)-\(tabId)"
                if let scriptSession = scriptSessionByPosition[posKey] {
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
    
    // MARK: - Session Management
    
    func findOrCreateSession(
        projectPath: String?,
        tag: String,
        focusPreference: AppConfig.FocusCLIArgument
    ) throws -> TerminalSessionInfo {
        // For now, just try to find an existing session
        // Full implementation would need to create new sessions if not found
        let existingSessions = try listSessions(filterByTag: tag)
        
        if let session = existingSessions.first {
            return session
        }
        
        // TODO: Implement session creation for iTerm
        throw TerminalControllerError.notImplemented(feature: "iTerm session creation")
    }
    
    // MARK: - Utility Methods
    
    private func runAsyncBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        
        Task.detached {
            do {
                let value = try await operation()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw TerminalControllerError.internalError(details: "Async operation did not complete")
        }
    }
}

// Feature flags have been removed - we now always use Accessibility APIs where possible

// MARK: - Supporting Types

private struct SessionData {
    let winID: String
    let tabID: String
    let sessionID: String
    let tty: String
}