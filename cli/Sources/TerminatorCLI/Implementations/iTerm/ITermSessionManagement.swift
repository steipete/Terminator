import Foundation

// MARK: - Session Management Extension for ITermControl

extension ITermControl {
    // Helper struct to avoid large tuple warning
    struct SessionCreationData {
        let winID: String
        let tabID: String
        let sessionID: String
        let tty: String
    }

    func attentesFocus(focusPreference: AppConfig.FocusCLIArgument, defaultFocusSetting: Bool) -> Bool {
        switch focusPreference {
        case .forceFocus:
            true
        case .noFocus:
            false
        case .autoBehavior:
            defaultFocusSetting
        case .default:
            defaultFocusSetting
        }
    }

    static func clearSessionScreen(appName: String, sessionID: String, tag: String) {
        let clearScript = ITermScripts.clearSessionScript(
            appName: appName,
            sessionID: sessionID,
            shouldActivateITerm: false
        )
        let clearScriptResult = AppleScriptBridge.runAppleScript(script: clearScript)
        if case let .failure(error) = clearScriptResult {
            Logger.log(
                level: .warn,
                "[ITermControl] Failed to clear iTerm session for tag \(tag): \(error.localizedDescription)",
                file: #file,
                function: #function
            )
        }
    }
}
