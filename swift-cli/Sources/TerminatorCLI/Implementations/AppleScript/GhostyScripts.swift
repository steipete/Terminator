import Foundation

// GhostyScripts.swift
// Contains AppleScript snippets for interacting with the Ghosty terminal application.
// As per SDD, Ghosty support is "best-effort" for V1, so scripts are minimal.

struct GhostyScripts {

    static func listSessionsScript(appName: String) -> String {
        // For V1, listing distinct sessions in Ghosty might not be feasible or reliable.
        // This script can just try to activate it to see if it's running.
        // The parser will likely return an empty list or a single placeholder.
        return """
        tell application "\(appName)"
            if not running then error "Ghosty is not running."
            -- Ghosty may not have scriptable windows/tabs/sessions in a way we can list.
            -- Returning a placeholder or relying on parser to return empty.
            return "GHOSTY_LIST_PLACEHOLDER"
        end tell
        """
    }

    static func executeCommandScript(
        appName: String,
        commandToRunRaw: String,
        outputLogFilePath: String, // For potential output redirection
        completionMarker: String,  // For foreground completion detection
        isForeground: Bool,
        shouldActivate: Bool
    ) -> String {
        let quotedLogFilePath = "'\(outputLogFilePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        var shellCommandToExecute: String

        if commandToRunRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // If command is empty, Ghosty might just need to be focused or prepared.
            // For now, we'll assume an empty `do script` is harmless or Ghosty handles it.
            shellCommandToExecute = ""
        } else if isForeground {
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\''")
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePath) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePath))"
        } else { // Background
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\''")
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePath) 2>&1) & disown"
        }
        
        let appleScriptSafeShellCommand = shellCommandToExecute
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let activateBlock = shouldActivate ? "activate" : ""

        // Ghosty might always operate on the current/frontmost window/session or create a new one.
        // It might not support `do script in specific_tab`.
        return """
        tell application "\(appName)"
            if not running then 
                if \(shouldActivate) then activate else run
                delay 0.5
            else if \(shouldActivate) then
                activate
            end if
            
            try
                do script "\(appleScriptSafeShellCommand)"
                return "OK_COMMAND_SUBMITTED"
            on error errMsg number errNum
                return "ERROR: Ghosty execute failed: " & errMsg & " (Number: " & errNum & ")"
            end try
        end tell
        """
    }

    static func readCurrentOutputScript(appName: String, activate: Bool) -> String {
        // Attempts to get content from the frontmost Ghosty window/document.
        // This is highly dependent on Ghosty's AppleScript dictionary.
        let activateBlock = activate ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then error "Ghosty is not running."
            \(activateBlock)
            delay 0.1
            try
                -- This is speculative. Ghosty might use `text of front document`, `contents of front window`, etc.
                -- Or it might not be scriptable for reading content this way at all.
                if (count of windows) > 0 then
                    return contents of front window -- Common pattern, but may not apply
                else
                    return "Ghosty has no active window to read from."
                end if
            on error errMsg number errNum
                return "ERROR: Ghosty read failed: " & errMsg & " (Number: " & errNum & ")"
            end try
        end tell
        """
    }

    static func focusGhostyScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            activate
            return "OK_FOCUSED"
        end tell
        """
    }

    static func sendControlCScript(appName: String, activate: Bool) -> String {
        // Attempts to send Ctrl+C. This might be via keystroke or a character sequence.
        let activateBlock = activate ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then error "Ghosty is not running."
            \(activateBlock)
            delay 0.1
            try
                -- Attempt 1: Keystroke (most common for less scriptable apps)
                -- tell application "System Events" to keystroke "c" using control down
                -- Attempt 2: Sending ETX character (Ctrl+C) via do script if Ghosty supports it
                do script "\\003" -- ETX character (Ctrl+C)
                return "OK_CTRL_C_SENT"
            on error errMsg number errNum
                -- Fallback if `do script ETX` fails, try keystroke if System Events is reliable enough.
                -- However, direct System Events calls from within another app's tell block can be tricky.
                -- For V1, just report the error from `do script ETX`.
                return "ERROR: Ghosty Ctrl+C failed: " & errMsg & " (Number: " & errNum & ")"
            end try
        end tell
        """
    }

    static func clearScreenScript(appName: String, activate: Bool) -> String {
        let activateBlock = activate ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then error "Ghosty is not running."
            \(activateBlock)
            delay 0.1
            try
                do script "clear"
                return "OK_CLEAR_SENT"
            on error errMsg number errNum
                return "ERROR: Ghosty clear screen failed: " & errMsg & " (Number: " & errNum & ")"
            end try
        end tell
        """
    }
    
    // Minimalistic get version script for validation
    static func getVersionScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            if not running then error "Ghosty application \"\(appName)\" is not running."
            try
                return version
            on error errMsg number errNum
                error "Failed to get Ghosty version. Error \(errNum): \(errMsg)"
            end try
        end tell
        """
    }
} 