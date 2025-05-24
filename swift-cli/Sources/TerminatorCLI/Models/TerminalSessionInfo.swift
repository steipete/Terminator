import Foundation

// SDD 3.2.5: Defines the structure for information about a terminal session.
// This is used by various commands like list, info, and as part of results for exec, focus, kill.
struct TerminalSessionInfo: Codable {
    let sessionIdentifier: String // User-friendly display name, e.g., "ProjectName / task_tag" or "🤖💥 ProjectName / task_tag"
    let projectPath: String?      // Absolute path to the project if applicable
    let tag: String               // The specific tag for this session
    let fullTabTitle: String?     // The complete, raw title of the tab/session as read from the terminal
    let tty: String?              // The TTY device path (e.g., /dev/ttys003)
    let isBusy: Bool              // True if a non-shell foreground process is detected on the TTY
    let windowIdentifier: String? // AppleScript ID or unique reference for the window
    let tabIdentifier: String?    // AppleScript ID or unique reference for the tab (Terminal) or session (iTerm)
    
    // New fields from SDD 3.2.4, parsed from the session title string itself
    let ttyFromTitle: String?     // TTY path that was embedded in the title at session creation
    let pidFromTitle: Int32?      // PID of the Terminator CLI that created the session, from title

    // Consider adding:
    // let processId: Int?        // PID of the shell process or primary process in the session (if reliably obtainable)
    // let lastActivity: Date?    // Timestamp of last detected activity or command execution

    // CodingKeys to match SDD 3.2.5 list --json output if needed, or for internal consistency
    enum CodingKeys: String, CodingKey {
        case sessionIdentifier = "session_identifier"
        case projectPath = "project_path"
        case tag
        case fullTabTitle = "full_tab_title"
        case tty
        case isBusy = "is_busy"
        case windowIdentifier = "window_identifier"
        case tabIdentifier = "tab_identifier"
        case ttyFromTitle = "tty_from_title"
        case pidFromTitle = "pid_from_title"
    }
    
    // Initializer to construct from raw components typically gathered via AppleScript + system calls
    init(
        sessionIdentifier: String,
        projectPath: String? = nil,
        tag: String,
        fullTabTitle: String? = nil,
        tty: String? = nil,
        isBusy: Bool = false,
        windowIdentifier: String? = nil,
        tabIdentifier: String? = nil,
        ttyFromTitle: String? = nil,
        pidFromTitle: Int32? = nil
    ) {
        self.sessionIdentifier = sessionIdentifier
        self.projectPath = projectPath
        self.tag = tag
        self.fullTabTitle = fullTabTitle
        self.tty = tty
        self.isBusy = isBusy
        self.windowIdentifier = windowIdentifier
        self.tabIdentifier = tabIdentifier
        self.ttyFromTitle = ttyFromTitle
        self.pidFromTitle = pidFromTitle
    }
} 