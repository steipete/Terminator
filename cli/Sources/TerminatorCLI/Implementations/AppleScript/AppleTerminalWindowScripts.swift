import Foundation

// MARK: - Window and Tab Management Scripts

enum AppleTerminalWindowScripts {
    static func listWindowsAndTabsWithTitlesScript(appName: String) -> String {
        """
        set windowData to {}
        tell application "\(appName)"
            repeat with aWindow in windows
                set windowID to id of aWindow
                set tabList to {}
                repeat with aTab in tabs of aWindow
                    set tabIndex to index of aTab
                    set tabTitle to custom title of aTab
                    if tabTitle is missing value then
                        set tabTitle to ""
                    end if
                    set end of tabList to {tabIndex, tabTitle}
                end repeat
                set end of windowData to {windowID, tabList}
            end repeat
        end tell
        return windowData
        """
    }

    static func createWindowScript(appName: String, shouldActivateTerminal: Bool) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        return """
        tell application "\(appName)"
            \(activateCommand)set newWindow to make new window
            set windowID to id of newWindow
            return windowID as string
        end tell
        """
    }

    static func createTabInWindowScript(
        appName: String,
        windowID: String,
        newSessionTitle: String,
        shouldActivateTerminal: Bool
    ) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        return """
        tell application "\(appName)"
            \(activateCommand)set targetWindow to window id \(windowID)

            -- Create a new tab
            tell application "System Events" to keystroke "t" using command down

            -- The newly created tab becomes the selected tab
            set newTab to selected tab of targetWindow
            set custom title of newTab to "\(newSessionTitle)"

            -- Get the tab's index (which we'll use as ID)
            set tabID to index of newTab

            -- Get the TTY device
            set ttyDevice to tty of newTab

            -- Get the title
            set tabTitle to custom title of newTab

            return {windowID as string, tabID as string, ttyDevice, tabTitle}
        end tell
        """
    }

    static func activateTerminalAppScript(appName: String) -> String {
        """
        tell application "\(appName)"
            activate
        end tell
        """
    }

    static func setSelectedTabScript(appName: String, windowID: String, tabID: String) -> String {
        """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            set selected of targetTab to true
        end tell
        """
    }
}
