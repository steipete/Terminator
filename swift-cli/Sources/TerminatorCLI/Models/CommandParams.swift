import Foundation

// Parameter struct for the executeCommand operation
struct ExecuteCommandParams {
    let projectPath: String?
    let tag: String
    let command: String? // Made optional for session preparation without command (SDD 3.1.5 / 3.2.5)
    let executionMode: ExecutionMode
    let linesToCapture: Int
    let timeout: Int // In seconds
    let focusPreference: AppConfig.FocusCLIArgument

    enum ExecutionMode {
        case foreground
        case background
    }
}

// Parameter struct for the readSessionOutput operation
struct ReadSessionParams {
    let projectPath: String?
    let tag: String
    let linesToRead: Int
    let focusPreference: AppConfig.FocusCLIArgument // To control if focusing the tab is desired before reading
}

// Parameter struct for the focusSession operation
struct FocusSessionParams {
    let projectPath: String?
    let tag: String
    // No explicit focusPreference here, as the `focus` command itself implies force-focus.
}

// Parameter struct for the killProcessInSession operation
struct KillSessionParams {
    let projectPath: String?
    let tag: String
    let focusPreference: AppConfig.FocusCLIArgument // For any ancillary actions (e.g., screen clearing post-kill)
    // sigintWait and sigtermWait will be taken from AppConfig
}
