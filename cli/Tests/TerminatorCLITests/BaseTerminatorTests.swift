import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

/// Base utilities for Terminator CLI tests
enum TestUtilities {
    /// Runs the Terminator CLI executable with given arguments and returns output.
    static func runCommand(arguments: [String]) throws -> (output: String, errorOutput: String, exitCode: ExitCode) {
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
    static var productsDirectory: URL {
        #if os(macOS)
            // For Swift Testing, we need to find the build directory
            // First check if we're in SPM test context
            if let testBundle = Bundle.allBundles.first(where: { $0.bundlePath.hasSuffix(".xctest") }) {
                return testBundle.bundleURL.deletingLastPathComponent()
            }

            // Fallback: Look for the executable relative to the current directory
            let fileManager = FileManager.default
            let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

            // Check common SPM build paths
            let possiblePaths = [
                currentDir.appendingPathComponent(".build/debug"),
                currentDir.appendingPathComponent(".build/release"),
                currentDir.appendingPathComponent("../.build/debug"),
                currentDir.appendingPathComponent("../.build/release")
            ]

            for path in possiblePaths {
                let execPath = path.appendingPathComponent("terminator")
                if fileManager.fileExists(atPath: execPath.path) {
                    return path
                }
            }

            fatalError("couldn't find the products directory. Current directory: \(currentDir.path)")
        #else
            return Bundle.main.bundleURL
        #endif
    }

    /// Clear all Terminator environment variables before tests
    static func clearEnvironment() {
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

/// Base test suite that provides common setup and utilities
@Suite("Base Terminator Tests")
struct BaseTerminatorTests {
    init() {
        // Clear any environment variables that might interfere with tests
        TestUtilities.clearEnvironment()
    }
}
