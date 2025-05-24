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
        case let .sessionNotFound(projectPath, tag):
            return "Session for tag '\(tag)'" + (projectPath != nil ? " in project '\(projectPath!)'" : "") + " not found."
        case let .appleScriptError(message, _, _):
            return "AppleScript execution failed: \(message)"
        case let .busy(tty, processDescription):
            var desc = "Session on TTY '\(tty)' is busy."
            if let procDesc = processDescription {
                desc += " Process: \(procDesc)"
            }
            return desc
        case let .commandExecutionFailed(reason):
            return "Command execution failed: \(reason)"
        case let .timeout(operation, timeoutSeconds):
            return "Operation '\(operation)' timed out after \(timeoutSeconds) seconds."
        case let .unsupportedTerminalApp(appName):
            return "The configured terminal application ('\(appName)') is not supported for this operation."
        case let .internalError(details):
            return "An internal error occurred: \(details)"
        case let .processInteractionError(signal, pid, reason):
            return "Failed to interact with process (PID: \(pid ?? -1)) using signal \(signal). Reason: \(reason)"
        case let .outputParsingError(details, _):
            return "Failed to parse output: \(details)"
        case let .fileIOError(path, operation, underlyingError):
            return "File I/O error during '\(operation)' on path '\(path)': \(underlyingError.localizedDescription)"
        }
    }

    var scriptContent: String? {
        switch self {
        case let .appleScriptError(_, scriptContent, _):
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
