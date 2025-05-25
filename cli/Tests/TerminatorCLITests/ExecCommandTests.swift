import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class ExecCommandTests: BaseTerminatorTests {
    // MARK: - Basic Tests

    func testExecCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["exec"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.improperUsage),
            "Exec command should fail with improperUsage (64) if tag is missing. Got \(result.exitCode.rawValue)"
        )
        XCTAssertTrue(
            result.errorOutput.lowercased().contains("error: missing expected argument '<tag>'"),
            "Stderr should indicate missing tag argument. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_PrepareSession_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagNoCommand"
        let result = try runCommand(arguments: ["exec", tagValue]) // No --command, so it's a prepare

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command (prepare session) should fail when underlying action fails."
        )
        // Expect a general error from the controller or session not found
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for prepare session failure. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithCommand_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagWithCommand"
        let commandToRun = "echo hello"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with a command should fail when underlying action fails."
        )
        // Expect a general error from the controller or session not found
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for command execution failure. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_Background_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagBackground"
        let commandToRun = "sleep 5"
        // --background is a Flag, so it doesn't take a value
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun, "--background"])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with --background should still report failure if action fails."
        )
        // Even for background, if the setup/initial dispatch fails (e.g. session not found), it should report an error.
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for background command failure. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_EmptyCommand_IsPrepareSession_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagEmptyCommand"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", ""])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with empty command (prepare session) should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for empty command (prepare) failure. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithTimeout_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagWithTimeout"
        let commandToRun = "echo hello"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun, "--timeout", "1"])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with timeout should fail when underlying action fails."
        )
        // The timeout itself might not be triggered if basic session setup fails first.
        // So we expect either a generic execution error or a session not found error primarily.
        // If a timeout error specific to AppConfig/Controller were to surface directly, the message would be different.
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found") ||
                result.errorOutput.contains("timed out"), // Adding timeout as a possible message part
            "Stderr should contain a relevant error message for command execution failure with timeout. Got: \(result.errorOutput)"
        )
    }
}
