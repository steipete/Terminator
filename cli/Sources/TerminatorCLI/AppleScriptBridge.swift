import AppKit // Required for NSAppleScript
import CoreServices // For AE* constants
import Foundation
import UniformTypeIdentifiers // Import for UTType
import ApplicationServices // For AEDeterminePermissionToAutomateTarget

// Use Logger from the same module

// Define AppleScript type constants using their FourCharCode UInt32 literal values
let typeText: DescType = 0x5445_5854 // 'TEXT' = kAEText
let typeBoolean: DescType = 0x626F_6F6C // 'bool' = kAEBoolean
let typeInteger: DescType = 0x6C6F_6E67 // 'long' = kAELongInteger
let typeNull: DescType = 0x6E75_6C6C // 'null' = kAENull
let typeAEList: DescType = 0x6C69_7374 // 'list' = kAEList
let typeApplicationBundleID: DescType = 0x62756E64 // 'bund' = typeApplicationBundleID
let typeWildCard: DescType = 0x2A2A2A2A // '****' = typeWildCard
let errAEEventNotPermitted: OSStatus = -1743 // Permission denied
let procNotFound: OSStatus = -600 // Process not found

enum AppleScriptError: Error, Sendable {
    case scriptCompilationFailed(errorInfo: String) // Changed from [String: Any] to String
    case scriptExecutionFailed(errorInfo: String) // Changed from [String: Any] to String
    case permissionDenied // Specifically for error -1743
    case unknownError(message: String)
    case typeConversionError(message: String)
}

enum AppleScriptBridge {
    static func checkAndRequestPermission(for bundleIdentifier: String) -> Bool {
        Logger.log(level: .info, "Checking Apple Events permission for \(bundleIdentifier)")
        
        // Launch the target app if it's not running
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            Logger.log(level: .debug, "Target app is running with PID: \(app.processIdentifier)")
        } else {
            Logger.log(level: .info, "Target app not running, attempting to launch...")
            if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                Logger.log(level: .debug, "Launching app at URL: \(appURL)")
                
                if #available(macOS 11.0, *) {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.activates = false
                    
                    workspace.openApplication(at: appURL, configuration: configuration) { _, error in
                        if let error = error {
                            Logger.log(level: .error, "Failed to launch app: \(error)")
                        } else {
                            Logger.log(level: .debug, "Launched target app")
                        }
                    }
                    Thread.sleep(forTimeInterval: 1.0) // Give app time to launch
                } else {
                    // Fallback for older macOS versions
                    do {
                        try workspace.launchApplication(at: appURL, options: .withoutActivation, configuration: [:])
                        Logger.log(level: .debug, "Launched target app")
                        Thread.sleep(forTimeInterval: 1.0) // Give app time to launch
                    } catch {
                        Logger.log(level: .error, "Failed to launch app: \(error)")
                    }
                }
            }
        }
        
        // Create AEAddressDesc for the target application
        var targetAddress = AEAddressDesc()
        defer { AEDisposeDesc(&targetAddress) }
        
        // Convert bundle identifier to CFString and use it properly
        var err: OSErr = OSErr(noErr)
        
        bundleIdentifier.withCString { cString in
            err = AECreateDesc(
                typeApplicationBundleID,
                cString,
                bundleIdentifier.count,
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
        
        Logger.log(level: .info, "Permission check result: \(permissionStatus)")
        
        switch permissionStatus {
        case noErr:
            Logger.log(level: .info, "Apple Events permission granted for \(bundleIdentifier)")
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
    
    private static let permissionCheckQueue = DispatchQueue(label: "com.steipete.terminator.permissionCheck")
    private nonisolated(unsafe) static var hasCheckedPermission = false
    
    static func runAppleScript(script: String) -> Result<Any, AppleScriptError> {
        // Check permissions on first AppleScript execution
        var shouldCheckPermission = false
        permissionCheckQueue.sync {
            if !hasCheckedPermission {
                hasCheckedPermission = true
                shouldCheckPermission = true
            }
        }
        
        if shouldCheckPermission {
            // Determine which app we're targeting from the script
            let bundleID: String
            if script.contains("tell application \"Terminal\"") {
                bundleID = "com.apple.Terminal"
            } else if script.contains("tell application \"iTerm\"") {
                bundleID = "com.googlecode.iterm2"
            } else {
                bundleID = ""
            }
            
            if !bundleID.isEmpty {
                Logger.log(level: .info, "First AppleScript execution - checking permissions for \(bundleID)")
                if !checkAndRequestPermission(for: bundleID) {
                    Logger.log(level: .error, "Apple Events permission not granted for \(bundleID)")
                    return .failure(.permissionDenied)
                }
            }
        }
        
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
