import Foundation

// MARK: - Helper Methods Extension for ITermControl

extension ITermControl {
    /// Validate and extract session identifiers from a TerminalSessionInfo
    func validateSessionIdentifiers(_ sessionInfo: TerminalSessionInfo) throws
        -> (windowID: String, sessionID: String, tty: String) {
        guard let compositeTabID = sessionInfo.tabIdentifier,
              Self.extractTabID(from: compositeTabID) != nil,
              let sessionID = Self.extractSessionID(from: compositeTabID),
              let windowID = sessionInfo.windowIdentifier,
              let tty = sessionInfo.tty else {
            throw TerminalControllerError.internalError(
                details: "iTerm session missing required identifiers. Session: \(sessionInfo)"
            )
        }

        return (windowID, sessionID, tty)
    }
}
