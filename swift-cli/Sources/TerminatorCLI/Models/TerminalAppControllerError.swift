import Foundation

// Defines the errors that can be thrown by the TerminalAppController and its components.
// These are intended to be caught by the CLI subcommands and mapped to appropriate exit codes.
enum TerminalControllerError: Error, LocalizedError {
    case sessionNotFound(projectPath: String?, tag: String)
    case appleScriptError(message: String, scriptContent: String? = nil, underlyingError: Error? = nil)
    case busy(tty: String, processDescription: String?)
    case commandExecutionFailed(reason: String)
    case timeout(operation: String, timeoutSeconds: Int)
    case unsupportedTerminalApp(appName: String)
    case internalError(details: String)
    case processInteractionError(signal: String, pid: pid_t?, reason: String)
    case outputParsingError(details: String, rawOutput: String?)
    case fileIOError(path: String, operation: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let projectPath, let tag):
            return "Session for tag '\(tag)'" + (projectPath != nil ? " in project '\(projectPath!)'" : "") + " not found."
        case .appleScriptError(let message, _, _):
            return "AppleScript execution failed: \(message)"
        case .busy(let tty, let processDescription):
            var desc = "Session on TTY '\(tty)' is busy."
            if let procDesc = processDescription {
                desc += " Process: \(procDesc)"
            }
            return desc
        case .commandExecutionFailed(let reason):
            return "Command execution failed: \(reason)"
        case .timeout(let operation, let timeoutSeconds):
            return "Operation '\(operation)' timed out after \(timeoutSeconds) seconds."
        case .unsupportedTerminalApp(let appName):
            return "The configured terminal application ('\(appName)') is not supported for this operation."
        case .internalError(let details):
            return "An internal error occurred: \(details)"
        case .processInteractionError(let signal, let pid, let reason):
            return "Failed to interact with process (PID: \(pid ?? -1)) using signal \(signal). Reason: \(reason)"
        case .outputParsingError(let details, _):
            return "Failed to parse output: \(details)"
        case .fileIOError(let path, let operation, let underlyingError):
            return "File I/O error during '\(operation)' on path '\(path)': \(underlyingError.localizedDescription)"
        }
    }
    
    var scriptContent: String? {
        switch self {
        case .appleScriptError(_, let scriptContent, _):
            return scriptContent
        default:
            return nil
        }
    }
    
    var suggestedErrorCode: Int32 {
        switch self {
        case .sessionNotFound:
            return ErrorCodes.sessionNotFound
        case .appleScriptError:
            return ErrorCodes.appleScriptError
        case .busy:
            return ErrorCodes.sessionBusyError
        case .commandExecutionFailed:
            return ErrorCodes.commandFailedError
        case .timeout:
            return ErrorCodes.timeoutError
        case .unsupportedTerminalApp:
            return ErrorCodes.configurationError
        case .internalError:
            return ErrorCodes.internalError
        case .processInteractionError:
            return ErrorCodes.generalError
        case .outputParsingError:
            return ErrorCodes.internalError
        case .fileIOError:
            return ErrorCodes.generalError
        }
    }
} 