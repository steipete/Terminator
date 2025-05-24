import Foundation

// ErrorCodes.swift
// Defines standardized exit codes for the Terminator CLI.

struct ErrorCodes {
    // General Errors (as per SDD 3.2.8)
    static let success: Int32 = 0
    static let generalError: Int32 = 1 // Generic error
    static let configurationError: Int32 = 2 // Configuration problem (e.g., invalid TERMINATOR_APP, Ghosty validation failed)
    static let appleScriptError: Int32 = 3   // AppleScript execution failed or returned an error
    static let sessionNotFound: Int32 = 4    // Specified session (tag/project) not found
    static let sessionBusyError: Int32 = 5   // Session is busy and operation cannot proceed (e.g., pre-exec check)
    static let commandFailedError: Int32 = 6 // Command executed but returned non-zero exit status (less common for this CLI, primarily for exec output)
    static let timeoutError: Int32 = 7       // Operation timed out (e.g., waiting for foreground command marker)
    static let internalError: Int32 = 8      // Unexpected internal CLI error (e.g., parsing issue, missing identifiers)
    static let permissionError: Int32 = 9    // macOS Permissions error (e.g. Automation, TCC)

    // Specific command errors can also use these or have their own if needed.
} 