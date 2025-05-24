import Foundation

enum ITermSessionIntrospectionScripts {
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

    static func readSessionOutputScript(
        appName: String,
        sessionID: String,
        linesToRead _: Int,
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

    static func listWindowsForGroupingScript(appName: String) -> String {
        return """
        tell application "\(appName)"
            set window_details_list to {}
            try
                repeat with w in windows
                    set w_id to id of w as string
                    set w_name to name of w
                    set end of window_details_list to {w_id, w_name}
                end repeat
            on error errMsg number errNum
                -- Return an empty list or a specific error indicator if preferred
                return {}
            end try
            return window_details_list
        end tell
        """
    }
}