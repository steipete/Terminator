import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class ExecCommandGroupingTests: BaseTerminatorTests {
    // MARK: - Project Grouping Tests

    func testExecCommand_WithProjectGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagProjectGroup"
        let projectPath = "/some/test/project_path"
        let commandToRun = "echo hello"
        // Since TERMINATOR_WINDOW_GROUPING is set, --grouping CLI arg is not needed for this test's purpose
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with project grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for command execution failure with project grouping. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithProjectGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagProjectGroupNoFocus"
        let projectPath = "/some/test/project_path_nf"
        let commandToRun = "echo hello project no_focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun,
            "--focus-mode",
            "no-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with project grouping and no-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithProjectGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagProjectGroupForceFocus"
        let projectPath = "/some/test/project_path_ff"
        let commandToRun = "echo hello project focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun,
            "--focus-mode",
            "force-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with project grouping and force-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithProjectGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagProjectGroupAutoBehavior"
        let projectPath = "/some/test/project_path_ab"
        let commandToRun = "echo hello project auto_behavior"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun,
            "--focus-mode",
            "auto-behavior"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with project grouping and auto-behavior should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    // MARK: - Smart Grouping Tests

    func testExecCommand_WithSmartGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagSmartGroup"
        // project-path is not strictly necessary for smart grouping but can be provided
        let commandToRun = "echo hello smart"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with smart grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for command execution failure with smart grouping. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithSmartGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagSmartGroupForceFocus"
        let commandToRun = "echo hello smart force_focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "force-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with smart grouping and force-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithSmartGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagSmartGroupNoFocus"
        let commandToRun = "echo hello smart no_focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "no-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with smart grouping and no-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithSmartGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagSmartGroupAutoBehavior"
        let commandToRun = "echo hello smart auto_behavior"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "auto-behavior"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with smart grouping and auto-behavior should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    // MARK: - Off Grouping Tests

    func testExecCommand_WithOffGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagOffGroup"
        let commandToRun = "echo hello off"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with 'off' grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for command execution failure with 'off' grouping. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithOffGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagOffGroupNoFocus"
        let commandToRun = "echo hello off no_focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "no-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with off grouping and no-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithOffGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagOffGroupForceFocus"
        let commandToRun = "echo hello off force_focus"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "force-focus"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with off grouping and force-focus should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_WithOffGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagOffGroupAutoBehavior"
        let commandToRun = "echo hello off auto_behavior"
        let result = try runCommand(arguments: [
            "exec",
            tagValue,
            "--command",
            commandToRun,
            "--focus-mode",
            "auto-behavior"
        ])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with off grouping and auto-behavior should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }
}
