import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class KillCommandTests: BaseTerminatorTests {
    func testKillCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "killTag123"
        // --focus-on-kill is a required Option, not a Flag
        let result = try runCommand(arguments: ["kill", "--tag", tagValue, "--focus-on-kill", "false"])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Kill command should fail when underlying action fails in test."
        )
        // Expect session not found or a general AppleScript/controller error
        XCTAssertTrue(
            result.errorOutput
                .contains("Error: Session for tag \"\(tagValue)\" in project \"N/A\" not found for kill.") ||
                result.errorOutput.contains("Error: AppleScript failed during kill operation.") ||
                result.errorOutput.contains("Failed to kill session process."),
            "Stderr should contain a relevant kill error message for tag. Got: \(result.errorOutput)"
        )
    }

    func testKillCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectKillTag456"
        let projectPath = "/Users/test/projectZ"
        let result = try runCommand(arguments: [
            "kill",
            "--tag",
            tagValue,
            "--project-path",
            projectPath,
            "--focus-on-kill",
            "false"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Kill command with tag and project path should fail when action fails."
        )
        XCTAssertTrue(
            result.errorOutput
                .contains("Error: Session for tag \"\(tagValue)\" in project \"\(projectPath)\" not found for kill.") ||
                result.errorOutput.contains("Error: AppleScript failed during kill operation.") ||
                result.errorOutput.contains("Failed to kill session process."),
            "Stderr should contain a relevant kill error message for tag with project context. Got: \(result.errorOutput)"
        )
    }

    func testKillCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        // Missing --tag, but --focus-on-kill is present
        let result = try runCommand(arguments: ["kill", "--focus-on-kill", "false"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.improperUsage),
            "Kill command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)"
        )
        XCTAssertTrue(
            result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"),
            "Stderr should indicate missing --tag argument. Got: \(result.errorOutput)"
        )
    }

    func testKillCommand_MissingFocusOnKill() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        // Missing --focus-on-kill, but --tag is present
        let result = try runCommand(arguments: ["kill", "--tag", "someTag"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.improperUsage),
            "Kill command should fail with improperUsage (64) if --focus-on-kill is missing. Got \(result.exitCode.rawValue)"
        )
        XCTAssertTrue(
            result.errorOutput.lowercased()
                .contains("error: missing expected argument '--focus-on-kill <focus-on-kill>'"),
            "Stderr should indicate missing --focus-on-kill argument. Got: \(result.errorOutput)"
        )
    }
}
