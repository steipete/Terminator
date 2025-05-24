import ArgumentParser
import Foundation

// MARK: - Configuration Management (SDD 3.2.3)

struct AppConfig {
    let terminalApp: String
    let logLevel: LogLevel
    let logDir: URL
    let windowGrouping: WindowGrouping
    let defaultLines: Int
    let backgroundStartupSeconds: Int
    let foregroundCompletionSeconds: Int
    let defaultFocusOnAction: Bool
    let sigintWaitSeconds: Int
    let sigtermWaitSeconds: Int
    let defaultFocusOnKill: Bool
    let defaultBackgroundExecution: Bool
    let preKillScriptPath: String?
    let reuseBusySessions: Bool
    let iTermProfileName: String?

    enum LogLevel: String, CaseIterable, ExpressibleByArgument {
        case debug, info, warn, error, fatal, none

        // To allow comparison, e.g., level.rawValue >= currentLogLevel.rawValue
        var intValue: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warn: return 2
            case .error: return 3
            case .fatal: return 4
            case .none: return 5
            }
        }
    }

    enum WindowGrouping: String, CaseIterable, ExpressibleByArgument {
        case off, project, smart // "current", "new" are handled by specific logic in controllers based on this
    }

    // Enum for different terminal applications supported
    // This should align with TerminalAppType used in TerminalAppController
    enum TerminalAppType: String, CaseIterable {
        case appleTerminal = "Terminal"
        case iterm = "iTerm" // Covers iTerm2 as well for scripting name
        case ghosty = "Ghosty"
        case unknown
    }

    var terminalAppEnum: TerminalAppType {
        switch terminalApp.lowercased() {
        case "terminal", "appleterminal", "apple terminal":
            return .appleTerminal
        case "iterm", "iterm2", "iterm.app":
            return .iterm
        case "ghosty", "ghosty.app":
            return .ghosty
        default:
            return .unknown
        }
    }

    // As per SDD 3.2.5 for --focus-mode
    enum FocusCLIArgument: String, CaseIterable, ExpressibleByArgument { // Made ExpressibleByArgument if used directly in ArgumentParser options for subcommands
        case forceFocus = "force-focus"
        case noFocus = "no-focus"
        case autoBehavior = "auto-behavior"
        case `default`
    }

    init(
        terminalAppOption: String?,
        logLevelOption: String?,
        logDirOption: String?,
        groupingOption: String?,
        defaultLinesOption: Int?,
        backgroundStartupOption: Int?,
        foregroundCompletionOption: Int?,
        defaultFocusOption: Bool?,
        sigintWaitOption: Int?,
        sigtermWaitOption: Int?,
        defaultFocusOnKillOption: Bool?,
        preKillScriptPathOption: String?,
        reuseBusySessionsOption: Bool?,
        iTermProfileNameOption: String?
    ) {
        let resolvedTerminalApp = AppConfig.resolve(
            cli: terminalAppOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_APP"],
            default: "Terminal"
        )

        // Validate Ghosty if selected (SDD 3.2.3)
        var validatedTerminalApp = resolvedTerminalApp
        if resolvedTerminalApp.lowercased() == "ghosty" || resolvedTerminalApp.lowercased() == "ghosty.app" {
            let ghostyValidationScript = "tell application \"Ghosty\" to get version"
            let result = AppleScriptBridge.runAppleScript(script: ghostyValidationScript)
            switch result {
            case let .success(versionInfo):
                // Ghosty validation successful - will log after Logger is configured
                _ = versionInfo
            case let .failure(error):
                fputs("Error: TERMINATOR_APP set to Ghosty, but Ghosty failed validation. Error: \(error.localizedDescription). Check if Ghosty is installed and scriptable.\n", stderr)
                fputs("Terminator will proceed as if Ghosty is not correctly configured (which may lead to exit code 2).\n", stderr)
                // Mark terminalApp as invalid so subsequent checks can handle it, potentially leading to exit code 2.
                // A more robust solution might be to make AppConfig.init throwing or have a separate validation function.
                validatedTerminalApp = "INVALID_GHOSTY_CONFIGURATION"
                // The terminalAppEnum will now also return .unknown due to this change, which should be handled
                // by TerminalAppController or TerminatorCLI.validate().
            }
        }

        terminalApp = validatedTerminalApp

        let resolvedLogLevelString = AppConfig.resolve(
            cli: logLevelOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_LOG_LEVEL"],
            default: "info"
        ).lowercased()
        logLevel = LogLevel(rawValue: resolvedLogLevelString) ?? .info

        let logDirEnvValue = ProcessInfo.processInfo.environment["TERMINATOR_LOG_DIR"]
        let logDirCliValue = logDirOption

        var resolvedLogDirString: String
        if let cliValue = logDirCliValue, !cliValue.isEmpty {
            resolvedLogDirString = cliValue
        } else if let envValue = logDirEnvValue, !envValue.isEmpty {
            resolvedLogDirString = envValue
        } else {
            resolvedLogDirString = "~/Library/Logs/terminator-mcp/"
        }

        if resolvedLogDirString.uppercased() == "SYSTEM_TEMP" { // SDD 3.2.3 Log Dir Fallback
            logDir = AppConfig.systemTempLogDir()
        } else {
            logDir = AppConfig.expandPath(resolvedLogDirString) ?? AppConfig.fallbackLogDir() // fallbackLogDir is the default if expandPath fails
        }

        // Ensure log directory exists - moved here so it's done once.
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            fputs("Error: Could not create log directory at \(logDir.path). Error: \(error.localizedDescription)\n", stderr)
        }

        let resolvedGroupingString = AppConfig.resolve(
            cli: groupingOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_WINDOW_GROUPING"],
            default: "smart" // Default to smart as per previous logic
        ).lowercased()
        windowGrouping = WindowGrouping(rawValue: resolvedGroupingString) ?? .smart

        defaultLines = AppConfig.resolveInt(
            cli: defaultLinesOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_DEFAULT_LINES"],
            default: 100
        )
        backgroundStartupSeconds = AppConfig.resolveInt(
            cli: backgroundStartupOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_BACKGROUND_STARTUP_SECONDS"],
            default: 5
        )
        foregroundCompletionSeconds = AppConfig.resolveInt(
            cli: foregroundCompletionOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_FOREGROUND_COMPLETION_SECONDS"],
            default: 60
        )
        defaultFocusOnAction = AppConfig.resolveBool(
            cli: defaultFocusOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_DEFAULT_FOCUS_ON_ACTION"],
            default: true
        )
        sigintWaitSeconds = AppConfig.resolveInt(
            cli: sigintWaitOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_SIGINT_WAIT_SECONDS"],
            default: 2
        )
        sigtermWaitSeconds = AppConfig.resolveInt(
            cli: sigtermWaitOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_SIGTERM_WAIT_SECONDS"],
            default: 2
        )
        defaultFocusOnKill = AppConfig.resolveBool(
            cli: defaultFocusOnKillOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_DEFAULT_FOCUS_ON_KILL"],
            default: false
        )
        defaultBackgroundExecution = AppConfig.resolveBool(
            cli: nil, // Not a direct CLI flag for AppConfig default itself
            env: ProcessInfo.processInfo.environment["TERMINATOR_DEFAULT_BACKGROUND_EXECUTION"],
            default: false // Default to foreground
        )

        preKillScriptPath = AppConfig.resolve(
            cli: preKillScriptPathOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_PRE_KILL_SCRIPT_PATH"],
            default: nil // Default to nil, meaning no script
        )

        reuseBusySessions = AppConfig.resolveBool(
            cli: reuseBusySessionsOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_REUSE_BUSY_SESSIONS"],
            default: false // Default to false, do not reuse busy sessions unless explicitly configured
        )

        iTermProfileName = AppConfig.resolve(
            cli: iTermProfileNameOption,
            env: ProcessInfo.processInfo.environment["TERMINATOR_ITERM_PROFILE_NAME"],
            default: nil // Default to nil, meaning iTerm uses its default profile
        )

        // Logger.configure is called from TerminatorCLI.validate() after AppConfig is initialized.
        // Logging AppConfig details is also done from TerminatorCLI.validate() or where AppConfig is instantiated.
    }

    // Static helper methods for resolving configuration values
    static func resolve<T: LosslessStringConvertible>(cli: T?, env: String?, default defaultValue: T) -> T {
        if let cliValue = cli { return cliValue }
        if let envValueString = env, let envValue = T(envValueString) { return envValue }
        return defaultValue
    }

    static func resolve(cli: String?, env: String?, default defaultValue: String?) -> String? {
        if let cliValue = cli { return cliValue.isEmpty && defaultValue == nil ? nil : cliValue }
        if let envValue = env { return envValue.isEmpty && defaultValue == nil ? nil : envValue }
        return defaultValue
    }

    static func resolve(cli: String?, env: String?, default defaultValue: String) -> String {
        if let cliValue = cli, !cliValue.isEmpty { return cliValue }
        if let envValue = env, !envValue.isEmpty { return envValue }
        return defaultValue
    }

    static func resolveInt(cli: Int?, env: String?, default defaultValue: Int) -> Int {
        if let cliValue = cli { return cliValue }
        if let envValueString = env, let envValue = Int(envValueString) { return envValue }
        return defaultValue
    }

    static func resolveBool(cli: Bool?, env: String?, default defaultValue: Bool) -> Bool {
        if let cliValue = cli { return cliValue }
        if let envValueString = env?.lowercased() {
            return ["true", "1", "yes", "on"].contains(envValueString)
        }
        return defaultValue
    }

    static func expandPath(_ path: String) -> URL? {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if expandedPath.isEmpty { return nil }
        return URL(fileURLWithPath: expandedPath)
    }

    static func fallbackLogDir() -> URL {
        // This is the default path if user doesn't specify anything or if their path is invalid.
        // Per spec, default is ~/Library/Logs/terminator-mcp/
        // If THAT fails, then NSTemporaryDirectory()/terminator-mcp/
        // This function will represent the "~/Library/Logs/terminator-mcp/" path primarily,
        // and systemTempLogDir() will be the ultimate fallback or for "SYSTEM_TEMP"
        let defaultUserLogDir = expandPath("~/Library/Logs/terminator-mcp/")

        if let dir = defaultUserLogDir, createDirIfNeeded(dir) {
            return dir
        } else {
            // If default user log dir fails, use system temp as final fallback.
            return systemTempLogDir()
        }
    }

    static func systemTempLogDir() -> URL { // New function for SYSTEM_TEMP and ultimate fallback
        let tempDir = FileManager.default.temporaryDirectory
        let fallbackDir = tempDir.appendingPathComponent("terminator-mcp", isDirectory: true)
        _ = createDirIfNeeded(fallbackDir) // Best effort to create
        return fallbackDir
    }

    // Helper to create directory and return success status
    private static func createDirIfNeeded(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            // Use fputs for direct stderr output as logger might not be configured yet
            fputs("Error: Could not create log directory at \(url.path). Error: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    var asDictionary: [String: Any] {
        let configDict: [String: Any?] = [
            "TERMINATOR_APP": terminalApp,
            "TERMINATOR_LOG_DIR": logDir.path,
            "TERMINATOR_LOG_LEVEL": logLevel.rawValue,
            "TERMINATOR_WINDOW_GROUPING": windowGrouping.rawValue,
            "TERMINATOR_DEFAULT_LINES": defaultLines,
            "TERMINATOR_BACKGROUND_STARTUP_SECONDS": backgroundStartupSeconds,
            "TERMINATOR_FOREGROUND_COMPLETION_SECONDS": foregroundCompletionSeconds,
            "TERMINATOR_DEFAULT_FOCUS_ON_ACTION": defaultFocusOnAction,
            "TERMINATOR_SIGINT_WAIT_SECONDS": sigintWaitSeconds,
            "TERMINATOR_SIGTERM_WAIT_SECONDS": sigtermWaitSeconds,
            "TERMINATOR_DEFAULT_FOCUS_ON_KILL": defaultFocusOnKill,
            "TERMINATOR_DEFAULT_BACKGROUND_EXECUTION": defaultBackgroundExecution,
            "TERMINATOR_PRE_KILL_SCRIPT_PATH": preKillScriptPath,
            "TERMINATOR_REUSE_BUSY_SESSIONS": reuseBusySessions,
            "TERMINATOR_ITERM_PROFILE_NAME": iTermProfileName,
        ]
        return configDict.compactMapValues { $0 }
    }
}
