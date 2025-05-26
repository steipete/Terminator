import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class ExecCommandITermTests: BaseTerminatorTests {
    // MARK: - iTerm Grouping Tests

    func testExecCommand_ITerm_WithProjectGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermProjectGroup"
        let projectPath = "/some/test/iterm_project_path"
        let commandToRun = "echo hello iTerm project"
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
            "Exec command with iTerm, project grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for iTerm, project grouping. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithSmartGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermSmartGroup"
        let commandToRun = "echo hello iTerm smart"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with iTerm, smart grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for iTerm, smart grouping. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithOffGrouping_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermOffGroup"
        let commandToRun = "echo hello iTerm off"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(
            result.exitCode,
            ExitCode.success,
            "Exec command with iTerm, off grouping should fail when underlying action fails."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message for iTerm, off grouping. Got: \(result.errorOutput)"
        )
    }

    // MARK: - iTerm Focus Mode Tests

    func testExecCommand_ITerm_WithProjectGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermProjectGroupForceFocus"
        let projectPath = "/some/test/iterm_project_path_ff"
        let commandToRun = "echo hello iTerm project force_focus"
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
            "Exec command with iTerm, project grouping, force-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithProjectGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermProjectGroupNoFocus"
        let projectPath = "/some/test/iterm_project_path_nf"
        let commandToRun = "echo hello iTerm project no_focus"
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
            "Exec command with iTerm, project grouping, no-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithProjectGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermProjectGroupAutoBehavior"
        let projectPath = "/some/test/iterm_project_path_ab"
        let commandToRun = "echo hello iTerm project auto_behavior"
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
            "Exec command with iTerm, project grouping, auto-behavior should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithSmartGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermSmartGroupForceFocus"
        let commandToRun = "echo hello iTerm smart force_focus"
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
            "Exec command with iTerm, smart grouping, force-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithSmartGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermSmartGroupNoFocus"
        let commandToRun = "echo hello iTerm smart no_focus"
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
            "Exec command with iTerm, smart grouping, no-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithSmartGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermSmartGroupAutoBehavior"
        let commandToRun = "echo hello iTerm smart auto_behavior"
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
            "Exec command with iTerm, smart grouping, auto-behavior should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithOffGrouping_FocusForce_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermOffGroupForceFocus"
        let commandToRun = "echo hello iTerm off force_focus"
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
            "Exec command with iTerm, off grouping, force-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithOffGrouping_FocusNo_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermOffGroupNoFocus"
        let commandToRun = "echo hello iTerm off no_focus"
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
            "Exec command with iTerm, off grouping, no-focus should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }

    func testExecCommand_ITerm_WithOffGrouping_FocusAuto_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer {
            unsetenv("TERMINATOR_LOG_LEVEL")
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_WINDOW_GROUPING")
        }

        let tagValue = "execTagITermOffGroupAutoBehavior"
        let commandToRun = "echo hello iTerm off auto_behavior"
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
            "Exec command with iTerm, off grouping, auto-behavior should fail."
        )
        XCTAssertTrue(
            result.errorOutput.contains("Error executing command:") || result.errorOutput
                .contains("session not found"),
            "Stderr should contain a relevant error message. Got: \(result.errorOutput)"
        )
    }
}
