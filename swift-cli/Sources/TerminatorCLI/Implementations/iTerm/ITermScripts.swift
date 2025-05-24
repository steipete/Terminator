import Foundation

struct ITermScripts {
    
    static func listSessionsScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            set session_list to {}
            try
                repeat with w in windows
                    set w_id to id of w
                    repeat with t in tabs of w
                        set t_id to id of t
                        repeat with s in sessions of t
                            set s_id to id of s
                            set s_tty to tty of s
                            set s_name to name of s
                            set session_info to {"win_id:" & w_id, "tab_id:" & t_id, "session_id:" & s_id, "tty:" & s_tty, "name:" & s_name}
                            set end of session_list to session_info
                        end repeat
                    end repeat
                end repeat
                return session_list
            on error errMsg number errNum
                return {{"ERROR", errMsg & " (Error " & (errNum as string) & ")"}}
            end try
        end tell
        """
    }
    
    static func findOrCreateSessionScript(
        appName: String,
        newSessionTitle: String,
        shouldActivateITerm: Bool,
        windowGroupingStrategy: String,
        projectPathForGrouping: String?,
        projectHashForGrouping: String?,
        defaultProfile: String?
    ) -> String {
        let profileName = defaultProfile ?? "Default"
        let activationScript = shouldActivateITerm ? "activate" : ""
        
        var windowCreationScript = ""
        
        if windowGroupingStrategy == "project", let projectHash = projectHashForGrouping {
            windowCreationScript = """
                set targetWindow to missing value
                set targetWindowID to missing value
                
                -- Search for existing window with project hash in title
                repeat with aWindow in windows
                    if name of aWindow contains "::TERMINATOR_SESSION::PROJECT_HASH=\(projectHash)::" then
                        set targetWindow to aWindow
                        set targetWindowID to id of aWindow
                        exit repeat
                    end if
                end repeat
                
                -- If no matching window found, create a new one
                if targetWindow is missing value then
                    set newWindow to (create window with default profile)
                    set targetWindow to newWindow
                    set targetWindowID to id of newWindow
                    -- Set window title with project hash marker
                    set name of targetWindow to "::TERMINATOR_SESSION::PROJECT_HASH=\(projectHash)::"
                end if
                
                -- Create new tab in target window
                tell targetWindow
                    set newTab to (create tab with profile "\(profileName)")
                end tell
            """
        } else if windowGroupingStrategy == "current" {
            windowCreationScript = """
                -- Use current window
                set targetWindow to current window
                set targetWindowID to id of targetWindow
                
                -- Create new tab in current window
                tell targetWindow
                    set newTab to (create tab with profile "\(profileName)")
                end tell
            """
        } else {
            // Default to "new" strategy
            windowCreationScript = """
                -- Create new window
                set newWindow to (create window with profile "\(profileName)")
                set targetWindow to newWindow
                set targetWindowID to id of newWindow
                set newTab to current tab of targetWindow
            """
        }
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                \(windowCreationScript)
                
                -- Get the new session from the new tab
                set newSession to current session of newTab
                set newSessionID to id of newSession
                set newTabID to id of newTab
                set newSessionTTY to tty of newSession
                
                -- Set the session name
                set name of newSession to "\(newSessionTitle)"
                set newSessionName to name of newSession
                
                return {newWindowID:targetWindowID, newTabID:newTabID, newSessionID:newSessionID, newSessionTTY:newSessionTTY, newSessionName:newSessionName, status:"OK"}
            on error errMsg number errNum
                return {status:"ERROR: " & errMsg & " (Error " & (errNum as string) & ")"}
            end try
        end tell
        """
    }
    
    static func executeCommandScript(
        appName: String,
        sessionID: String,
        commandToRunRaw: String,
        outputLogFilePath: String,
        completionMarker: String,
        isForeground: Bool,
        shouldActivateITerm: Bool
    ) -> String {
        // Escape the command and paths for shell usage
        let commandEscapedForShell = commandToRunRaw
            .replacingOccurrences(of: "\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "'", with: "'\\\\''")
        
        let logPathEscapedForShell = outputLogFilePath
            .replacingOccurrences(of: "\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "'", with: "'\\\\''")
        
        let markerEscapedForShell = completionMarker
            .replacingOccurrences(of: "\\", with: "\\\\\\\\")
            .replacingOccurrences(of: "'", with: "'\\\\''")
        
        // Construct the shell command
        let shellCommand: String
        if isForeground {
            shellCommand = "( (\(commandEscapedForShell)) > '\(logPathEscapedForShell)' 2>&1; echo '\(markerEscapedForShell)' >> '\(logPathEscapedForShell)' )"
        } else {
            shellCommand = "( (\(commandEscapedForShell)) > '\(logPathEscapedForShell)' 2>&1 ) & disown"
        }
        
        // Escape the entire shell command for AppleScript
        let shellCommandEscapedForAppleScript = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let activationScript = shouldActivateITerm ? """
                    activate
                    select w
                    select t
        """ : ""
        
        return """
        tell application "\(appName)"
            try
                set found_session to false
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with a_session in sessions of t
                            if id of a_session is "\(sessionID)" then
                                set found_session to true
                                \(activationScript)
                                write text "\(shellCommandEscapedForAppleScript)" to session id "\(sessionID)"
                                return {"OK", "Command submitted to session \(sessionID)", "PID_UNKNOWN"}
                            end if
                        end repeat
                    end repeat
                end repeat
                
                if not found_session then
                    return {"ERROR", "Session with ID \(sessionID) not found"}
                end if
            on error errMsg number errNum
                return {"ERROR", errMsg & " (Error " & (errNum as string) & ")"}
            end try
        end tell
        """
    }
    
    static func readSessionOutputScript(
        appName: String,
        sessionID: String,
        linesToRead: Int,
        shouldActivateITerm: Bool
    ) -> String {
        let activationScript = shouldActivateITerm ? "activate" : ""
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                -- Find session by ID
                set targetSession to missing value
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if id of aSession is equal to "\(sessionID)" then
                                set targetSession to aSession
                                exit repeat
                            end if
                        end repeat
                        if targetSession is not missing value then exit repeat
                    end repeat
                    if targetSession is not missing value then exit repeat
                end repeat
                
                if targetSession is missing value then
                    return "ERROR: Session with ID \(sessionID) not found"
                end if
                
                -- Get session contents
                tell targetSession
                    set sessionContents to contents
                end tell
                
                return sessionContents
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
            end try
        end tell
        """
    }
    
    static func focusSessionScript(
        appName: String,
        windowID: String,
        tabID: String,
        sessionID: String
    ) -> String {
        return """
        tell application "\(appName)"
            try
                activate
                
                -- Find and focus window
                set targetWindow to missing value
                repeat with aWindow in windows
                    if id of aWindow is equal to "\(windowID)" then
                        set targetWindow to aWindow
                        exit repeat
                    end if
                end repeat
                
                if targetWindow is missing value then
                    return "ERROR: Window with ID \(windowID) not found"
                end if
                
                -- Select the window
                select targetWindow
                
                -- Find and select tab
                set targetTab to missing value
                repeat with aTab in tabs of targetWindow
                    if id of aTab is equal to "\(tabID)" then
                        set targetTab to aTab
                        exit repeat
                    end if
                end repeat
                
                if targetTab is missing value then
                    return "ERROR: Tab with ID \(tabID) not found"
                end if
                
                -- Select the tab
                tell targetWindow
                    select targetTab
                end tell
                
                -- Find and select session
                set targetSession to missing value
                repeat with aSession in sessions of targetTab
                    if id of aSession is equal to "\(sessionID)" then
                        set targetSession to aSession
                        exit repeat
                    end if
                end repeat
                
                if targetSession is missing value then
                    return "ERROR: Session with ID \(sessionID) not found"
                end if
                
                -- Select the session
                tell targetTab
                    select targetSession
                end tell
                
                return "OK"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
            end try
        end tell
        """
    }
    
    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        return """
        try
            do shell script "ps -t \(ttyNameOnly) -o pgid=,stat=,pid=,command= | awk '$2 ~ /\\\\+/ {print $1 \\\" \\\" $3}' | head -n 1"
        on error errMsg number errNum
            return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
        end try
        """
    }
    
    static func clearSessionScript(
        appName: String,
        sessionID: String,
        shouldActivateITerm: Bool
    ) -> String {
        let activationScript = shouldActivateITerm ? "activate" : ""
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                -- Find session by ID
                set targetSession to missing value
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if id of aSession is equal to "\(sessionID)" then
                                set targetSession to aSession
                                exit repeat
                            end if
                        end repeat
                        if targetSession is not missing value then exit repeat
                    end repeat
                    if targetSession is not missing value then exit repeat
                end repeat
                
                if targetSession is missing value then
                    return "ERROR: Session with ID \(sessionID) not found"
                end if
                
                -- Clear the session
                tell targetSession
                    -- Clear the scrollback buffer
                    clear buffer
                    -- Also send clear command for visual feedback
                    write text "clear"
                end tell
                
                return "OK"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
            end try
        end tell
        """
    }
    
    static func sendControlCScript(
        appName: String,
        sessionID: String,
        shouldActivateITerm: Bool
    ) -> String {
        let activationScript = shouldActivateITerm ? "activate" : ""
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                -- Find session by ID
                set targetSession to missing value
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if id of aSession is equal to "\(sessionID)" then
                                set targetSession to aSession
                                exit repeat
                            end if
                        end repeat
                        if targetSession is not missing value then exit repeat
                    end repeat
                    if targetSession is not missing value then exit repeat
                end repeat
                
                if targetSession is missing value then
                    return "ERROR: Session with ID \(sessionID) not found"
                end if
                
                -- Send Control-C
                tell targetSession
                    write text "\\003"
                end tell
                
                return "OK_CTRL_C_SENT"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
            end try
        end tell
        """
    }
    
    static func setTitleScript(
        appName: String,
        sessionID: String,
        newTitle: String
    ) -> String {
        return """
        tell application "\(appName)"
            try
                -- Find session by ID
                set targetSession to missing value
                repeat with aWindow in windows
                    repeat with aTab in tabs of aWindow
                        repeat with aSession in sessions of aTab
                            if id of aSession is equal to "\(sessionID)" then
                                set targetSession to aSession
                                exit repeat
                            end if
                        end repeat
                        if targetSession is not missing value then exit repeat
                    end repeat
                    if targetSession is not missing value then exit repeat
                end repeat
                
                if targetSession is missing value then
                    return "ERROR: Session with ID \(sessionID) not found"
                end if
                
                -- Set the session name
                tell targetSession
                    set name to "\(newTitle)"
                end tell
                
                return "OK"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"
            end try
        end tell
        """
    }
    
    static func findWindowForProjectScript(appName: String, projectPath: String) -> String {
        let projectHash = SessionUtilities.generateProjectHash(projectPath: projectPath)
        return """
        tell application "\(appName)"
            try
                repeat with aWindow in windows
                    set windowName to name of aWindow
                    if windowName contains "::TERMINATOR_SESSION::PROJECT_HASH=\(projectHash)::" then
                        return id of aWindow as string
                    end if
                end repeat
                return ""
            on error errMsg number errNum
                return ""
            end try
        end tell
        """
    }
    
    static func getCurrentWindowIDScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            try
                if (count of windows) > 0 then
                    return id of current window as string
                else
                    return ""
                end if
            on error errMsg number errNum
                return ""
            end try
        end tell
        """
    }
    
    static func createNewTabInWindowScript(
        appName: String,
        windowID: String,
        customTitle: String,
        commandToRunEscaped: String?,
        shouldActivateITerm: Bool
    ) -> String {
        let activationScript = shouldActivateITerm ? "activate" : ""
        let commandScript = commandToRunEscaped != nil ? "write text \"\(commandToRunEscaped!)\" to newSession" : ""
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                -- Find window by ID
                set targetWindow to missing value
                repeat with aWindow in windows
                    if id of aWindow is equal to "\(windowID)" then
                        set targetWindow to aWindow
                        exit repeat
                    end if
                end repeat
                
                if targetWindow is missing value then
                    return {"ERROR", "Window with ID \(windowID) not found", "", ""}
                end if
                
                -- Create new tab in target window
                tell targetWindow
                    set newTab to (create tab with default profile)
                end tell
                
                -- Get tab and session info
                set newTabID to id of newTab
                set newSession to current session of newTab
                set newSessionID to id of newSession
                set newSessionTTY to tty of newSession
                
                -- Set the session name
                set name of newSession to "\(customTitle)"
                
                \(commandScript)
                
                return {newTabID as string, newSessionID as string, newSessionTTY, "OK"}
            on error errMsg number errNum
                return {"", "", "", "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"}
            end try
        end tell
        """
    }
    
    static func createNewWindowWithSessionScript(
        appName: String,
        customTitle: String,
        commandToRunEscaped: String?,
        shouldActivateITerm: Bool
    ) -> String {
        let activationScript = shouldActivateITerm ? "activate" : ""
        let commandScript = commandToRunEscaped != nil ? "write text \"\(commandToRunEscaped!)\" to newSession" : ""
        
        return """
        tell application "\(appName)"
            try
                \(activationScript)
                
                -- Create new window
                set newWindow to (create window with default profile)
                set newWindowID to id of newWindow
                
                -- Get the current tab and session
                set newTab to current tab of newWindow
                set newTabID to id of newTab
                set newSession to current session of newTab
                set newSessionID to id of newSession
                set newSessionTTY to tty of newSession
                
                -- Set the session name
                set name of newSession to "\(customTitle)"
                
                \(commandScript)
                
                return {newWindowID as string, newTabID as string, newSessionID as string, newSessionTTY, "OK"}
            on error errMsg number errNum
                return {"", "", "", "", "ERROR: " & errMsg & " (Error " & (errNum as string) & ")"}
            end try
        end tell
        """
    }
}