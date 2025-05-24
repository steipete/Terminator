import ArgumentParser
import Foundation

// Global app version - can be updated by a build script
let APP_VERSION = "0.1.0"

// MARK: - Error Handling (SDD 3.2.8)

// MARK: - Main CLI Structure
@main
struct TerminatorCLI: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "A Swift CLI to manage macOS terminal sessions for an MCP plugin.",
        version: APP_VERSION,
        subcommands: [Exec.self, Read.self, List.self, Info.self, Focus.self, Kill.self],
        defaultSubcommand: Info.self
    )


    // Global options, to be usable by subcommands if they embed this type.
    struct GlobalOptions: ParsableArguments {
        @Option(name: .long, help: "Terminal app (e.g., \"Terminal\", \"iTerm\"). Env: TERMINATOR_APP")
        var terminalApp: String?

        @Option(name: .long, help: "Logging verbosity (debug, info, warn, error, fatal). Env: TERMINATOR_LOG_LEVEL")
        var logLevel: String?

        @Option(name: .long, help: "Log directory. Env: TERMINATOR_LOG_DIR")
        var logDir: String?

        @Option(name: .long, help: "Tab grouping strategy (off, project, smart). Env: TERMINATOR_WINDOW_GROUPING")
        var grouping: String?

        @Flag(name: [.short, .long], help: "Verbose logging (alias for --log-level debug).")
        var verbose: Bool = false

        @Option(name: .long, help: "Default focus behavior for kill actions (true, false). Env: TERMINATOR_DEFAULT_FOCUS_ON_KILL")
        var defaultFocusOnKill: Bool?
    }
    
    @OptionGroup var globals: GlobalOptions

    static var currentConfig: AppConfig! // Holds the globally resolved config

    mutating func validate() throws {
        TerminatorCLI.currentConfig = AppConfig(
            terminalAppOption: globals.terminalApp,
            logLevelOption: globals.logLevel ?? (globals.verbose ? "debug" : nil),
            logDirOption: globals.logDir,
            groupingOption: globals.grouping,
            defaultLinesOption: nil, 
            backgroundStartupOption: nil,
            foregroundCompletionOption: nil,
            defaultFocusOption: nil,
            sigintWaitOption: nil,
            sigtermWaitOption: nil,
            defaultFocusOnKillOption: globals.defaultFocusOnKill
        )
        
        // Configure the logger now that AppConfig is available.
        // Assuming Logger has a static configure method.
        // Adjust alsoPrintToStdOut as needed, true seems reasonable for a CLI tool.
        Logger.configure(level: TerminatorCLI.currentConfig.logLevel, 
                         directory: TerminatorCLI.currentConfig.logDir, 
                         alsoPrintToStdOut: true) 
        
        Logger.log(level: .debug, "Global options validated. Config loaded. Logger configured.")
        Logger.log(level: .debug, "Using Swift version: \(swiftVersion())")
        Logger.log(level: .debug, "macOS version: \(macOSVersion())")

        // SDD 3.2.3: Validate Ghosty configuration - if AppConfig marked it as invalid,
        // the CLI should error out with code 2.
        if TerminatorCLI.currentConfig.terminalApp == "INVALID_GHOSTY_CONFIGURATION" || 
           (TerminatorCLI.currentConfig.terminalAppEnum == .unknown && 
            (globals.terminalApp?.lowercased() == "ghosty" || 
             ProcessInfo.processInfo.environment["TERMINATOR_APP"]?.lowercased() == "ghosty")) {
            
            let errorMsg = "Configuration Error: TERMINATOR_APP is set to Ghosty, but Ghosty is not installed, not scriptable, or failed validation. Please check your Ghosty installation and macOS Automation Permissions."
            fputs("Error: \(errorMsg)\n", stderr)
            Logger.log(level: .error, errorMsg) // Log it as well, in case logger is partially working
            throw ExitCode(ErrorCodes.configurationError) // Exit code 2
        }
    }
    
    // This is called automatically by ArgumentParser on exit
    static func main() {
        // Ensure logger is flushed and file closed on exit
        atexit_b { Logger.shutdown() }
        super.main()
    }
    
    private func swiftVersion() -> String {
        #if swift(>=6.0)
        "Swift 6.0 or later"
        #elseif swift(>=5.9)
        "Swift 5.9"
        #elseif swift(>=5.8)
        "Swift 5.8"
        #else
        "Older Swift version"
        #endif
    }
    
    private func macOSVersion() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}


// MARK: - Subcommands

// MARK: - Command Definitions (SDD 3.2.5)






