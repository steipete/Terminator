import ArgumentParser
@testable import TerminatorCLI
import XCTest

/// Base class for Terminator CLI tests with shared utilities
class BaseTerminatorTests: XCTestCase {
    /// Runs the Terminator CLI executable with given arguments and returns output.
    func runCommand(arguments: [String]) throws -> (output: String, errorOutput: String, exitCode: ExitCode) {
        // Create a Process to run the built terminator executable
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("terminator")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        // ArgumentParser's ExitCode is Int32
        let exitCodeValue = process.terminationStatus
        return (output, errorOutput, ExitCode(exitCodeValue))
    }

    /// Returns path to the built products directory.
    var productsDirectory: URL {
        #if os(macOS)
            for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
                return bundle.bundleURL.deletingLastPathComponent()
            }
            fatalError("couldn't find the products directory")
        #else
            return Bundle.main.bundleURL
        #endif
    }

    override func setUp() {
        super.setUp()
        // Clear any environment variables that might interfere with tests
        unsetenv("TERMINATOR_APP")
        unsetenv("TERMINATOR_LOG_LEVEL")
        unsetenv("TERMINATOR_LOG_DIR")
        unsetenv("TERMINATOR_WINDOW_GROUPING")
        unsetenv("TERMINATOR_DEFAULT_FOCUS_ON_ACTION")
        unsetenv("TERMINATOR_SIGINT_WAIT_SECONDS")
        unsetenv("TERMINATOR_SIGTERM_WAIT_SECONDS")
        unsetenv("TERMINATOR_DEFAULT_FOCUS_ON_KILL")
        unsetenv("TERMINATOR_FOREGROUND_COMPLETION_SECONDS")
        unsetenv("TERMINATOR_BACKGROUND_STARTUP_SECONDS")
        unsetenv("TERMINATOR_PRE_KILL_SCRIPT_PATH")
        unsetenv("TERMINATOR_REUSE_BUSY_SESSIONS")
        unsetenv("TERMINATOR_ITERM_PROFILE_NAME")
    }
}
