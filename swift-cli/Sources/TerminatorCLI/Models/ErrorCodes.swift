import Foundation

enum ErrorCodes {
    static let success: Int32 = 0
    static let generalError: Int32 = 1 // Catch-all for general errors
    static let configurationError: Int32 = 2 // Errors in configuration
    static let appleScriptError: Int32 = 3 // Errors from AppleScript execution
    static let ghostyCommunicationError: Int32 = 4 // Example, if Ghosty has specific issues
    static let processExecutionError: Int32 = 5 // For errors from ProcessUtilities
    static let internalError: Int32 = 6 // For unexpected internal errors
    static let improperUsage: Int32 = 64 // Standard exit code for command line usage errors (EX_USAGE)
    static let sessionNotFound: Int32 = 7 // Specific error for session not found
    static let sessionBusyError: Int32 = 8 // Specific error for session being busy
    static let unsupportedOperationForApp: Int32 = 9 // Operation not supported for the current app
    static let timeoutError: Int32 = 10 // Command execution timed out
    static let commandFailedError: Int32 = 11 // A command sent to a session failed

    // Add more specific error codes as needed
}
