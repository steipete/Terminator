import Foundation

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

struct TerminalAppController {
    let appName: String // Resolved application name (e.g., "Terminal", "iTerm")
    let config: AppConfig
    private let specificController: TerminalControlling

    init(config: AppConfig) {
        self.config = config
        appName = config.terminalApp

        // Instantiate the specific controller based on appName
        switch appName.lowercased() {
        case "terminal", "terminal.app":
            Logger.log(level: .debug, "Instantiating AppleTerminalControl.")
            specificController = AppleTerminalControl(config: config, appName: appName)
        case "iterm", "iterm.app", "iterm2", "iterm2.app":
            Logger.log(level: .debug, "Instantiating ITermControl.")
            specificController = ITermControl(config: config, appName: appName)
        // Add case for "Ghosty" when its controller is ready
        // case "ghosty", "ghosty.app":
        //     self.specificController = GhostyControl(config: config, appName: self.appName)
        default:
            let errorMsg =
                "TerminalAppController: No specific controller available for unsupported terminal application: \(appName). This should have been caught by AppConfig validation."
            Logger.log(level: .fatal, errorMsg) // Log as fatal as this is a critical setup error.
            // To allow compilation and testing up to this point, but clearly indicate a failure:
            // Throwing from init is complex with non-optional `specificController`.
            // A fatalError is clear during development if this state is reached.
            // In a production build, this path might be guarded by earlier validation in AppConfig ensuring appName is
            // always supported.
            fatalError(errorMsg)
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
