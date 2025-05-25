import AppKit // Required for NSAppleScript
import CoreServices // For AE* constants
import Foundation
import UniformTypeIdentifiers // Import for UTType

// Define AppleScript type constants using their FourCharCode UInt32 literal values
let typeText: DescType = 0x5445_5854 // 'TEXT' = kAEText
let typeBoolean: DescType = 0x626F_6F6C // 'bool' = kAEBoolean
let typeInteger: DescType = 0x6C6F_6E67 // 'long' = kAELongInteger
let typeNull: DescType = 0x6E75_6C6C // 'null' = kAENull
let typeAEList: DescType = 0x6C69_7374 // 'list' = kAEList

enum AppleScriptError: Error {
    case scriptCompilationFailed(errorInfo: [String: Any])
    case scriptExecutionFailed(errorInfo: [String: Any])
    case permissionDenied // Specifically for error -1743
    case unknownError(message: String)
    case typeConversionError(message: String)
}

enum AppleScriptBridge {
    static func runAppleScript(script: String) -> Result<Any, AppleScriptError> {
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

        // Handle different descriptor types
        switch eventResult.descriptorType {
        case typeText:
            Logger.log(level: .debug, "AppleScript returned Text.")
            Logger.log(level: .debug, "AppleScript result: \(eventResult.stringValue ?? "N/A")")
            return .success(eventResult.stringValue ?? "")
        case typeBoolean:
            Logger.log(level: .debug, "AppleScript returned Boolean: \(eventResult.booleanValue)")
            return .success(eventResult.booleanValue) // Return Bool directly
        case typeInteger:
            Logger.log(level: .debug, "AppleScript returned Integer: \(eventResult.int32Value)")
            return .success(eventResult.int32Value) // Return Int32 directly
        case typeNull:
            Logger.log(level: .debug, "AppleScript returned Null.")
            return .success("") // Or perhaps a specific representation for null, like NSNull() or a custom enum case
        case typeAEList:
            Logger.log(level: .debug, "AppleScript returned a List.")
            var swiftArray: [Any] = []
            // NSAppleEventDescriptor lists are 1-indexed
            for i in 1...eventResult.numberOfItems {
                if let itemDescriptor = eventResult.atIndex(i) {
                    // Recursively process list items to convert them to Swift types
                    // This simple version tries to get stringValue; a more robust one would check itemDescriptor.descriptorType
                    switch itemDescriptor.descriptorType {
                    case typeText:
                        swiftArray.append(itemDescriptor.stringValue ?? "")
                    case typeBoolean:
                        swiftArray.append(itemDescriptor.booleanValue)
                    case typeInteger:
                        swiftArray.append(itemDescriptor.int32Value)
                    case typeNull: // Represent AppleScript null as NSNull or a custom type if needed
                        swiftArray.append(NSNull()) // Example: using NSNull
                    default:
                        // For other types in list, attempt to get string value or log/handle error
                        if let strVal = itemDescriptor.stringValue {
                             swiftArray.append(strVal)
                        } else {
                            Logger.log(level: .warn, "List item at index \(i) is of unhandled type \(itemDescriptor.descriptorType.description) and not string convertible.")
                            swiftArray.append("<Unsupported List Item Type: \(itemDescriptor.descriptorType.description)>")
                        }
                    }
                }
            }
            Logger.log(level: .debug, "Converted AppleScript list to Swift array: \(swiftArray)")
            return .success(swiftArray)
        default:
            // Attempt to coerce to text as a final fallback, or fail if not appropriate
            Logger.log(level: .warn, "AppleScript execution returned unhandled descriptor type: \(eventResult.descriptorType.description). Attempting to coerce to String.")
            if let stringValue = eventResult.stringValue {
                Logger.log(level: .debug, "AppleScript result (coerced from unhandled type): \(stringValue)")
                return .success(stringValue)
            }
            Logger.log(level: .error, "Result could not be coerced to String. Type was: \(eventResult.descriptorType.description)")
            return .failure(.typeConversionError(message: "Result could not be coerced to expected Swift type. AppleScript type was: \(eventResult.descriptorType.description)"))
        }
    }
}
