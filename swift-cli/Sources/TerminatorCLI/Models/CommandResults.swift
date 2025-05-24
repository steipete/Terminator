import Foundation

// Result struct for the executeCommand operation
struct ExecuteCommandResult {
    let sessionInfo: TerminalSessionInfo // Information about the session used/created
    let output: String?                  // Captured output (stdout/stderr combined) - Can be nil
    let exitCode: Int?                   // Exit code of the command, if applicable and obtainable
    let pid: pid_t?                      // PID of the executed command/shell process
    let wasKilledByTimeout: Bool
}

// Helper struct for decoding JSON response from AppleScript execute commands
struct AppleScriptExecuteResponse: Decodable {
    let status: String // e.g., "OK", "ERROR", "TIMEOUT"
    let message: String? // Error message or success message
    let log_file: String // Path to the output log file
    // pid might be added later if script can reliably return it
}

// Result struct for the readSessionOutput operation
struct ReadSessionResult {
    let sessionInfo: TerminalSessionInfo // Information about the session read from
    let output: String                   // The content read from the session's scrollback
}

// Result struct for the focusSession operation
struct FocusSessionResult {
    let focusedSessionInfo: TerminalSessionInfo // Information about the session that was focused
}

// Result struct for the killProcessInSession operation
struct KillSessionResult {
    let killedSessionInfo: TerminalSessionInfo // Information about the session where kill was attempted
    let killSuccess: Bool                      // True if the process was confirmed to be terminated or wasn't running
    let message: String?                       // Optional message describing the outcome of the kill attempt
    // Could add more details, e.g., signal used for termination, if process was found etc.

    init(killedSessionInfo: TerminalSessionInfo, killSuccess: Bool, message: String? = nil) {
        self.killedSessionInfo = killedSessionInfo
        self.killSuccess = killSuccess
        self.message = message
    }
} 