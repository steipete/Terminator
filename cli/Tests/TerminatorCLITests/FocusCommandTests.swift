import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class FocusCommandTests: BaseTerminatorTests {
    func testFocusCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "testTag123"
        let result = try runCommand(arguments: ["focus", "--tag", tagValue])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Focus command should fail when underlying action fails in test."
        )
        // Check for an error message on stderr (FocusCommand should report failure for the tag)
        XCTAssertTrue(
            result.errorOutput.contains("Error focusing session with tag \"\(tagValue)\""),
            "Stderr should contain focus error message for tag. Got: \(result.errorOutput)"
        )
    }

    func testFocusCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectTag456"
        let projectPath = "/Users/test/projectX"
        let result = try runCommand(arguments: ["focus", "--tag", tagValue, "--project-path", projectPath])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Focus command with tag and project path should fail when action fails."
        )
        XCTAssertTrue(
            result.errorOutput
                .contains("Error focusing session with tag \"\(tagValue)\" for project \"\(projectPath)\""),
            "Stderr should contain focus error message for tag with project context. Got: \(result.errorOutput)"
        )
    }

    func testFocusCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["focus"])
        // ArgumentParser should catch missing required argument '--tag'
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.improperUsage),
            "Focus command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)"
        )
        XCTAssertTrue(
            result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"),
            "Stderr should indicate missing --tag argument. Got: \(result.errorOutput)"
        )
    }
}
