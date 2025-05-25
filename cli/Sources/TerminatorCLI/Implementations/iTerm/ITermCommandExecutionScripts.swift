import Foundation

enum ITermCommandExecutionScripts {
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

    static func simpleExecuteShellCommandInSessionScript(
        appName: String,
        sessionID: String,
        shellCommandToExecuteEscapedForAppleScript: String,
        shouldActivateITerm: Bool
    ) -> String {
        let activationLogic = shouldActivateITerm ? """
                                activate
                                -- Attempt to select the session's window and tab for better activation
                                repeat with w_ref in windows
                                    repeat with t_ref in tabs of w_ref
                                        repeat with s_ref in sessions of t_ref
                                            if id of s_ref is "\(sessionID)" then
                                                select w_ref
                                                tell w_ref to select t_ref
                                                exit repeat
                                            end if
                                        end repeat
                                        if exists (session id "\(sessionID)" of t_ref) then exit repeat
                                    end repeat
                                    if exists (session id "\(sessionID
                                    )" of current tab of w_ref) then exit repeat -- A bit broad, but helps
                                end repeat
        """ : ""

        return """
        tell application "\(appName)"
            try
                set found_session to false
                set target_session_ref to missing value

                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s_ref in sessions of t
                            if id of s_ref is "\(sessionID)" then
                                set target_session_ref to s_ref
                                set found_session to true
                                exit repeat
                            end if
                        end repeat
                        if found_session then exit repeat
                    end repeat
                    if found_session then exit repeat
                end repeat

                if not found_session or target_session_ref is missing value then
                    return "ERROR: Session with ID \(sessionID) not found for command execution."
                end if

                \(activationLogic)

                -- Execute the command in the found session reference
                tell target_session_ref
                    write text "\(shellCommandToExecuteEscapedForAppleScript)"
                end tell

                return "OK_COMMAND_SUBMITTED"
            on error errMsg number errNum
                return "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"
            end try
        end tell
        """
    }

    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        let shellCommand = findPgidScriptForKill(ttyNameOnly: ttyNameOnly)
        let escapedShellCommand = shellCommand.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedShellCommand)\""
    }

    // Helper function from AppleTerminalScripts for use by iTerm's getPGIDAppleScript
    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        // Escaping for "do shell script" needs to be handled by the caller if this string is embedded.
        // This returns a raw shell command string.
        "ps -t \(ttyNameOnly) -o pgid=,stat=,pid=,command= | awk '$2 ~ /\\+/ {print $1 \" \" $3}' | head -n 1"
    }
}
