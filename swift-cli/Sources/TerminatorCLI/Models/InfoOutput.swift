import Foundation

// Structure for JSON output of 'info' command (SDD 3.2.5)
struct InfoOutput: Codable {
    let version: String
    let managedSessions: [[String: AnyCodable]] 
    let activeConfiguration: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case version
        case managedSessions = "sessions"
        case activeConfiguration = "configuration"
    }
    
    // Nested struct to represent session info within InfoOutput
    // This mirrors key fields from TerminalSessionInfo for the purpose of JSON output for 'info'
    struct SessionInfo: Codable {
        let sessionIdentifier: String
        let projectPath: String?
        let tag: String
        let fullTabTitle: String?
        let tty: String?
        let isBusy: Bool
        let windowIdentifier: String?
        let tabIdentifier: String?

        // Initializer to map from the main TerminalSessionInfo struct
        // This assumes TerminalSessionInfo is available in the scope where this is used, or this can be adapted.
        init(from info: TerminalSessionInfo) { // Assuming TerminalSessionInfo is defined elsewhere
            self.sessionIdentifier = info.sessionIdentifier
            self.projectPath = info.projectPath
            self.tag = info.tag
            self.fullTabTitle = info.fullTabTitle
            self.tty = info.tty
            self.isBusy = info.isBusy
            self.windowIdentifier = info.windowIdentifier
            self.tabIdentifier = info.tabIdentifier
        }
        
        // Helper to convert to [String: Any] for easier construction of [[String: AnyCodable]]
        // This is used before wrapping values with AnyCodable
        var asDictionary: [String: Any?] { // Changed to Any? to handle nil projectPath more directly
             return [
                "session_identifier": sessionIdentifier,
                "project_path": projectPath as Any,
                "tag": tag,
                "full_tab_title": fullTabTitle as Any,
                "tty": tty as Any,
                "is_busy": isBusy,
                "window_identifier": windowIdentifier as Any,
                "tab_identifier": tabIdentifier as Any
             ].compactMapValues { $0 } // Removes keys with nil values if that's desired, or handle NSNull in AnyCodable
        }
    }
} 