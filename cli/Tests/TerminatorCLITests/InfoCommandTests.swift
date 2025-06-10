import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Info Command Tests", .tags(.info), .serialized)
struct InfoCommandTests {
    // MARK: - Test Output Structures

    struct TestInfoOutput: Decodable {
        let version: String
        let configuration: [String: AnyCodable]
        let sessions: [AnyCodable] // Will be array of session objects in real usage
    }

    struct TestErrorOutput: Decodable {
        let version: String
        let error: String
        let activeConfiguration: [String: AnyCodable]?
    }

    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Tests

    @Test("Default output should contain required sections")
    func defaultOutput() throws {
        let result = try TestUtilities.runCommand(arguments: ["info"])

        #expect(result.exitCode == ExitCode.success)
        #expect(result.output.contains("Terminator CLI Version:"))
        #expect(result.output.contains("--- Active Configuration ---"))
        #expect(result.output.contains("TERMINATOR_APP:"))
        #expect(result.output.contains("--- Managed Sessions ---"))
        #expect(
            result.errorOutput.contains("Warning:") ||
                result.errorOutput.isEmpty ||
                result.errorOutput.contains("Logger shutting down")
        )
    }

    @Test("JSON output should contain valid structure")
    func jsonOutput() throws {
        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])

        #expect(result.exitCode == ExitCode.success)

        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            Issue.record("Unexpected stderr for info --json: \(result.errorOutput)")
        }

        let jsonData = try #require(result.output.data(using: .utf8))
        let decodedOutput = try JSONDecoder().decode(TestInfoOutput.self, from: jsonData)

        #expect(!decodedOutput.version.isEmpty)
        #expect(!decodedOutput.configuration.isEmpty)
        #expect(decodedOutput.configuration.keys.contains("TERMINATOR_APP"))
        #expect(decodedOutput.sessions.isEmpty) // No sessions in test context
    }

    @Test("Unknown terminal app should return configuration error", .tags(.configuration))
    func unknownTerminalAppJson() throws {
        setenv("TERMINATOR_APP", "UnknownApp123", 1)
        defer { unsetenv("TERMINATOR_APP") }

        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])

        #expect(result.exitCode == ExitCode(ErrorCodes.configurationError))

        let jsonData = try #require(result.output.data(using: .utf8))
        let decodedOutput = try JSONDecoder().decode(TestErrorOutput.self, from: jsonData)

        #expect(!decodedOutput.version.isEmpty)
        #expect(decodedOutput.error.contains("Unknown terminal application: UnknownApp123"))
        #expect(decodedOutput.activeConfiguration != nil)
        #expect(decodedOutput.activeConfiguration?["TERMINATOR_APP"]?.stringValue == "UnknownApp123")
    }

    @Test("Ghosty validation failure should exit with configuration error", .tags(.configuration, .ghosty))
    func ghostyValidationFailure() throws {
        // This test assumes Ghosty is NOT installed or will fail AppleScript validation
        setenv("TERMINATOR_APP", "Ghosty", 1)
        setenv("TERMINATOR_LOG_LEVEL", "error", 1) // Allow error logs to see validation message
        defer {
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_LOG_LEVEL")
        }

        let result = try TestUtilities.runCommand(arguments: ["info"])

        #expect(result.exitCode == ExitCode(ErrorCodes.configurationError))
        #expect(result.errorOutput.contains("Configuration Error: TERMINATOR_APP is set to Ghosty"))
    }
}

// Test tags are defined in TestTags.swift
