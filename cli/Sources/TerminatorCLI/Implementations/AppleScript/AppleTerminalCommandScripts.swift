import Foundation

// MARK: - Command Execution Scripts

enum AppleTerminalCommandScripts {
    struct ExecuteCommandParams {
        let appName: String
        let windowID: String
        let tabID: String
        let command: String
        let clearBeforeExecute: Bool
        let projectPath: String?
        let shouldActivateTerminal: Bool
        let waitForCompletion: Bool
        let timeout: Double
        let execInBackground: Bool
    }

    static func executeCommandScript(params: ExecuteCommandParams) -> String {
        let appName = params.appName
        let windowID = params.windowID
        let tabID = params.tabID
        let command = params.command
        let clearBeforeExecute = params.clearBeforeExecute
        let projectPath = params.projectPath
        let shouldActivateTerminal = params.shouldActivateTerminal
        let waitForCompletion = params.waitForCompletion
        let timeout = params.timeout
        let execInBackground = params.execInBackground
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""

        let clearCommand = clearBeforeExecute ? "clear && " : ""
        let fullCommand = clearCommand + command

        let cdCommand = if let projectPath {
            """
            -- First, navigate to the project directory
            do script "cd '\(projectPath)'" in targetTab
            delay 0.5

            """
        } else {
            ""
        }

        let backgroundSuffix = execInBackground ? " &" : ""
        let commandToExecute = fullCommand + backgroundSuffix

        let waitLogic = if waitForCompletion && !execInBackground {
            """

            -- Wait for command to complete
            set startTime to current date
            repeat
                if busy of targetTab is false then
                    exit repeat
                end if
                if (current date) - startTime > \(timeout) then
                    error "Command execution timed out after \(timeout) seconds"
                end if
                delay 0.1
            end repeat
            """
        } else {
            ""
        }

        return """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            \(activateCommand)\(cdCommand)-- Execute the command
            do script "\(commandToExecute)" in targetTab\(waitLogic)

            -- Return command result info
            set tabTitle to custom title of targetTab
            set tabBusy to busy of targetTab
            return {windowID as string, \(tabID) as string, tabTitle, tabBusy}
        end tell
        """
    }

    // Backward compatibility overload
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
        let params = ExecuteCommandParams(
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
        return executeCommandScript(params: params)
    }

    static func readSessionOutputScript(
        appName: String,
        windowID: String,
        tabID: String,
        tag _: String
    ) -> String {
        """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow

            -- Get the tab's history
            set tabHistory to history of targetTab

            -- Return the history
            return tabHistory
        end tell
        """
    }

    static func simpleExecuteShellCommandInTabScript(
        appName: String,
        windowID: String,
        tabID: String,
        command: String,
        shouldActivateTerminal: Bool
    ) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        return """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            \(activateCommand)do script "\(command)" in targetTab

            return "OK"
        end tell
        """
    }

    static func sendControlCScript(
        appName: String,
        windowID: String,
        tabID: String,
        shouldActivateTerminal: Bool
    ) -> String {
        let activateCommand = shouldActivateTerminal ? "activate\n" : ""
        return """
        tell application "\(appName)"
            set targetWindow to window id \(windowID)
            set targetTab to tab \(tabID) of targetWindow
            \(activateCommand)-- Send Ctrl+C to the tab
            tell application "System Events"
                key code 8 using control down -- 8 is the key code for 'c'
            end tell

            return "OK_CTRL_C_SENT"
        end tell
        """
    }
}
