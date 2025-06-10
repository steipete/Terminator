import AppKit // Required for NSAppleScript
import CoreServices // For AE* constants
import Foundation
import UniformTypeIdentifiers // Import for UTType
import ApplicationServices // For AEDeterminePermissionToAutomateTarget

// Define AppleScript type constants using their FourCharCode UInt32 literal values
let typeText: DescType = 0x5445_5854 // 'TEXT' = kAEText
let typeBoolean: DescType = 0x626F_6F6C // 'bool' = kAEBoolean
let typeInteger: DescType = 0x6C6F_6E67 // 'long' = kAELongInteger
let typeNull: DescType = 0x6E75_6C6C // 'null' = kAENull
let typeAEList: DescType = 0x6C69_7374 // 'list' = kAEList
let typeApplicationBundleID: DescType = 0x62756E64 // 'bund' = typeApplicationBundleID
let typeWildCard: DescType = 0x2A2A2A2A // '****' = typeWildCard
let errAEEventNotPermitted: OSStatus = -1743 // Permission denied

enum AppleScriptError: Error, Sendable {
    case scriptCompilationFailed(errorInfo: String) // Changed from [String: Any] to String
    case scriptExecutionFailed(errorInfo: String) // Changed from [String: Any] to String
    case permissionDenied // Specifically for error -1743
    case unknownError(message: String)
    case typeConversionError(message: String)
}

enum AppleScriptBridge {
    static func checkAndRequestPermission(for bundleIdentifier: String) -> Bool {
        Logger.log(level: .debug, "Checking Apple Events permission for \(bundleIdentifier)")
        
        // Create AEAddressDesc for the target application
        var targetAddress = AEAddressDesc()
        defer { AEDisposeDesc(&targetAddress) }
        
        // Convert bundle identifier to data
        let bundleIDData = bundleIdentifier.data(using: .utf8)!
        
        // Create the address descriptor for the target app
        let err = bundleIDData.withUnsafeBytes { bytes in
            AECreateDesc(
                typeApplicationBundleID,
                bytes.baseAddress!,
                bytes.count,
                &targetAddress
            )
        }
        
        if err != noErr {
            Logger.log(level: .error, "Failed to create AEAddressDesc for \(bundleIdentifier): \(err)")
            return false
        }
        
        // Check permission and ask user if needed
        let permissionStatus = AEDeterminePermissionToAutomateTarget(
            &targetAddress,
            typeWildCard,
            typeWildCard,
            true // askUserIfNeeded
        )
        
        switch permissionStatus {
        case noErr:
            Logger.log(level: .debug, "Apple Events permission granted for \(bundleIdentifier)")
            return true
        case OSStatus(errAEEventNotPermitted):
            Logger.log(level: .error, "Apple Events permission denied for \(bundleIdentifier)")
            return false
        case OSStatus(procNotFound):
            Logger.log(level: .error, "Target application \(bundleIdentifier) not found")
            return false
        default:
            Logger.log(level: .error, "Apple Events permission check failed with error: \(permissionStatus)")
            return false
        }
    }
    
    static func runAppleScript(script: String) -> Result<Any, AppleScriptError> {
        Logger.log(level: .debug, "Attempting to run AppleScript:")
        // Log the script itself only at debug for PII
        Logger.log(level: .debug, "\\n--BEGIN APPLE SCRIPT--\\n\(script)\\n--END APPLE SCRIPT--\\n")

        var errorInfo: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else {
            // This case should ideally not happen if the script string is valid Swift-side.
            // If it does, it might be an internal NSAppleScript issue or a very malformed script.
            Logger.log(level: .error, "Failed to initialize NSAppleScript. This is unexpected.")
            return .failure(
                .scriptCompilationFailed(
                    errorInfo: "Failed to initialize NSAppleScript object."
                )
            )
        }

        let eventResult = appleScript.executeAndReturnError(&errorInfo)

        if let errorDict = errorInfo as? [String: Any] {
            let errorMessage = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            let errorNumber = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            Logger.log(level: .error, "AppleScript execution error. Number: \(errorNumber), Message: \(errorMessage)")
            Logger.log(level: .debug, "Full AppleScript error details: \(errorDict)")
            if errorNumber == -1743 { // Permissions error
                return .failure(.permissionDenied)
            }
            let errorInfo = "Error \(errorNumber): \(errorMessage)"
            return .failure(.scriptExecutionFailed(errorInfo: errorInfo))
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
            return processListDescriptor(eventResult)
        default:
            // Attempt to coerce to text as a final fallback, or fail if not appropriate
            Logger.log(
                level: .warn,
                "AppleScript execution returned unhandled descriptor type: \(eventResult.descriptorType.description). Attempting to coerce to String."
            )
            if let stringValue = eventResult.stringValue {
                Logger.log(level: .debug, "AppleScript result (coerced from unhandled type): \(stringValue)")
                return .success(stringValue)
            }
            Logger.log(
                level: .error,
                "Result could not be coerced to String. Type was: \(eventResult.descriptorType.description)"
            )
            return .failure(
                .typeConversionError(
                    message: "Result could not be coerced to expected Swift type. AppleScript type was: \(eventResult.descriptorType.description)"
                )
            )
        }
    }

    // MARK: - Private Helper Methods

    private static func processListDescriptor(_ eventResult: NSAppleEventDescriptor) -> Result<Any, AppleScriptError> {
        Logger.log(level: .debug, "AppleScript returned a List.")
        var swiftArray: [Any] = []

        // NSAppleEventDescriptor lists are 1-indexed
        let itemCount = eventResult.numberOfItems
        if itemCount > 0 {
            for index in 1...itemCount {
                if let itemDescriptor = eventResult.atIndex(index) {
                    let value = convertDescriptorToSwiftValue(itemDescriptor, index: index)
                    swiftArray.append(value)
                }
            }
        }

        Logger.log(level: .debug, "Converted AppleScript list to Swift array: \(swiftArray)")
        return .success(swiftArray)
    }

    private static func convertDescriptorToSwiftValue(_ descriptor: NSAppleEventDescriptor, index: Int) -> Any {
        switch descriptor.descriptorType {
        case typeText:
            return descriptor.stringValue ?? ""
        case typeBoolean:
            return descriptor.booleanValue
        case typeInteger:
            return descriptor.int32Value
        case typeNull:
            return NSNull()
        case typeAEList:
            // Handle nested lists recursively
            var nestedArray: [Any] = []
            let nestedItemCount = descriptor.numberOfItems
            if nestedItemCount > 0 {
                for nestedIndex in 1...nestedItemCount {
                    if let nestedDescriptor = descriptor.atIndex(nestedIndex) {
                        let nestedValue = convertDescriptorToSwiftValue(nestedDescriptor, index: nestedIndex)
                        nestedArray.append(nestedValue)
                    }
                }
            }
            return nestedArray
        default:
            // For other types, attempt to get string value
            if let strVal = descriptor.stringValue {
                return strVal
            } else {
                Logger.log(
                    level: .warn,
                    "List item at index \(index) is of unhandled type \(descriptor.descriptorType.description) and not string convertible."
                )
                return "<Unsupported List Item Type: \(descriptor.descriptorType.description)>"
            }
        }
    }
}
