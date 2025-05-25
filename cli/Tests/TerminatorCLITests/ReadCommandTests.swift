import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class ReadCommandTests: BaseTerminatorTests {
    func testReadCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "readTag789"
        let result = try runCommand(arguments: ["read", "--tag", tagValue])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Read command should fail when underlying action fails in test."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error reading session output for tag \"\(tagValue)\""),
            "Stderr should contain read error message for tag. Got: \(result.errorOutput)"
        )
    }

    func testReadCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectReadTag101"
        let projectPath = "/Users/test/projectY"
        let result = try runCommand(arguments: ["read", "--tag", tagValue, "--project-path", projectPath])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Read command with tag and project path should fail when action fails."
        )
        XCTAssertTrue(
            result.errorOutput
                .contains("Error reading session output for tag \"\(tagValue)\" in project \"\(projectPath)\""),
            "Stderr should contain read error message for tag with project context. Got: \(result.errorOutput)"
        )
    }

    func testReadCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["read"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode(ErrorCodes.improperUsage),
            "Read command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)"
        )
        XCTAssertTrue(
            result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"),
            "Stderr should indicate missing --tag argument. Got: \(result.errorOutput)"
        )
    }
}
