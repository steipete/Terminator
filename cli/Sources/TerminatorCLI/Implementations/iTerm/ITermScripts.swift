import Foundation

enum ITermScripts {
    // MARK: - Session Introspection

    static func listSessionsScript(appName: String) -> String {
        ITermSessionIntrospectionScripts.listSessionsScript(appName: appName)
    }

    static func readSessionOutputScript(
        appName: String,
        sessionID: String,
        linesToRead: Int,
        shouldActivateITerm: Bool
    ) -> String {
        ITermSessionIntrospectionScripts.readSessionOutputScript(
            appName: appName,
            sessionID: sessionID,
            linesToRead: linesToRead,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func findWindowForProjectScript(appName: String, projectPath: String) -> String {
        ITermSessionIntrospectionScripts.findWindowForProjectScript(appName: appName, projectPath: projectPath)
    }

    static func getCurrentWindowIDScript(appName: String) -> String {
        ITermSessionIntrospectionScripts.getCurrentWindowIDScript(appName: appName)
    }

    static func listWindowsForGroupingScript(appName: String) -> String {
        ITermSessionIntrospectionScripts.listWindowsForGroupingScript(appName: appName)
    }

    // MARK: - Session Control

    static func focusSessionScript(
        appName: String,
        windowID: String,
        tabID: String,
        sessionID: String
    ) -> String {
        ITermSessionControlScripts.focusSessionScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            sessionID: sessionID
        )
    }

    static func clearSessionScript(
        appName: String,
        sessionID: String,
        shouldActivateITerm: Bool
    ) -> String {
        ITermSessionControlScripts.clearSessionScript(
            appName: appName,
            sessionID: sessionID,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func setTitleScript(
        appName: String,
        sessionID: String,
        newTitle: String
    ) -> String {
        ITermSessionControlScripts.setTitleScript(
            appName: appName,
            sessionID: sessionID,
            newTitle: newTitle
        )
    }

    static func setSessionNameScript(appName: String, sessionID: String, newName: String) -> String {
        ITermSessionControlScripts.setSessionNameScript(appName: appName, sessionID: sessionID, newName: newName)
    }

    static func setWindowNameScript(appName: String, windowID: String, newName: String) -> String {
        ITermSessionControlScripts.setWindowNameScript(appName: appName, windowID: windowID, newName: newName)
    }

    static func activateITermAppScript(appName: String) -> String {
        ITermSessionControlScripts.activateITermAppScript(appName: appName)
    }

    static func selectSessionInITermScript(
        appName: String,
        windowID: String,
        tabID: String,
        sessionID: String
    ) -> String {
        ITermSessionControlScripts.selectSessionInITermScript(
            appName: appName,
            windowID: windowID,
            tabID: tabID,
            sessionID: sessionID
        )
    }

    // MARK: - Session Creation

    static func createNewTabInWindowScript(
        appName: String,
        windowID: String,
        customTitle: String,
        commandToRunEscaped: String?,
        shouldActivateITerm: Bool
    ) -> String {
        ITermSessionCreationScripts.createNewTabInWindowScript(
            appName: appName,
            windowID: windowID,
            customTitle: customTitle,
            commandToRunEscaped: commandToRunEscaped,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func createNewWindowWithSessionScript(
        appName: String,
        customTitle: String,
        commandToRunEscaped: String?,
        shouldActivateITerm: Bool
    ) -> String {
        ITermSessionCreationScripts.createNewWindowWithSessionScript(
            appName: appName,
            customTitle: customTitle,
            commandToRunEscaped: commandToRunEscaped,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func createWindowWithProfileScript(appName: String, profileName: String, shouldActivate: Bool) -> String {
        ITermSessionCreationScripts.createWindowWithProfileScript(
            appName: appName,
            profileName: profileName,
            shouldActivate: shouldActivate
        )
    }

    static func createTabInWindowWithProfileScript(
        appName: String,
        windowID: String,
        profileName: String,
        shouldActivate: Bool,
        selectTab: Bool
    ) -> String {
        ITermSessionCreationScripts.createTabInWindowWithProfileScript(
            appName: appName,
            windowID: windowID,
            profileName: profileName,
            shouldActivate: shouldActivate,
            selectTab: selectTab
        )
    }

    // MARK: - Command Execution

    static func sendControlCScript(
        appName: String,
        sessionID: String,
        shouldActivateITerm: Bool
    ) -> String {
        ITermCommandExecutionScripts.sendControlCScript(
            appName: appName,
            sessionID: sessionID,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func simpleExecuteShellCommandInSessionScript(
        appName: String,
        sessionID: String,
        shellCommandToExecuteEscapedForAppleScript: String,
        shouldActivateITerm: Bool
    ) -> String {
        ITermCommandExecutionScripts.simpleExecuteShellCommandInSessionScript(
            appName: appName,
            sessionID: sessionID,
            shellCommandToExecuteEscapedForAppleScript: shellCommandToExecuteEscapedForAppleScript,
            shouldActivateITerm: shouldActivateITerm
        )
    }

    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        ITermCommandExecutionScripts.getPGIDAppleScript(ttyNameOnly: ttyNameOnly)
    }

    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        ITermCommandExecutionScripts.findPgidScriptForKill(ttyNameOnly: ttyNameOnly)
    }
}
