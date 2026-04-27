import Foundation
@preconcurrency import ApplicationServices

protocol TerminalControlling {
    // Initializer for the specific controller.
    // It needs AppConfig for settings and appName to confirm it's the right controller (or for minor variations if one
    // controller handles multiple similar apps).
    init(config: AppConfig, appName: String)

    func listSessions(filterByTag: String?) throws -> [TerminalSessionInfo]

    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult

    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult

    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult

    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult
}

struct UnsupportedTerminalControl: TerminalControlling {
    let config: AppConfig
    let appName: String

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .warn, "Unsupported terminal application: \(appName)")
    }

    func listSessions(filterByTag _: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .warn, "Cannot list sessions for unsupported terminal application: \(appName)")
        throw TerminalControllerError.unsupportedTerminalApp(appName: appName)
    }

    func executeCommand(params _: ExecuteCommandParams) throws -> ExecuteCommandResult {
        throw TerminalControllerError.unsupportedTerminalApp(appName: appName)
    }

    func readSessionOutput(params _: ReadSessionParams) throws -> ReadSessionResult {
        throw TerminalControllerError.unsupportedTerminalApp(appName: appName)
    }

    func focusSession(params _: FocusSessionParams) throws -> FocusSessionResult {
        throw TerminalControllerError.unsupportedTerminalApp(appName: appName)
    }

    func killProcessInSession(params _: KillSessionParams) throws -> KillSessionResult {
        throw TerminalControllerError.unsupportedTerminalApp(appName: appName)
    }
}

struct TerminalAppController {
    let appName: String // Resolved application name (e.g., "Terminal", "iTerm")
    let config: AppConfig
    private let specificController: TerminalControlling

    init(config: AppConfig) {
        self.config = config
        appName = config.terminalApp

        // Check permissions for the target app
        let bundleID = switch appName.lowercased() {
        case "terminal", "terminal.app":
            "com.apple.Terminal"
        case "iterm", "iterm.app", "iterm2", "iterm2.app":
            "com.googlecode.iterm2"
        default:
            ""
        }

        if !bundleID.isEmpty {
            Logger.log(level: .info, "Checking Apple Events permission for \(appName)")
            if !AppleScriptBridge.checkAndRequestPermission(for: bundleID) {
                Logger.log(
                    level: .warn,
                    "Apple Events permission not granted for \(appName). Operations will fail."
                )
            }
            
            // Always check accessibility permission
            if !AXIsProcessTrusted() {
                Logger.log(
                    level: .warn,
                    "Accessibility permission not granted. Requesting permission..."
                )
                // Request permission
                AccessibilityPermission.requestAccessibilityPermission()
            }
        }

        // Instantiate controllers that use AX for UI and AppleScript for terminal operations
        switch appName.lowercased() {
        case "terminal", "terminal.app":
            Logger.log(level: .debug, "Instantiating AppleTerminalControl with Accessibility support.")
            specificController = AppleTerminalControl(config: config, appName: appName)
        case "iterm", "iterm.app", "iterm2", "iterm2.app":
            Logger.log(level: .debug, "Instantiating ITermControl with Accessibility support.")
            specificController = ITermControl(config: config, appName: appName)
        // Add case for "Ghosty" when its controller is ready
        // case "ghosty", "ghosty.app":
        //     self.specificController = GhostyControl(config: config, appName: self.appName)
        default:
            specificController = UnsupportedTerminalControl(config: config, appName: appName)
        }
        
        Logger.log(
            level: .info,
            "TerminalAppController initialized for \(appName) using \(String(describing: type(of: specificController)))."
        )
    }

    func listSessions(filterByTag: String? = nil) throws -> [TerminalSessionInfo] {
        Logger.log(
            level: .info,
            "[Controller Facade] Listing sessions for \(appName) with filter: \(filterByTag ?? "none")"
        )
        return try specificController.listSessions(filterByTag: filterByTag)
    }

    func executeCommand(params: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .info, "[Controller Facade] Executing command for tag: \(params.tag)")
        return try specificController.executeCommand(params: params)
    }

    func readSessionOutput(params: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .info, "[Controller Facade] Reading session output for tag: \(params.tag)")
        return try specificController.readSessionOutput(params: params)
    }

    func focusSession(params: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .info, "[Controller Facade] Focusing session for tag: \(params.tag)")
        return try specificController.focusSession(params: params)
    }

    func killProcessInSession(params: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .info, "[Controller Facade] Killing process in session for tag: \(params.tag)")
        return try specificController.killProcessInSession(params: params)
    }
}
