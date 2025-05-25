import Foundation

// Placeholder for Ghosty terminal control.
// SDD indicates Ghosty support is best-effort V1.
// Most operations will likely throw .unsupportedTerminalApp or .internalError.

struct GhostyControl: TerminalControlling {
    let config: AppConfig
    let appName: String

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .warn, "[GhostyControl] Initialized. Most operations are not yet supported.")
    }

    func listSessions(filterByTag _: String?) throws -> [TerminalSessionInfo] {
        Logger.log(level: .warn, "[GhostyControl] listSessions called, but not implemented.")
        // As per SDD 3.2.7.1: If Ghosty doesn't support listing, return empty or error.
        // Returning empty is safer for now until full spec for Ghosty list is defined.
        return []
        // Alternatively, to indicate definite non-support:
        // throw TerminalControllerError.unsupportedTerminalApp(appName: "Ghosty (listSessions)")
    }

    func executeCommand(params _: ExecuteCommandParams) throws -> ExecuteCommandResult {
        Logger.log(level: .error, "[GhostyControl] executeCommand is not implemented for Ghosty.")
        throw TerminalControllerError.unsupportedTerminalApp(appName: "Ghosty (executeCommand)")
    }

    func readSessionOutput(params _: ReadSessionParams) throws -> ReadSessionResult {
        Logger.log(level: .error, "[GhostyControl] readSessionOutput is not implemented for Ghosty.")
        throw TerminalControllerError.unsupportedTerminalApp(appName: "Ghosty (readSessionOutput)")
    }

    func focusSession(params _: FocusSessionParams) throws -> FocusSessionResult {
        Logger.log(level: .error, "[GhostyControl] focusSession is not implemented for Ghosty.")
        throw TerminalControllerError.unsupportedTerminalApp(appName: "Ghosty (focusSession)")
    }

    func killProcessInSession(params _: KillSessionParams) throws -> KillSessionResult {
        Logger.log(level: .error, "[GhostyControl] killProcessInSession is not implemented for Ghosty.")
        throw TerminalControllerError.unsupportedTerminalApp(appName: "Ghosty (killProcessInSession)")
    }
}
