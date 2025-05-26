import Foundation

enum ITermSessionCreationScripts {
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
            if not running then
                run
                delay 0.5
            end if
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
            if not running then
                run
                delay 0.5
            end if
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

    static func createWindowWithProfileScript(appName: String, profileName: String, shouldActivate: Bool) -> String {
        let profileToUse = profileName.isEmpty ? "Default" : profileName
        let activation = shouldActivate ? "activate" : ""
        return """
        tell application "\(appName)"
            if not running then
                run
                delay 0.5
            end if
            \(activation)
            try
                set new_window to (create window with profile "\(profileToUse)")
                delay 0.2 -- Allow window and session to initialize
                set win_id to id of new_window as string
                set current_tab to current tab of new_window
                set tab_id to id of current_tab as string
                set current_session to current session of current_tab
                set session_id to id of current_session as string
                set session_tty to tty of current_session
                return {win_id, tab_id, session_id, session_tty, "OK"}
            on error errMsg number errNum
                return {"", "", "", "", "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"}
            end try
        end tell
        """
    }

    static func createTabInWindowWithProfileScript(
        appName: String,
        windowID: String,
        profileName: String,
        shouldActivate: Bool,
        selectTab: Bool
    ) -> String {
        let profileToUse = profileName.isEmpty ? "Default" : profileName
        var activationCommands = ""
        if shouldActivate {
            activationCommands += "activate\n"
            activationCommands += "           select target_window\n"
        }
        if selectTab {
            activationCommands += "           tell target_window to select new_tab\n"
        }

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
                    return {"", "", "", "ERROR: Window with ID \(windowID) not found."}
                end if

                \(activationCommands)

                tell target_window
                    set new_tab to (create tab with profile "\(profileToUse)")
                end tell
                delay 0.2 -- Allow session to initialize

                set tab_id to id of new_tab as string
                set current_session to current session of new_tab
                set session_id to id of current_session as string
                set session_tty to tty of current_session

                return {tab_id, session_id, session_tty, "OK"}
            on error errMsg number errNum
                return {"", "", "", "ERROR: " & errMsg & " (Num: " & (errNum as string) & ")"}
            end try
        end tell
        """
    }
}
