import Foundation
import AppKit // Required for NSAppleScript
import UniformTypeIdentifiers // Import for UTType
import CoreServices // For AE* constants

// Define AppleScript type constants using their FourCharCode UInt32 literal values
let typeText: DescType = 0x54455854       // 'TEXT' = kAEText
let typeBoolean: DescType = 0x626F6F6C    // 'bool' = kAEBoolean  
let typeInteger: DescType = 0x6C6F6E67    // 'long' = kAELongInteger
let typeNull: DescType = 0x6E756C6C       // 'null' = kAENull

enum AppleScriptError: Error {
    case scriptCompilationFailed(errorInfo: [String: Any])
    case scriptExecutionFailed(errorInfo: [String: Any])
    case permissionDenied // Specifically for error -1743
    case unknownError(message: String)
    case typeConversionError(message: String)
}

struct AppleScriptBridge {

    static func runAppleScript(script: String) -> Result<String, AppleScriptError> {
        Logger.log(level: .debug, "Attempting to run AppleScript:")
        // Log the script itself only at debug for PII
        Logger.log(level: .debug, "\\n--BEGIN APPLE SCRIPT--\\n\(script)\\n--END APPLE SCRIPT--\\n")

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            // This case should ideally not happen if the script string is valid Swift-side.
            // If it does, it might be an internal NSAppleScript issue or a very malformed script.
            Logger.log(level: .error, "Failed to initialize NSAppleScript. This is unexpected.")
            return .failure(.scriptCompilationFailed(errorInfo: ["NSAppleScriptErrorMessage": "Failed to initialize NSAppleScript object."]))
        }

        // Attempt to compile the script first (though NSAppleScript often does this implicitly on execution)
        // Disabling explicit compile as it can report errors that execute still handles or provides better info for.
        // if !appleScript.compileAndReturnError(&errorInfo) {
        //     Logger.log(level: .error, "AppleScript compilation failed.")
        //     if let info = errorInfo as? [String: Any] {
        //         Logger.log(level: .debug, "Compilation error details: \(info)")
        //         return .failure(.scriptCompilationFailed(errorInfo: info))
        //     }
        //     return .failure(.scriptCompilationFailed(errorInfo: [:]))
        // }

        let eventResult = appleScript.executeAndReturnError(&errorInfo)

        if let errorDict = errorInfo as? [String: Any] {
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            Logger.log(level: .error, "AppleScript execution error. Number: \(errorNumber), Message: \(errorMessage)")
            Logger.log(level: .debug, "Full AppleScript error details: \(errorDict)")
            if errorNumber == -1743 { // Permissions error
                return .failure(.permissionDenied)
            }
            return .failure(.scriptExecutionFailed(errorInfo: errorDict))
        }

        guard let resultDescriptor = eventResult.coerce(toDescriptorType: typeText) else {
            if eventResult.descriptorType == typeBoolean { // Check if it's a boolean
                 if eventResult.booleanValue {
                    return .success("true")
                 } else {
                    return .success("false")
                 }
            } else if eventResult.descriptorType == typeInteger {
                return .success("\(eventResult.int32Value)")
            }
            // If it's not text, boolean or int, and not an error, what is it?
            // It could be a list or record, which we'd need to parse differently.
            // For now, if direct coercion to text fails, and no error was reported, it's an issue.
            Logger.log(level: .warn, "AppleScript execution did not return a text-coercible result, and no error dictionary was provided. Descriptor type: \(eventResult.descriptorType.description)")
             // Check if the eventResult is typeNull, indicating no actual return value (e.g. `delay` command)
            if eventResult.descriptorType == typeNull {
                return .success("") // Successfully executed, but no string output
            }
            return .failure(.typeConversionError(message: "Result could not be coerced to String. Type was: \(eventResult.descriptorType.description)"))
        }
        
        Logger.log(level: .debug, "AppleScript executed successfully.")
        // Log output only at debug level
        Logger.log(level: .debug, "AppleScript result: \(resultDescriptor.stringValue ?? "N/A")")
        return .success(resultDescriptor.stringValue ?? "")
    }
} 