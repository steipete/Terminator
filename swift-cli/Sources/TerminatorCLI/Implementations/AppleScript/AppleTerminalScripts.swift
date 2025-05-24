import Foundation

// This struct centralizes the generation of AppleScript strings used by AppleTerminalControl.
// By offloading script generation here, AppleTerminalControl.swift becomes cleaner and
// focuses more on the logic of interacting with Terminal.app rather than script text.
enum AppleTerminalScripts {
    static func listSessionsScript(appName: String) -> String {
        // Note: Original script from AppleTerminalControl.listSessions
        // Properties like `history` are intensive; only get what's needed for listing.
        // `λον` was likely a typo for `"` or a copy-paste artifact in the original prompt, assuming standard AppleScript.
        // For `listSessions`, we mainly need identifiers and TTY to parse titles and check status.
        return """
        set output_list to {}
        tell application "\(appName)"
            if not running then error "Terminal application \(appName) is not running."
            try
                set window_indices to index of windows
                repeat with i from 1 to count of window_indices
                    set w_index to item i of window_indices
                    set w to window id (id of window w_index)

                    set tab_indices to index of tabs of w
                    repeat with j from 1 to count of tab_indices
                        set t_index to item j of tab_indices
                        set t to tab id (id of tab t_index of w)

                        set ttyPath to tty of t
                        set customTitle to custom title of t
                        if customTitle is missing value then set customTitle to ""
                        -- History not needed for list, only for read.

                        set end of output_list to {"win_id:" & (id of w as string), "tab_id:" & (id of t as string), "tty:" & ttyPath, "title:" & customTitle}
                    end repeat
                end repeat
            on error errMsg number errNum
                error "AppleScript Error (Code " & (errNum as string) & "): " & errMsg
            end try
        end tell
        return output_list
        """
    }

    static func findOrCreateSessionScript(
        appName: String,
        newSessionTitle: String,
        shouldActivateTerminal: Bool,
        windowGroupingStrategy: String, // "project", "current", "new"
        projectPathForGrouping: String?, // Used if windowGrouping is "project"
        projectHashForGrouping: String? // Used if windowGrouping is "project"
    ) -> String {
        // Note: Original script from AppleTerminalControl.findOrCreateSessionForAppleTerminal (creation part)
        let escapedNewSessionTitle = newSessionTitle.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'") // AS escape

        var script = """
        tell application "\(appName)"
            if not running then
                if \(shouldActivateTerminal) then
                    activate
                else
                    run 
                end if
                delay 0.5 
            else if \(shouldActivateTerminal) then
                 activate
            end if

            set targetWindow to missing value
            set newTab to missing value
            set newTabTTY to ""
            set newTabID to ""
            set newWindowID to ""

            if (count of windows) is 0 then
                log "AppleTerminal: No windows open, creating a new one."
                make new window
                delay 0.2 
            end if
        """

        if windowGroupingStrategy == "project", let projPath = projectPathForGrouping, let projHash = projectHashForGrouping, !projPath.isEmpty {
            script += """
            set projectHashForTitleSearch to "\(projHash)"
            set foundProjectWindow to false
            repeat with w in windows
                try
                    repeat with t in tabs of w
                        set tabTitle to custom title of t
                        if tabTitle starts with "::TERMINATOR_SESSION::PROJECT_HASH=" & projectHashForTitleSearch & "::" then
                            set targetWindow to w
                            set foundProjectWindow to true
                            exit repeat
                        end if
                    end repeat
                    if foundProjectWindow then exit repeat
                on error
                    log "AppleTerminal: Error inspecting tabs of a window."
                end try
            end repeat
            if not foundProjectWindow then
                log "AppleTerminal: No existing window for project '\(projPath)'. Creating new window."
                set targetWindow to make new window
            else
                log "AppleTerminal: Found existing window for project '\(projPath)'."
            end if
            """
        } else if windowGroupingStrategy == "current" {
            script += """
            if frontmost then
                 set targetWindow to front window
            else
                 set targetWindow to window 1
            end if
            """
        } else { // "new" or default
            script += """
            log "AppleTerminal: Window grouping is 'new'. Creating new window."
            set targetWindow to make new window
            """
        }

        script += """
            if targetWindow is missing value then
                 log "AppleTerminal: Target window fallback."
                 if (count of windows) > 0 then
                    set targetWindow to front window
                 else
                    set targetWindow to make new window 
                    delay 0.2
                 end if
            end if

            tell targetWindow
                if \(shouldActivateTerminal) then activate
                set newTab to do script ""
                delay 0.2 
                set newTabTTY to tty of newTab
                set newTabID to id of newTab as string
                set custom title of newTab to "\(escapedNewSessionTitle)" 

                if \(shouldActivateTerminal) then
                    set selected tab to newTab
                end if
            end tell
            set newWindowID to id of targetWindow as string

            return {newWindowID, newTabID, newTabTTY, "\(escapedNewSessionTitle)"}
        end tell
        """
        return script
    }

    static func focusExistingSessionScript(appName: String, windowID: String, tabID: String) -> String {
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            activate
            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)
            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for focusing existing session."
            end if
            tell targetWindow
                set index to 1
                set selected tab to targetTab
            end tell
            return true
        end tell
        """
    }

    static func executeCommandScript(
        appName: String,
        windowID: String,
        tabID: String,
        tty _: String, // Kept for context, not directly used by script
        commandToRunRaw: String, // The raw command
        outputLogFilePath: String, // Absolute path to the log file
        completionMarker: String, // Marker to echo for foreground completion
        timeoutSeconds: Int, // Timeout for AppleScript to wait for marker (in tab history)
        isForeground: Bool,
        shouldActivateTerminal: Bool
    ) -> String {
        // Quote log file path for shell
        let quotedLogFilePathForShell = "'" + outputLogFilePath.replacingOccurrences(of: "'", with: "'\\\\''") + "'"
        // Escape log file path for usage inside an AppleScript string literal that will be part of a JSON string
        let escapedLogPathForAppleScriptJSON = outputLogFilePath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        // Escape completion marker for AppleScript string comparison
        let escapedCompletionMarkerForAppleScript = completionMarker.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")

        var shellCommandToExecute: String
        if isForeground {
            // For foreground: ( (actual_command) > logfile 2>&1; echo MARKER >> logfile )
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\\\''")
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePathForShell) 2>&1; echo '\(completionMarker)' >> \(quotedLogFilePathForShell))"
        } else {
            // For background: ( (actual_command) > logfile 2>&1 ) & disown
            let shellEscapedCommand = commandToRunRaw.replacingOccurrences(of: "'", with: "'\\\\''")
            shellCommandToExecute = "((\(shellEscapedCommand)) > \(quotedLogFilePathForShell) 2>&1) & disown"
        }

        let appleScriptSafeShellCommand = shellCommandToExecute
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptCore = """
        set targetWindow to first window whose id is \(windowID)
        set targetTab to first tab of targetWindow whose id is \(tabID)

        if targetWindow is missing value or targetTab is missing value then
            return "{\\\"status\\\": \\\"ERROR\\\", \\\"message\\\": \\\"Session find error: Could not find window ID \(windowID) or tab ID \(tabID). Executing in default context not supported for file redirection.\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
        end if

        if \(shouldActivateTerminal) then
            activate
            tell targetWindow to set selected tab to targetTab
        end if

        do script "\(appleScriptSafeShellCommand)" in targetTab
        """

        var finalScript = """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            try
                \(scriptCore)
        """

        if isForeground {
            finalScript += """
                    set foundMarker to false
                    set startTime to current date
                    repeat while ((current date) - startTime) < \(timeoutSeconds) seconds and not foundMarker
                        delay 0.2 -- Polling interval
                        try
                            set tabHistory to history of targetTab
                            if tabHistory contains "\(escapedCompletionMarkerForAppleScript)" then
                                set foundMarker to true
                            end if
                        on error errMsg number errNum
                            log "AppleTerminal: Error reading history during marker poll: " & errMsg & " (Number: " & (errNum as string) & ")"
                            delay 0.5
                        end try
                    end repeat

                    if not foundMarker then
                        return "{\\\"status\\\": \\\"TIMEOUT\\\", \\\"message\\\": \\\"Timeout waiting for foreground completion marker in tab history. Log file (\\\"\(escapedLogPathForAppleScriptJSON)\\\") may contain output.\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
                    end if

                    return "{\\\"status\\\": \\\"OK_SUBMITTED_FG\\\", \\\"message\\\": \\\"Foreground command submitted, completion marker found in history.\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
                on error e
                     return "{\\\"status\\\": \\\"ERROR\\\", \\\"message\\\": \\\"Error during foreground execution: \" & (e as string) & \"\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
                end try
            end tell
            """
        } else { // Background
            finalScript += """
                    return "{\\\"status\\\": \\\"OK_SUBMITTED_BG\\\", \\\"message\\\": \\\"Background command submitted.\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
                on error e
                     return "{\\\"status\\\": \\\"ERROR\\\", \\\"message\\\": \\\"Error during background submission: \" & (e as string) & \"\\\", \\\"log_file\\\": \\\"\(escapedLogPathForAppleScriptJSON)\\\"}"
                end try
            end tell
            """
        }
        return finalScript
    }

    static func readSessionOutputScript(appName: String, windowID: String, tabID: String, shouldActivateTerminal: Bool) -> String {
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)

            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for reading."
            end if

            if \(shouldActivateTerminal) then
                activate
                tell targetWindow to set selected tab to targetTab
            end if

            return history of targetTab
        end tell
        """
    }

    static func focusSessionScript(appName: String, windowID: String, tabID: String) -> String {
        // This is the same as focusExistingSessionScript, can be consolidated if desired
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            activate 

            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)

            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for focusing."
            end if

            tell targetWindow
                set index to 1 
                set selected tab to targetTab
            end tell
            return true 
        end tell
        """
    }

    // Note: killProcessInSession primarily uses `do shell script` for `ps` and `ProcessUtilities` for kill signals.
    // If it needed to, for example, clear the screen in the tab *after* a kill, that would be an AppleScript snippet here.
    // For now, the main script part of kill is the `ps` command to find PGID.
    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        // Escaping for "do shell script" needs to be handled by the caller if this string is embedded.
        // This returns a raw shell command string.
        return "ps -t \(ttyNameOnly) -o pgid=,stat=,pid=,command= | awk '$2 ~ /\\+/ {print $1 \" \" $3}' | head -n 1"
    }

    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        let shellCommand = findPgidScriptForKill(ttyNameOnly: ttyNameOnly)
        // Ensure the shell command itself is properly escaped for inclusion in an AppleScript string
        let escapedShellCommand = shellCommand.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escapedShellCommand)\""
    }

    static func clearSessionScript(appName: String, windowID: String, tabID: String, shouldActivateTerminal: Bool) -> String {
        return """
        tell application "\(appName)"
            if not running then return "ERROR_CLEAR: Terminal is not running."

            try
                set targetWindow to first window whose id is \(windowID)
                set targetTab to first tab of targetWindow whose id is \(tabID)

                if targetWindow is missing value or targetTab is missing value then
                    return "ERROR_CLEAR: Could not find window ID \(windowID) or tab ID \(tabID) for clearing."
                end if

                if \(shouldActivateTerminal) then
                    activate
                    tell targetWindow to set selected tab to targetTab
                end if

                -- Step 1: do script "clear && clear"
                do script "clear && clear" in targetTab
                delay 0.2 -- Give time for clear to execute

                -- Step 2: Best-effort Cmd+K
                if \(shouldActivateTerminal) then
                    try
                        tell application "System Events" to keystroke "k" using command down
                    on error
                        -- Ignore errors from System Events
                    end try
                end if

                return "OK"
            on error errMsg
                return "ERROR_CLEAR: " & errMsg
            end try
        end tell
        """
    }

    static func sendControlCScript(appName: String, windowID: String, tabID: String, shouldActivateTerminal: Bool) -> String {
        // For Apple Terminal, Ctrl+C is typically ASCII code 3 (ETX).
        // `do script` with the character itself can work.
        let activateBlock = shouldActivateTerminal ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            \(activateBlock)

            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)

            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for sending Ctrl+C."
            end if

            if \(shouldActivateTerminal) then
                tell targetWindow to set selected tab to targetTab
            end if

            -- Sending ETX character (Ctrl+C)
            -- Ensure it's properly escaped for `do script` if it were more complex.
            -- For a single control char, direct use is often fine.
            do script "\\\\003" in targetTab -- \\003 is ETX (Ctrl+C)

            return "OK_CTRL_C_SENT"
        end tell
        """
    }

    // MARK: - Scripts for Find/Create Session Refactor

    static func listWindowsAndTabsWithTitlesScript(appName: String) -> String {
        return """
        set output_list to {}
        tell application "\(appName)"
            if not running then error "Terminal application \(appName) is not running."
            try
                set window_indices to index of windows
                repeat with i from 1 to count of window_indices
                    set w_index to item i of window_indices
                    set w to window id (id of window w_index)
                    set w_id_str to id of w as string

                    set tab_details to {}
                    set tab_indices to index of tabs of w
                    repeat with j from 1 to count of tab_indices
                        set t_index to item j of tab_indices
                        set t to tab id (id of tab t_index of w)
                        set t_id_str to id of t as string
                        set customTitle to custom title of t
                        if customTitle is missing value then set customTitle to ""
                        set end of tab_details to {t_id_str, customTitle}
                    end repeat
                    set end of output_list to {w_id_str, tab_details}
                end repeat
            on error errMsg number errNum
                error "AppleScript Error (Code " & (errNum as string) & "): " & errMsg
            end try
        end tell
        return output_list
        """
    }

    static func createWindowScript(appName: String, shouldActivate: Bool) -> String {
        return """
        tell application "\(appName)"
            if not running then
                if \(shouldActivate) then activate else run
                delay 0.5
            else if \(shouldActivate) then
                activate
            end if
            set new_window to make new window
            delay 0.2
            return id of new_window as string
        end tell
        """
    }

    static func createTabInWindowScript(appName: String, windowID: String, newSessionTitle: String, shouldActivate: Bool, selectTab: Bool) -> String {
        let escapedNewSessionTitle = newSessionTitle.replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'")
        return """
        tell application "\(appName)"
            if not running then error "Terminal application \(appName) is not running."
            set targetWindow to first window whose id is (\(windowID) as integer)
            if targetWindow is missing value then error "Window with ID \(windowID) not found."

            tell targetWindow
                if \(shouldActivate) then activate
                set newTab to do script ""
                delay 0.2 
                set newTabTTY to tty of newTab
                set newTabID to id of newTab as string
                set custom title of newTab to "\(escapedNewSessionTitle)" 

                if \(selectTab) then
                    set selected tab to newTab
                end if
                return {id of targetWindow as string, newTabID, newTabTTY, "\(escapedNewSessionTitle)"}
            end tell
        end tell
        """
    }

    static func activateTerminalAppScript(appName: String) -> String {
        return "tell application \"\(appName)\" to activate"
    }

    static func setSelectedTabScript(appName: String, windowID: String, tabID: String) -> String {
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            activate
            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)
            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for selecting tab."
            end if
            tell targetWindow
                set selected tab to targetTab
            end tell
            return true
        end tell
        """
    }

    // MARK: - Scripts for ExecuteCommand Refactor

    static func simpleExecuteShellCommandInTabScript(
        appName: String,
        windowID: String,
        tabID: String,
        shellCommandToExecute: String, // This is the fully formed shell command (e.g., with redirection, marker echo, etc.)
        shouldActivateTerminal: Bool
    ) -> String {
        let appleScriptSafeShellCommand = shellCommandToExecute
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        tell application "\(appName)"
            if not running then error "Terminal application \(appName) is not running."
            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)

            if targetWindow is missing value or targetTab is missing value then
                error "Session find error: Could not find window ID \(windowID) or tab ID \(tabID) for command execution."
            end if

            if \(shouldActivateTerminal) then
                activate
                tell targetWindow to set selected tab to targetTab
            end if

            do script "\(appleScriptSafeShellCommand)" in targetTab
            return "OK_COMMAND_SUBMITTED"
        end tell
        """
    }

    static func getTabHistoryScript(appName: String, windowID: String, tabID: String) -> String {
        return """
        tell application "\(appName)"
            if not running then error "Terminal is not running."
            set targetWindow to first window whose id is \(windowID)
            set targetTab to first tab of targetWindow whose id is \(tabID)
            if targetWindow is missing value or targetTab is missing value then
                error "Could not find window ID \(windowID) or tab ID \(tabID) for reading history."
            end if
            return history of targetTab
        end tell
        """
    }

    // --- End of Scripts for ExecuteCommand Refactor ---
}
