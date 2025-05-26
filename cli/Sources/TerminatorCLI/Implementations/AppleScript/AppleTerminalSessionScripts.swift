import Foundation

// MARK: - Session Management Scripts

enum AppleTerminalSessionScripts {
    static func listSessionsScript(appName: String) -> String {
        """
        set sessionList to {}
        tell application "\(appName)"
            repeat with aWindow in windows
                set windowID to id of aWindow
                repeat with aTab in tabs of aWindow
                    set tabIndex to index of aTab
                    set tabTitle to custom title of aTab
                    if tabTitle is missing value then
                        set tabTitle to ""
                    end if
                    set end of sessionList to {windowID, tabIndex, tabTitle}
                end repeat
            end repeat
        end tell
        return sessionList
        """
    }

    static func focusExistingSessionScript(appName: String, windowID: String, tabID: String) -> String {
        """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            set selected of targetTab to true
            set frontmost of targetWindow to true
            activate
        end tell
        """
    }

    static func focusSessionScript(appName: String, windowID: String, tabID: String) -> String {
        """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            set selected of targetTab to true
            set frontmost of targetWindow to true
            activate
        end tell
        """
    }

    static func clearSessionScript(
        appName: String,
        windowID: String,
        tabID: String,
        shouldActivateTerminal: Bool
    ) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        let keystrokeCommand = shouldActivateTerminal ? """
        tell application \"System Events\"
            keystroke \"k\" using command down
        end tell
        """ : ""

        return """
        tell application \"\(appName)\"\n            \(activateCommand)set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            do script \"clear && clear\" in targetTab
            delay 0.1 -- Allow clear to process before keystroke
            \(keystrokeCommand)
        end tell
        """
    }

    static func getTabHistoryScript(appName: String, windowID: String, tabID: String) -> String {
        """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            return history of targetTab
        end tell
        """
    }
}
