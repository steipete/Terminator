import ApplicationServices
import Foundation

/// Utilities for checking and requesting accessibility permissions
enum AccessibilityPermission {
    /// Check if the current process has accessibility permissions
    /// These are required for sending keystrokes via System Events
    static func checkAccessibilityPermission() -> Bool {
        Logger.log(level: .info, "Checking accessibility permissions")

        // AXIsProcessTrusted checks if the current process is trusted for accessibility
        let isTrusted = AXIsProcessTrusted()

        Logger.log(level: .info, "Accessibility permission status: \(isTrusted ? "granted" : "not granted")")
        return isTrusted
    }

    /// Request accessibility permissions by prompting the user
    /// This will open System Preferences if permissions are not granted
    static func requestAccessibilityPermission() {
        Logger.log(level: .info, "Requesting accessibility permissions")

        // Create options dictionary to request permission with prompt
        // Using the string value directly to avoid concurrency issues
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary

        // This will prompt the user if permissions are not granted
        let isTrusted = AXIsProcessTrustedWithOptions(options)

        if isTrusted {
            Logger.log(level: .info, "Accessibility permissions already granted")
        } else {
            Logger.log(
                level: .warn,
                "Accessibility permission dialog shown - user must grant permission in System Settings"
            )
            Logger.log(
                level: .info,
                "User should enable access in System Settings > Privacy & Security > Accessibility"
            )
        }
    }

    /// Check if accessibility permissions are needed for the given script
    static func isAccessibilityNeededForScript(_ script: String) -> Bool {
        // Check if the script contains System Events keystroke commands
        script.contains("System Events") && script.contains("keystroke")
    }
    
    /// Check if accessibility permissions are needed
    static func isAccessibilityNeededForTerminalControl() -> Bool {
        // We always need accessibility for the new terminal control implementation
        return true
    }
    
    /// Check all required permissions for the given configuration
    static func checkAllPermissions(for bundleID: String) -> PermissionStatus {
        var status = PermissionStatus()
        
        // Always need Apple Events
        status.appleEvents = AppleScriptBridge.checkAndRequestPermission(for: bundleID)
        
        // Always check accessibility as it's required for our implementation
        status.accessibility = checkAccessibilityPermission()
        status.accessibilityRequired = true
        
        return status
    }
    
    /// Request all required permissions
    static func requestAllPermissions(for bundleID: String) {
        // Request Apple Events if needed
        _ = AppleScriptBridge.checkAndRequestPermission(for: bundleID)
        
        // Request Accessibility if not granted
        if !checkAccessibilityPermission() {
            requestAccessibilityPermission()
        }
    }
    
    /// Permission status for all required permissions
    struct PermissionStatus {
        var appleEvents: Bool = false
        var accessibility: Bool = false
        var accessibilityRequired: Bool = false
        
        var allGranted: Bool {
            return appleEvents && (!accessibilityRequired || accessibility)
        }
        
        var missingPermissions: [String] {
            var missing: [String] = []
            if !appleEvents { missing.append("Apple Events") }
            if accessibilityRequired && !accessibility { missing.append("Accessibility") }
            return missing
        }
        
        var description: String {
            if allGranted {
                return "All required permissions granted"
            } else {
                return "Missing permissions: \(missingPermissions.joined(separator: ", "))"
            }
        }
    }
}
