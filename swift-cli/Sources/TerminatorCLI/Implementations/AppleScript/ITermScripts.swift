import Foundation

struct ITermScripts {

    static func listSessionsScript(appName: String) -> String {
        // Note: iTerm session name is used as 'title'
        // iTerm tab ID is distinct from iTerm session ID. We use tab ID for 'tabIdentifier'.
        return """
        tell application "\\(appName)"
            if not running then error "iTerm2 is not running."
            set sessionList to {}
            try
                repeat with w in windows
                    set w_id to id of w as string
                    repeat with t in tabs of w
                        set t_id to id of t as string
                        repeat with s in sessions of t
                            set s_id to id of s as string -- iTerm's physical session ID
                            set s_tty to tty of s
                            set s_name to name of s -- This is the session title/name in iTerm
                            
                            set end of sessionList to { \\
                                "win_id:" & w_id, \\
                                "tab_id:" & t_id, \\
                                "session_id:" & s_id, \\
                                "tty:" & s_tty, \\
                                "name:" & s_name \\
                            }
                        end repeat
                    end repeat
                end repeat
            on error errMsg number errNum
                error "AppleScript Error: " & errMsg & " (Number: " & errNum & ")"
            end try
            return sessionList
        end tell
        """
    }

    static func executeCommandScript(
        appName: String,
        windowID: String, // Target existing window ID
        tabID: String,    // Target existing tab ID
        // TTY is not directly used to select the session here, but for context if needed by caller.
        // The script finds the session based on windowID and tabID, then uses its current session.
        commandToRunRaw: String,
        outputLogFilePath: String, // Full path to the output log file
        completionMarker: String,  // Marker for foreground completion
        isForeground: Bool,
        shouldActivateITerm: Bool
        // timeoutSeconds is now primarily handled by the Swift caller watching the log, not a long AppleScript timeout.
    ) -> String {
        let activateBlock = shouldActivateITerm ? "activate" : ""
        let quotedLogFilePath = "'\(outputLogFilePath.replacingOccurrences(of: "'", with: "'\\''"))'"
        
        var shellCommandToExecute: String
        if commandToRunRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            shellCommandToExecute = "# Empty command, ensuring session activation and readiness"
        } else if isForeground {
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\''")
            // Redirect output, then echo marker. Parentheses ensure sequence.
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePath) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePath))"
        } else { // Background
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\''")
            // Redirect output, then background and disown.
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePath) 2>&1) & disown"
        }
        
        // Escape for AppleScript string literal
        let appleScriptSafeShellCommand = shellCommandToExecute
            .replacingOccurrences(of: "\\", with: "\\\\") // Escape backslashes
            .replacingOccurrences(of: "\"", with: "\\\"")   // Escape double quotes

        // This script now primarily focuses on delivering the command to the correct session.
        // Output and completion are handled by the caller via the log file.
        // It returns a simple list: {status_string, message_string, optional_pid_string_if_captured}
        // For this version, PID capture is omitted for simplicity, can be added later if essential.
        return """
        tell application "\(appName)"
            if not running then return {"ERROR", "iTerm2 application \"\(appName)\" is not running.", ""}
            \(activateBlock)
            
            set targetWindow to missing value
            set targetTab to missing value
            set targetSession to missing value
            
            try
                repeat with w in windows
                    if id of w as string is "\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is missing value then return {"ERROR", "Window ID \(windowID) not found.", ""}
                
                tell targetWindow
                    repeat with t in tabs
                        if id of t as string is "\(tabID)" then
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is missing value then return {"ERROR", "Tab ID \(tabID) in window \(windowID) not found.", ""}
                    
                    select targetTab -- Ensure the tab is active to get its current session
                    set targetSession to current session of targetTab
                    if targetSession is missing value then return {"ERROR", "Could not get current session of tab \(tabID).", ""}
                end tell

                tell targetSession
                    write text "\(appleScriptSafeShellCommand)"
                end tell
                return {"OK", "Command submitted to iTerm session.", ""} -- PID not captured by this script version

            on error errMsg number errNum
                return {"ERROR", "iTerm execute error: " & errMsg & " (Number: " & errNum & ")", ""}
            end try
        end tell
        """
    }

    static func readSessionOutputScript(
        appName: String,
        windowID: String,
        tabID: String,
        shouldActivateITerm: Bool
    ) -> String {
        let activateBlock = shouldActivateITerm ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then error "iTerm2 is not running."
            \(activateBlock)
            
            set targetWindow to missing value
            set targetTab to missing value
            set targetSession to missing value
            
            try
                repeat with w in windows
                    if id of w as string is "\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is missing value then error "Window ID \(windowID) not found for reading."
                
                tell targetWindow
                    repeat with t in tabs
                        if id of t as string is "\(tabID)" then
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is missing value then error "Tab ID \(tabID) in window \(windowID) not found for reading."
                    
                    -- Select tab to ensure its session is current
                    select targetTab
                    set targetSession to current session of targetTab
                end tell
                if targetSession is missing value then error "Could not get current session of tab \(tabID) for reading."
                
                return (contents of targetSession)
            on error e
                error "Error reading iTerm session: " & e
            end try
        end tell
        """
    }

    static func focusSessionScript(
        appName: String,
        windowID: String,
        tabID: String
    ) -> String {
        return """
        tell application "\\(appName)"
            if not running then error "iTerm2 is not running."
            activate -- Always activate when explicitly focusing
            
            set targetWindow to missing value
            set targetTab to missing value
            
            try
                repeat with w in windows
                    if id of w as string is "\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is missing value then error "Window ID \(windowID) not found for focus."
                
                tell targetWindow
                    select -- Bring window to front
                    repeat with t in tabs
                        if id of t as string is "\(tabID)" then
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is missing value then error "Tab ID \(tabID) in window \(windowID) not found for focus."
                    
                    select targetTab -- Select the tab
                end tell
                return "Session focused: Window \(windowID), Tab \(tabID)"
            on error e
                error "Error focusing iTerm session: " & e
            end try
        end tell
        """
    }

    // findPgidScriptForKill remains a shell command, not pure AppleScript
    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        // Same as AppleTerminal, as it's a generic shell command
        // Important: This script is executed via "do shell script", so needs careful escaping if complex.
        // Returns PGID and PID of the foreground process in that TTY
        // Example: `ps -t <tty_name> -o pgid=,pid=,stat=,command= | awk '$3 ~ /^[RSTCDP]/ && $3 !~ /S\\+/ && $4 !~ /^(bash|zsh|sh|login|fish|tcsh|csh)/ {print $1 " " $2; exit}'`
        // Simpler version focusing on PGID, assuming first non-shell is the target group leader
        return "pgrep -t \(ttyNameOnly) -s 0" // Gets session leader (often the shell itself)
                                           // More robust:
                                           // "ps -t \(ttyNameOnly) -o pgid=,state=,command= | awk '$2 != \"Z\" && $2 != \"T\" && $3 !~ /^(bash|zsh|sh|fish|tcsh|csh|login)/ {gsub(/^[[:space:]]+|[[:space:]]+$/, \\"\\", $1); print $1; exit}'"
                                           // The following tries to get the PGID of the foremost process not being a common shell
        return "ps -t \(ttyNameOnly) -o pgid=,state=,command= | grep -vE ' (bash|zsh|sh|fish|tcsh|csh|login|nvim|vim|emacs|nano|pico|less|more|htop|top|btop)(\\s|$)|^-' | awk '$2 ~ /^[RSD]/ {gsub(/^[ ]*|[ ]*$/, \\"\\", $1); print $1; exit}'"

    }
    
    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        let shellCommand = findPgidScriptForKill(ttyNameOnly: ttyNameOnly)
        // Ensure the shell command itself is properly escaped for inclusion in an AppleScript string
        let escapedShellCommand = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedShellCommand)\""
    }

    static func findOrCreateSessionScript(
        appName: String,
        newSessionTitle: String,
        shouldActivateITerm: Bool,
        windowGroupingStrategy: String, // "project", "current", "new"
        projectPathForGrouping: String?, // Full project path for "project" strategy
        projectHashForGrouping: String?  // Hash for "project" strategy title search
    ) -> String {
        let activateBlock = shouldActivateITerm ? "activate" : "if not running then run else if frontmost is false then activate"
        var script = """
        tell application "\\(appName)"
            \(activateBlock)
            delay 0.2 -- Give app time to respond

            set targetWindow to missing value
            set newSessionTTY to ""
            set newITermSessionID to "" -- iTerm's physical session ID
            set newWindowID to ""
            set newTabID to ""

            if (count of windows) is 0 then
                log "iTerm: No windows open, creating a new one."
                set targetWindow to (create window with default profile)
                delay 0.5
            else
                if "\\(windowGroupingStrategy)" is "project" and "\\(projectPathForGrouping ?? "")" is not "" and "\\(projectHashForGrouping ?? "")" is not "" then
                    set foundProjectWindow to false
                    repeat with w_idx from 1 to count of windows
                        set w to item w_idx of windows
                        try
                            repeat with t_idx from 1 to count of tabs of w
                                set t to item t_idx of tabs of w
                                repeat with s_idx from 1 to count of sessions of t
                                    set s to item s_idx of sessions of t
                                    if name of s starts with "::TERMINATOR_SESSION::PROJECT_HASH=\\(projectHashForGrouping!)::" then
                                        set targetWindow to w
                                        set foundProjectWindow to true
                                        log "iTerm: Found existing window for project hash \\(projectHashForGrouping!)."
                                        exit repeat
                                    end if
                                end repeat
                                if foundProjectWindow then exit repeat
                            end repeat
                            if foundProjectWindow then exit repeat
                        on error errmsg number errnum
                            log "iTerm: Error inspecting sessions of window " & (id of w as string) & ": " & errmsg
                        end try
                    end repeat
                    if not foundProjectWindow then
                        log "iTerm: No existing window found for project hash \\(projectHashForGrouping!). Creating new window."
                        set targetWindow to (create window with default profile)
                        delay 0.5
                    end if
                else if "\\(windowGroupingStrategy)" is "current" then
                    log "iTerm: Window grouping is 'current'."
                    set targetWindow to current window
                    if targetWindow is missing value and (count of windows) > 0 then
                        set targetWindow to front window -- Fallback if current window not set (e.g. not frontmost)
                    else if targetWindow is missing value then
                        log "iTerm: No current/front window, creating new."
                        set targetWindow to (create window with default profile)
                        delay 0.5
                    end if
                else -- "new" or default
                    log "iTerm: Window grouping is 'new'. Creating new window."
                    set targetWindow to (create window with default profile)
                    delay 0.5
                end if
            end if

            if targetWindow is missing value then
                error "iTerm: Target window could not be determined or created."
            end if
            
            if shouldActivateITerm or (frontmost is false) then
                tell targetWindow to select -- Bring to front
                activate
            end if
            delay 0.2

            tell targetWindow
                set newTab to create tab with default profile
                tell newTab
                    -- In iTerm, 'create tab' often returns the tab, and its current session is the new one.
                    -- Sometimes it might return the session directly depending on iTerm version/context.
                    -- We get the current session of the new tab.
                    tell current session
                        set newSessionTTY to tty
                        set newITermSessionID to id as string
                        set name to "\(newSessionTitle)"
                    end tell
                    set newTabID to id as string
                end tell
            end tell
            set newWindowID to id of targetWindow as string

            return {newWindowID, newTabID, newITermSessionID, newSessionTTY, "\(newSessionTitle)"}
        end tell
        """
        return script
    }

    static func createNewSessionScript(appName: String, projectPath: String?, tag: String, commandToRunEscaped: String?, customTitle: String, shouldActivateITerm: Bool) -> String {
        let newWindowOrTabAppleScript:
        // Simplified: Always new tab in current window, or new window if no windows.
        // More complex grouping (project-based new window) would go here.
        // For now, it tries to use existing window or creates a new one.
        newWindowOrTabAppleScript = """
            if (count of windows) is 0 then
                set termWindow to (create window with default profile)
            else
                set termWindow to current window
            end if
            tell termWindow
                set newTab to create tab with default profile
            end tell
        """

        let commandPart = commandToRunEscaped != nil ? "write text \"\(commandToRunEscaped!)\"" : "" // If no command, just set title and focus
        let activatePart = shouldActivateITerm ? "activate" : "" // Only activate if needed

        return """
        tell application "\(appName)"
            \(activatePart)
            \(newWindowOrTabAppleScript)
            
            -- The newTab should be the current session in the new tab
            -- We need to get its ID, TTY, and set its name.
            tell current session of newTab of termWindow
                set variable named "name" to "\(customTitle)"
                delay 0.5 -- Give iTerm a moment to settle and register the new session/tty
                set s_id to id
                set s_tty to tty
                \(commandPart)
            end tell
            
            -- Get window and tab IDs for returning
            set w_id to id of termWindow
            set t_id to id of newTab
            
            return w_id & "\t" & t_id & "\t" & s_id & "\t" & s_tty & "\t" & "\(customTitle)"
        end tell
        """
    }

    static func getTerminalSessionPgidScript(ttyNameOnly: String) -> String {
        // This script directly executes a shell command via AppleScript to get the PGID.
        // It's simpler than trying to send text to iTerm and read its output for this specific task.
        let shellCommand = "ps -t '\(ttyNameOnly)' -o pgid=,stat=,command= | grep -Ev 'tmux|screen|sshd|login|zsh|bash|fish|csh|tcsh|ksh' | grep -m1 'S[+]?$' | awk '{print $1}' || ps -t '\(ttyNameOnly)' -o pgid=,stat=,command= | grep -Ev 'tmux|screen|sshd|login|zsh|bash|fish|csh|tcsh|ksh' | grep -m1 '.*' | awk '{print $1}'"
        let escapedShellCommand = shellCommand.replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedShellCommand)\""
    }

    static func clearSessionScript(appName: String, windowID: String, tabID: String) -> String {
        // SDD 3.2.5: Screen Clearing for iTerm2: `current_session clear_buffer`
        return """
        tell application "\\(appName)"
            if not running then error "iTerm2 is not running."
            
            set targetWindow to missing value
            set targetTab to missing value
            set targetSession to missing value
            
            try
                repeat with w in windows
                    if id of w as string is "\\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is missing value then error "Window ID \\(windowID) not found for clearing."
                
                tell targetWindow
                    repeat with t in tabs
                        if id of t as string is "\\(tabID)" then
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is missing value then error "Tab ID \\(tabID) in window \\(windowID) not found for clearing."
                    
                    select targetTab -- Ensure the tab is selected to get the current session
                    set targetSession to current session of targetTab
                end tell
                if targetSession is missing value then error "Could not get current session of tab \\(tabID) for clearing."

                tell targetSession
                    clear buffer
                end tell
                return "OK"
            on error e
                return "ERROR: " & e
            end try
        end tell
        """
    }

    static func sendControlCScript(appName: String, windowID: String, tabID: String, shouldActivateITerm: Bool) -> String {
        let activateBlock = shouldActivateITerm ? "activate" : ""
        // For iTerm, \\003 is Ctrl+C. Some sources say `key code 8 using control down` but `write text` is often more direct for control chars.
        return """
        tell application "\\(appName)"
            if not running then error "iTerm2 is not running."
            \\(activateBlock)
            
            set targetWindow to missing value
            set targetTab to missing value
            set targetSession to missing value
            
            try
                repeat with w in windows
                    if id of w as string is "\\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
                if targetWindow is missing value then error "Window ID \\(windowID) not found for sending Ctrl+C."
                
                tell targetWindow
                    if \\(shouldActivateITerm) then select -- Bring window to front
                    repeat with t in tabs
                        if id of t as string is "\\(tabID)" then
                            set targetTab to t
                            exit repeat
                        end if
                    end repeat
                    if targetTab is missing value then error "Tab ID \\(tabID) in window \\(windowID) not found for sending Ctrl+C."
                    
                    if \\(shouldActivateITerm) then select targetTab -- Select the tab
                    set targetSession to current session of targetTab
                end tell
                if targetSession is missing value then error "Could not get current session of tab \\(tabID) for sending Ctrl+C."

                tell targetSession
                    write text "\\\\003" -- Send ETX character (Ctrl+C)
                end tell
                return "OK_CTRL_C_SENT"
            on error e
                return "ERROR_CTRL_C: " & (e as string)
            end try
        end tell
        """
    }

    // Script to create a new iTerm window and return its ID, new tab's ID, and the new session's TTY & ID.
    static func createNewWindowWithSessionScript(appName: String, customTitle: String?) -> String {
        let setTitleCommands:
        if let title = customTitle, !title.isEmpty {
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            setTitleCommands = """
            delay 0.2 -- Allow session to fully initialize
            set name to "\(escapedTitle)"
            """
        } else {
            setTitleCommands = ""
        }

        return """
        tell application "\(appName)"
            if not running then 
                activate -- Start and activate if not running
                delay 1 -- Give it a moment to start up
            end if
            
            try
                set newWindow to (create window with default profile)
                delay 0.5 -- Wait for window and session to be ready
                tell newWindow
                    set newTab to current tab
                    set newSession to current session of newTab
                    tell newSession
                        \(setTitleCommands)
                    end tell
                    set win_id to id of newWindow as string
                    set tab_id to id of newTab as string
                    set session_id to id of newSession as string
                    set session_tty to tty of newSession
                    return {win_id, tab_id, session_id, session_tty, "OK"}
                end tell
            on error errMsg number errNum
                return {"", "", "", "", "ERROR: iTerm new window failed: " & errMsg & " (Number: " & errNum & ")"}
            end try
        end tell
        """
    }

    // Script to create a new tab in an existing iTerm window and return new tab's ID, and the new session's TTY & ID.
    static func createNewTabInWindowScript(appName: String, windowID: String, customTitle: String?) -> String {
        let setTitleCommands:
        if let title = customTitle, !title.isEmpty {
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            setTitleCommands = """
            delay 0.2 -- Allow session to fully initialize
            set name to "\(escapedTitle)"
            """
        } else {
            setTitleCommands = ""
        }

        return """
        tell application "\(appName)"
            if not running then return {"", "", "", "ERROR: iTerm2 application \"\(appName)\" is not running."}
            
            set targetWindow to missing value
            try
                repeat with w in windows
                    if id of w as string is "\(windowID)" then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
            on error errMsg number errNum
                 return {"", "", "", "ERROR: Finding window \(windowID) failed: " & errMsg & " (Number: " & errNum & ")"}
            end try
            
            if targetWindow is missing value then
                return {"", "", "", "ERROR: Window with ID \(windowID) not found."}
            end if
            
            try
                tell targetWindow
                    activate -- Bring window to front before creating tab
                    set newTab to (create tab with default profile)
                    delay 0.5 -- Wait for tab and session to be ready
                    tell newTab
                        set newSession to current session
                        tell newSession
                           \(setTitleCommands)
                        end tell
                        set tab_id to id of newTab as string
                        set session_id to id of newSession as string
                        set session_tty to tty of newSession
                        return {tab_id, session_id, session_tty, "OK"}
                    end tell
                end tell
            on error errMsg number errNum
                return {"", "", "", "ERROR: iTerm new tab failed: " & errMsg & " (Number: " & errNum & ")"}
            end try
        end tell
        """
    }
    
    // Script to set the title (name) of an iTerm session
    static func setSessionTitleScript(appName: String, windowID: String, tabID: String, sessionID: String, newTitle: String) -> String {
        let escapedTitle = newTitle.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(appName)"
            if not running then return "ERROR: iTerm2 application \"\(appName)\" is not running."
            try
                set targetWindow to first window whose id is (windowID as integer)
                set targetTab to first tab of targetWindow whose id is (tabID as integer)
                set targetSession to first session of targetTab whose id is (sessionID as integer)
                tell targetSession
                    set name to "\(escapedTitle)"
                end tell
                return "OK"
            on error errMsg number errNum
                return "ERROR: Failed to set iTerm session title for session \(sessionID): " & errMsg & " (Number: " & errNum & ")"
            end try
        end tell
        """
    }
} 