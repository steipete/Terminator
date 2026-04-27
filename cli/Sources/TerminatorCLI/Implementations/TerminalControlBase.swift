import Foundation
@preconcurrency import ApplicationServices

final class AsyncResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?

    func store(_ value: Result<T, Error>) {
        lock.withLock {
            result = value
        }
    }

    func load() -> Result<T, Error>? {
        lock.withLock {
            result
        }
    }
}

/// Base class for terminal controllers that use Accessibility APIs where possible and AppleScript where necessary
class TerminalControlBase: TerminalControlling, @unchecked Sendable {
    let config: AppConfig
    let appName: String
    let axProvider: AccessibilityProviding
    let bundleIdentifier: String
    
    required init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        self.axProvider = AXorcistProvider()
        
        // Determine bundle identifier
        switch appName.lowercased() {
        case "terminal", "terminal.app":
            self.bundleIdentifier = "com.apple.Terminal"
        case "iterm", "iterm.app", "iterm2", "iterm2.app":
            self.bundleIdentifier = "com.googlecode.iterm2"
        case "ghosty", "ghosty.app":
            self.bundleIdentifier = "com.mitchellh.ghostty"
        default:
            self.bundleIdentifier = ""
        }
        
        Logger.log(level: .info, "Initialized controller for \(appName) using Accessibility APIs with AppleScript for terminal operations")
    }
    
    // MARK: - TerminalControlling Protocol
    
    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .debug, "Using Accessibility API for session enumeration")
        
        // Ensure we have permission
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        return try listSessionsViaAccessibility(filterByTag: filterByTag)
    }
    
    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        // Command execution must use AppleScript as there's no AX equivalent
        return try executeCommandViaAppleScript(params: params)
    }
    
    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        // Output reading must use AppleScript as AX only provides visible text
        return try readSessionOutputViaAppleScript(params: params)
    }
    
    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .debug, "Using Accessibility API for session focus")
        
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        return try focusSessionViaAccessibility(params: params)
    }
    
    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        // Process killing requires AppleScript for TTY access
        return try killProcessInSessionViaAppleScript(params: params)
    }
    
    // MARK: - Accessibility Implementation
    
    private func listSessionsViaAccessibility(filterByTag: String?) throws -> [TerminalSessionInfo] {
        let startTime = Date()
        
        // Ensure we have permission
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        // Use async context for AX operations
        let sessions = try runAsyncBlocking { [self] in
            var allSessions: [TerminalSessionInfo] = []
            
            // Find all windows
            let windows = try await axProvider.findWindows(for: bundleIdentifier)
            Logger.log(level: .debug, "Found \(windows.count) windows via AX")
            
            // Process each window
            for (windowIndex, window) in windows.enumerated() {
                let windowTitle = try await axProvider.getTitle(of: window) ?? "Window \(windowIndex + 1)"
                
                // Find tabs in this window
                let tabs = try await axProvider.findTabs(in: window)
                Logger.log(level: .debug, "Found \(tabs.count) tabs in window '\(windowTitle)'")
                
                // Process each tab
                for (tabIndex, tab) in tabs.enumerated() {
                    if let tabTitle = try await axProvider.getTitle(of: tab) {
                        // Parse session info from title
                        if let sessionInfo = SessionTitleParser.parseSessionInfo(
                            from: tabTitle,
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
        Logger.log(level: .debug, "AX session enumeration took \(String(format: "%.1f", duration))ms")
        
        return sessions
    }
    
    private func focusSessionViaAccessibility(params: FocusSessionParams) throws -> FocusSessionResult {
        let startTime = Date()
        
        guard axProvider.isAccessibilityEnabled() else {
            throw AccessibilityError.permissionDenied
        }
        
        let result = try runAsyncBlocking { [self] in
            // Find the session
            let sessions = try await findSessionsViaAccessibility(tag: params.tag)
            
            guard let targetSession = sessions.first else {
                throw TerminalControllerError.sessionNotFound(projectPath: params.tag, tag: params.tag)
            }
            
            // Activate the application
            try await axProvider.activateApplication(bundleID: bundleIdentifier)
            
            // Find and focus the window/tab
            let windows = try await axProvider.findWindows(for: bundleIdentifier)
            
            for window in windows {
                let tabs = try await axProvider.findTabs(in: window)
                
                for tab in tabs {
                    if let tabTitle = try await axProvider.getTitle(of: tab),
                       SessionTitleParser.sessionMatches(title: tabTitle, tag: params.tag) {
                        
                        // Raise the window
                        try await axProvider.raiseWindow(window)
                        
                        // Select the tab
                        try await axProvider.setSelectedTab(tab, in: window)
                        
                        // Focus the window
                        try await axProvider.focusElement(window)
                        
                        let duration = Date().timeIntervalSince(startTime) * 1000
                        Logger.log(level: .debug, "AX focus operation took \(String(format: "%.1f", duration))ms")
                        
                        return FocusSessionResult(
                            focusedSessionInfo: targetSession
                        )
                    }
                }
            }
            
            throw TerminalControllerError.sessionNotFound(projectPath: params.tag, tag: params.tag)
        }
        
        return result
    }
    
    private func findSessionsViaAccessibility(tag: String) async throws -> [TerminalSessionInfo] {
        var sessions: [TerminalSessionInfo] = []
        
        let windows = try await axProvider.findWindows(for: bundleIdentifier)
        
        for (windowIndex, window) in windows.enumerated() {
            let tabs = try await axProvider.findTabs(in: window)
            
            for (tabIndex, tab) in tabs.enumerated() {
                if let tabTitle = try await axProvider.getTitle(of: tab),
                   let sessionInfo = SessionTitleParser.parseSessionInfo(
                       from: tabTitle,
                       windowIndex: windowIndex + 1,
                       tabIndex: tabIndex + 1
                   ),
                   sessionInfo.tag == tag {
                    sessions.append(sessionInfo)
                }
            }
        }
        
        return sessions
    }
    
    // MARK: - AppleScript Operations (to be implemented by subclasses)
    // These operations require AppleScript as they have no Accessibility API equivalent
    
    func executeCommandViaAppleScript(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        fatalError("Subclass must implement executeCommandViaAppleScript")
    }
    
    func readSessionOutputViaAppleScript(params: ReadSessionParams) throws -> ReadSessionResult {
        fatalError("Subclass must implement readSessionOutputViaAppleScript")
    }
    
    func killProcessInSessionViaAppleScript(params: KillSessionParams) throws -> KillSessionResult {
        fatalError("Subclass must implement killProcessInSessionViaAppleScript")
    }
    
    // MARK: - Utility Methods
    
    private func runAsyncBlocking<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
        let group = DispatchGroup()
        group.enter()
        let resultBox = AsyncResultBox<T>()
        
        Task.detached {
            do {
                let value = try await operation()
                resultBox.store(.success(value))
            } catch {
                resultBox.store(.failure(error))
            }
            group.leave()
        }
        
        group.wait()
        
        switch resultBox.load() {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw TerminalControllerError.internalError(details: "Async operation did not complete")
        }
    }
}

// MARK: - Session Title Parser

struct SessionTitleParser {
    static func parseSessionInfo(from title: String, windowIndex: Int, tabIndex: Int) -> TerminalSessionInfo? {
        // Look for our session marker
        guard title.contains("::TERMINATOR_SESSION::") else {
            return nil
        }
        
        // Extract components
        var tag: String?
        var ttyPath: String?
        var pid: Int?
        
        let components = title.components(separatedBy: "::")
        for component in components {
            if component.hasPrefix("PROJECT_HASH=") {
                // We don't need project hash for session info
                _ = String(component.dropFirst("PROJECT_HASH=".count))
            } else if component.hasPrefix("TAG=") {
                tag = String(component.dropFirst("TAG=".count))
            } else if component.hasPrefix("TTY_PATH=") {
                ttyPath = String(component.dropFirst("TTY_PATH=".count))
            } else if component.hasPrefix("PID=") {
                if let pidStr = String(component.dropFirst("PID=".count)).components(separatedBy: " ").first,
                   let pidInt = Int(pidStr) {
                    pid = pidInt
                }
            }
        }
        
        guard let sessionTag = tag else {
            return nil
        }
        
        let sessionIdentifier = "🤖💥 \(sessionTag)"
        
        return TerminalSessionInfo(
            sessionIdentifier: sessionIdentifier,
            projectPath: nil, // We don't have the project path from the title
            tag: sessionTag,
            fullTabTitle: title,
            tty: ttyPath,
            isBusy: false, // Will be determined separately
            windowIdentifier: "window_\(windowIndex)",
            tabIdentifier: "tab_\(tabIndex)",
            ttyFromTitle: ttyPath,
            pidFromTitle: pid.map { Int32($0) }
        )
    }
    
    static func sessionMatches(title: String, tag: String) -> Bool {
        return title.contains("::TAG=\(tag)::")
    }
    
    static func extractTag(from title: String) -> String? {
        guard title.contains("::TERMINATOR_SESSION::") else {
            return nil
        }
        
        let components = title.components(separatedBy: "::")
        for component in components {
            if component.hasPrefix("TAG=") {
                return String(component.dropFirst("TAG=".count))
            }
        }
        
        return nil
    }
}
