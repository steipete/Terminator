import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class InfoCommandTests: BaseTerminatorTests {
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

    // MARK: - Tests

    func testInfoCommand_DefaultOutput() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }
        let result = try runCommand(arguments: ["info"])

        XCTAssertEqual(result.exitCode, ExitCode.success)
        XCTAssertTrue(result.output.contains("Terminator CLI Version:"))
        XCTAssertTrue(result.output.contains("--- Active Configuration ---"))
        XCTAssertTrue(result.output.contains("TERMINATOR_APP:"))
        XCTAssertTrue(result.output.contains("--- Managed Sessions ---"))
        XCTAssertTrue(
            result.errorOutput.contains("Warning: Failed to list active sessions"),
            "Stderr should contain session listing warning."
        )
    }

    func testInfoCommand_JsonOutput() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }
        let result = try runCommand(arguments: ["info", "--json"])

        XCTAssertEqual(
            result.exitCode,
            ExitCode.success,
            "Info --json should exit with success. Actual: \(result.exitCode.rawValue)"
        )

        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            print("Unexpected stderr for testInfoCommand_JsonOutput was not empty:\n---\n\(result.errorOutput)---")
        }

        guard let jsonData = result.output.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.output)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode(TestInfoOutput.self, from: jsonData)

            XCTAssertFalse(decodedOutput.version.isEmpty, "JSON output should contain a non-empty version string.")
            XCTAssertFalse(decodedOutput.configuration.isEmpty, "JSON output should contain non-empty configuration.")

            let configContainsTerminatorApp = decodedOutput.configuration.keys.contains("TERMINATOR_APP")
            XCTAssertTrue(configContainsTerminatorApp, "Active configuration should include TERMINATOR_APP")

            XCTAssertNotNil(decodedOutput.sessions, "JSON output should contain sessions array (even if empty).")
            XCTAssertTrue(decodedOutput.sessions.isEmpty, "Sessions array should be empty in this test context.")

        } catch {
            XCTFail(
                "Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.output)\nstderr:\n\(result.errorOutput)"
            )
        }
    }

    func testInfoCommand_UnknownTerminalApp_Json() throws {
        // Temporarily set an unknown terminal app via environment variable
        setenv("TERMINATOR_APP", "UnknownApp123", 1)
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer {
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_LOG_LEVEL")
        }

        let result = try runCommand(arguments: ["info", "--json"])

        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.configurationError),
            "Info with unknown app should lead to configurationError (2). Actual: \(result.exitCode.rawValue)"
        )

        // If the above passes, then try decoding.
        guard let jsonData = result.output.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data for unknown app test. stdout: \(result.output)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode(TestErrorOutput.self, from: jsonData)
            // If we get here, decoding was successful.
            XCTAssertEqual(decodedOutput.version, "0.9.0", "Version mismatch in error JSON")
            XCTAssertTrue(
                decodedOutput.error.contains("Unknown terminal application: UnknownApp123"),
                "Error message mismatch in error JSON. Got: \(decodedOutput.error)"
            )
            XCTAssertNotNil(
                decodedOutput.activeConfiguration,
                "JSON output for unknown app should contain activeConfiguration."
            )
            XCTAssertEqual(
                decodedOutput.activeConfiguration?["TERMINATOR_APP"]?.stringValue,
                "UnknownApp123",
                "TERMINATOR_APP in JSON should match the unknown app"
            )
        } catch {
            XCTFail(
                "Error decoding JSON output for unknown app test: \(error.localizedDescription). stdout:\n\(result.output)"
            )
        }
    }

    // Test for Ghosty validation failure (SDD 3.2.3)
    func testGhostyValidationFailure_ExitCode() throws {
        // This test assumes Ghosty is NOT installed or will fail AppleScript validation.
        // We set TERMINATOR_APP to Ghosty and expect a specific exit code.
        setenv("TERMINATOR_APP", "Ghosty", 1)
        // Allow error logs for this test to see the fputs from AppConfig
        setenv("TERMINATOR_LOG_LEVEL", "error", 1)
        defer {
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_LOG_LEVEL")
        }

        let result = try runCommand(arguments: ["info"]) // Any command would trigger validate()

        // As per TerminatorCLI.validate(), this should be ErrorCodes.configurationError (2)
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.configurationError),
            "Expected configurationError (2) due to Ghosty validation failure."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Configuration Error: TERMINATOR_APP is set to Ghosty"),
            "Stderr should contain Ghosty validation error message."
        )
    }
}
