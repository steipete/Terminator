import Foundation

enum ITermSessionControlScripts {
    static func focusSessionScript(
        appName: String,
        windowID: String,
        tabID: String,
        sessionID: String
    ) -> String {
        """
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

    static func setTitleScript(
        appName: String,
        sessionID: String,
        newTitle: String
    ) -> String {
        """
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

    static func setSessionNameScript(appName: String, sessionID: String, newName: String) -> String {
        let escapedName = newName.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(appName)"
            try
                set found_session to false
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if id of s is "\(sessionID)" then
                                set name of s to "\(escapedName)"
                                set found_session to true
                                exit repeat
                            end if
                        end repeat
                        if found_session then exit repeat
                    end repeat
                    if found_session then exit repeat
                end repeat
                if found_session then
                    return "OK"
                else
                    return "ERROR: Session with ID \(sessionID) not found for setting name."
                end if
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"
            end try
        end tell
        """
    }

    static func setWindowNameScript(appName: String, windowID: String, newName: String) -> String {
        let escapedName = newName.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(appName)"
            try
                set target_window to missing value
                repeat with w_ref in windows
                    if (id of w_ref as string) is "\(windowID)" then
                        set target_window to w_ref
                        exit repeat
                    end if
                end repeat
                if target_window is missing value then
                    return "ERROR: Window with ID \(windowID) not found for setting name."
                end if
                set name of target_window to "\(escapedName)"
                return "OK"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"
            end try
        end tell
        """
    }

    static func activateITermAppScript(appName: String) -> String {
        "tell application \"\(appName)\" to activate"
    }

    static func selectSessionInITermScript(
        appName: String,
        windowID: String,
        tabID: String,
        sessionID _: String
    ) -> String {
        // This script ensures the window is front, tab is selected, and implies session is active.
        // iTerm selects the session when its tab is selected.
        """
        tell application "\(appName)"
            try
                activate
                set target_window to missing value
                repeat with w_ref in windows
                    if (id of w_ref as string) is "\(windowID)" then
                        set target_window to w_ref
                        exit repeat
                    end if
                end repeat
                if target_window is missing value then error "Window \(windowID) not found."

                select target_window -- Brings window to front

                set target_tab to missing value
                tell target_window
                    repeat with t_ref in tabs
                        if (id of t_ref as string) is "\(tabID)" then
                            set target_tab to t_ref
                            exit repeat
                        end if
                    end repeat
                end tell
                if target_tab is missing value then error "Tab \(tabID) not found in window \(windowID)."

                tell target_window to select target_tab -- Selects the tab
                return "OK"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"
            end try
        end tell
        """
    }
}
