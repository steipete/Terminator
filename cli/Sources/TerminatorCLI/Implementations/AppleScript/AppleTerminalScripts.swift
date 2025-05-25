import Foundation

// This enum provides backward compatibility by delegating to the new specialized script structs
// while maintaining the original API for existing code
enum AppleTerminalScripts {
    // MARK: - Session Management (Delegated)

    static func listSessionsScript(appName: String) -> String {
        // Complex listing logic for sessions with error handling
        """
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
        projectPath: String?,
        tag: String,
        newSessionTitle: String,
        shouldFocusNewTab: Bool,
        shouldActivateTerminal: Bool
    ) -> String {
        // Complex find or create session logic - kept here due to size
        let cdCommand: String
        if let projectPath {
            cdCommand = """
            -- Navigate to project directory
            do script "cd '\(projectPath)'" in selectedTab
            delay 0.5

            """
        } else {
            cdCommand = ""
        }

        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        let focusCommand = shouldFocusNewTab ? """
        set selected of selectedTab to true
        set frontmost of targetWindow to true
        """ : ""

        return """
        tell application "\(appName)"
            \(activateCommand)-- First, look for an existing session with the tag
            set foundSession to false
            set targetWindow to missing value
            set selectedTab to missing value

            repeat with aWindow in windows
                set windowID to id of aWindow
                repeat with aTab in tabs of aWindow
                    set tabTitle to custom title of aTab
                    if tabTitle contains "[\(tag)]" then
                        set foundSession to true
                        set targetWindow to aWindow
                        set selectedTab to aTab
                        exit repeat
                    end if
                end repeat
                if foundSession then exit repeat
            end repeat

            if not foundSession then
                -- No existing session found, create a new tab
                if (count of windows) = 0 then
                    -- No windows exist, create one
                    set targetWindow to make new window
                else
                    -- Use the frontmost window
                    set targetWindow to front window
                end if

                -- Create a new tab
                tell application "System Events" to keystroke "t" using command down

                -- The newly created tab becomes the selected tab
                set selectedTab to selected tab of targetWindow
                set custom title of selectedTab to "\(newSessionTitle)"
            end if

            \(cdCommand)\(focusCommand)
            -- Return session info
            set windowID to id of targetWindow
            set tabID to index of selectedTab
            set ttyDevice to tty of selectedTab
            set tabTitle to custom title of selectedTab

            return {windowID as string, tabID as string, ttyDevice, tabTitle, foundSession}
        end tell
        """
    }

    // MARK: - Delegate to Session Scripts

    static func focusExistingSessionScript(appName: String, windowID: String, tabID: String) -> String {
        AppleTerminalSessionScripts.focusExistingSessionScript(appName: appName, windowID: windowID, tabID: tabID)
    }

    static func focusSessionScript(appName: String, windowID: String, tabID: String) -> String {
        AppleTerminalSessionScripts.focusSessionScript(appName: appName, windowID: windowID, tabID: tabID)
    }

    static func clearSessionScript(
        appName: String,
        windowID: String,
        tabID: String,
        shouldActivateTerminal: Bool
    ) -> String {
        AppleTerminalSessionScripts.clearSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: shouldActivateTerminal
        )
    }

    static func getTabHistoryScript(appName: String, windowID: String, tabID: String) -> String {
        AppleTerminalSessionScripts.getTabHistoryScript(appName: appName, windowID: windowID, tabID: tabID)
    }

    // MARK: - Delegate to Command Scripts

    // swiftlint:disable:next function_parameter_count
    static func executeCommandScript(
        appName: String,
        windowID: String,
        tabID: String,
        command: String,
        clearBeforeExecute: Bool,
        projectPath: String?,
        shouldActivateTerminal: Bool,
        waitForCompletion: Bool,
        timeout: Double,
        execInBackground: Bool
    ) -> String {
        AppleTerminalCommandScripts.executeCommandScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            command: command,
            clearBeforeExecute: clearBeforeExecute,
            projectPath: projectPath,
            shouldActivateTerminal: shouldActivateTerminal,
            waitForCompletion: waitForCompletion,
            timeout: timeout,
            execInBackground: execInBackground
        )
    }

    static func readSessionOutputScript(
        appName: String,
        windowID: String,
        tabID: String,
        tag: String
    ) -> String {
        AppleTerminalCommandScripts.readSessionOutputScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            tag: tag
        )
    }

    static func simpleExecuteShellCommandInTabScript(
        appName: String,
        windowID: String,
        tabID: String,
        command: String,
        shouldActivateTerminal: Bool
    ) -> String {
        AppleTerminalCommandScripts.simpleExecuteShellCommandInTabScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            command: command,
            shouldActivateTerminal: shouldActivateTerminal
        )
    }

    static func sendControlCScript(
        appName: String,
        windowID: String,
        tabID: String,
        shouldActivateTerminal: Bool
    ) -> String {
        AppleTerminalCommandScripts.sendControlCScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            shouldActivateTerminal: shouldActivateTerminal
        )
    }

    // MARK: - Delegate to Window Scripts

    static func listWindowsAndTabsWithTitlesScript(appName: String) -> String {
        AppleTerminalWindowScripts.listWindowsAndTabsWithTitlesScript(appName: appName)
    }

    static func createWindowScript(appName: String, shouldActivateTerminal: Bool) -> String {
        AppleTerminalWindowScripts.createWindowScript(appName: appName, shouldActivateTerminal: shouldActivateTerminal)
    }

    static func createTabInWindowScript(
        appName: String,
        windowID: String,
        newSessionTitle: String,
        shouldActivateTerminal: Bool
    ) -> String {
        AppleTerminalWindowScripts.createTabInWindowScript(
            appName: appName,
            windowID: windowID,
            newSessionTitle: newSessionTitle,
            shouldActivateTerminal: shouldActivateTerminal
        )
    }

    static func activateTerminalAppScript(appName: String) -> String {
        AppleTerminalWindowScripts.activateTerminalAppScript(appName: appName)
    }

    static func setSelectedTabScript(appName: String, windowID: String, tabID: String) -> String {
        AppleTerminalWindowScripts.setSelectedTabScript(appName: appName, windowID: windowID, tabID: tabID)
    }

    // MARK: - Delegate to Process Scripts

    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        AppleTerminalProcessScripts.findPgidScriptForKill(ttyNameOnly: ttyNameOnly)
    }

    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        AppleTerminalProcessScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
    }
}
