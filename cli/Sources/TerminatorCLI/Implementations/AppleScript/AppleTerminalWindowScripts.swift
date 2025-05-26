import Foundation

enum AppleTerminalWindowScripts {
    static func listWindowsAndTabsWithTitlesScript(appName: String) -> String {
        """
        set windowData to {}
        tell application "\(appName)"
            set wasRunning to running
            if not running then
                run
                -- Wait for Terminal to be ready
                set waitCount to 0
                repeat while waitCount < 20
                    try
                        if (count of windows) >= 0 then
                            -- Terminal is responding to window queries
                            exit repeat
                        end if
                    on error
                        -- Terminal not ready yet
                    end try
                    delay 0.5
                    set waitCount to waitCount + 1
                end repeat
            end if

            -- Try to get windows with error handling
            try
                if (count of windows) > 0 then
                    repeat with aWindow in windows
                        try
                            set windowID to id of aWindow
                            set tabList to {}
                            try
                                repeat with aTab in tabs of aWindow
                                    try
                                        set tabIndex to index of aTab
                                        set tabTitle to custom title of aTab
                                        if tabTitle is missing value then
                                            set tabTitle to ""
                                        end if
                                        set end of tabList to {tabIndex, tabTitle}
                                    on error
                                        -- Skip this tab
                                    end try
                                end repeat
                            on error
                                -- No tabs accessible
                            end try
                            set end of windowData to {windowID, tabList}
                        on error
                            -- Skip this window
                        end try
                    end repeat
                end if
            on error
                -- No windows accessible
            end try
        end tell
        return windowData
        """
    }

    static func createWindowScript(appName: String, shouldActivateTerminal: Bool) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        return """
        tell application "\(appName)"
            set wasRunning to running
            if not running then
                run
                -- Wait for Terminal to create its default window
                set waitCount to 0
                repeat while (count of windows) = 0 and waitCount < 20
                    delay 0.5
                    set waitCount to waitCount + 1
                end repeat
            end if
            \(activateCommand)

            -- If Terminal just started and has a window, use it
            if not wasRunning and (count of windows) > 0 then
                set windowID to id of window 1
                return windowID as string
            else
                -- Otherwise create a new window
                set newWindow to make new window
                set windowID to id of newWindow
                return windowID as string
            end if
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
