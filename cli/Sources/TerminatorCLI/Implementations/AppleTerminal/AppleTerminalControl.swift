import Foundation

// Helper structs for parsing AppleScript list output
struct AppleTerminalTabInfo {
    let id: String
    let title: String
}

struct AppleTerminalWindowInfo {
    let id: String
    let tabs: [AppleTerminalTabInfo]
}

struct AppleTerminalControl: TerminalControlling {
    let config: AppConfig
    let appName: String // Should be "Terminal" or "Terminal.app"

    init(config: AppConfig, appName: String) {
        self.config = config
        self.appName = appName
        Logger.log(level: .debug, "AppleTerminalControl initialized for app: \(appName)")
    }

    // Helper method to determine if Terminal should be focused based on preference
    func shouldFocus(focusPreference: AppConfig.FocusCLIArgument) -> Bool {
        switch focusPreference {
        case .forceFocus:
            true
        case .noFocus:
            false
        case .autoBehavior, .default:
            config.defaultFocusOnAction
        }
    }
}
