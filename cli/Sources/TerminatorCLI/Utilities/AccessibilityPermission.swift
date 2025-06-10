import Foundation
import ApplicationServices

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
            Logger.log(level: .warn, "Accessibility permission dialog shown - user must grant permission in System Settings")
            Logger.log(level: .info, "User should enable access in System Settings > Privacy & Security > Accessibility")
        }
    }
    
    /// Check if accessibility permissions are needed for the given script
    static func isAccessibilityNeededForScript(_ script: String) -> Bool {
        // Check if the script contains System Events keystroke commands
        return script.contains("System Events") && script.contains("keystroke")
    }
}