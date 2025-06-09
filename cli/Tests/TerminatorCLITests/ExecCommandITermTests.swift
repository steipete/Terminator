import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Exec Command iTerm Tests", .tags(.exec, .iTerm))
struct ExecCommandITermTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        setenv("TERMINATOR_APP", "iTerm", 1)
    }

    deinit {
        unsetenv("TERMINATOR_LOG_LEVEL")
        unsetenv("TERMINATOR_APP")
    }

    // MARK: - iTerm Grouping Tests

    @Test("iTerm with project grouping should fail when action fails", .tags(.grouping))
    func iTermWithProjectGroupingActionFails() throws {
        setenv("TERMINATOR_WINDOW_GROUPING", "project", 1)
        defer { unsetenv("TERMINATOR_WINDOW_GROUPING") }

        let tagValue = "execTagITermProjectGroup"
        let projectPath = "/some/test/iterm_project_path"
        let commandToRun = "echo hello iTerm project"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }

    @Test("iTerm with smart grouping should fail when action fails", .tags(.grouping))
    func iTermWithSmartGroupingActionFails() throws {
        setenv("TERMINATOR_WINDOW_GROUPING", "smart", 1)
        defer { unsetenv("TERMINATOR_WINDOW_GROUPING") }

        let tagValue = "execTagITermSmartGroup"
        let projectPath = "/some/test/iterm_smart_path"
        let commandToRun = "echo hello iTerm smart"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }

    @Test("iTerm with grouping off should fail when action fails", .tags(.grouping))
    func iTermWithGroupingOffActionFails() throws {
        setenv("TERMINATOR_WINDOW_GROUPING", "off", 1)
        defer { unsetenv("TERMINATOR_WINDOW_GROUPING") }

        let tagValue = "execTagITermGroupOff"
        let projectPath = "/some/test/iterm_off_path"
        let commandToRun = "echo hello iTerm off"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }

    // MARK: - iTerm Focus Mode Tests

    @Test("iTerm with no focus mode should fail when action fails")
    func iTermNoFocusActionFails() throws {
        let tagValue = "execTagITermNoFocus"
        let projectPath = "/some/test/iterm_nofocus_path"
        let commandToRun = "echo no focus"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun,
            "--focus-mode",
            "no-focus"
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }

    @Test("iTerm with force focus mode should fail when action fails")
    func iTermForceFocusActionFails() throws {
        let tagValue = "execTagITermForceFocus"
        let projectPath = "/some/test/iterm_forcefocus_path"
        let commandToRun = "echo force focus"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun,
            "--focus-mode",
            "force-focus"
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }

    // MARK: - iTerm Profile Tests

    @Test("iTerm with profile name should fail when action fails", .tags(.configuration))
    func iTermWithProfileNameActionFails() throws {
        setenv("TERMINATOR_ITERM_PROFILE_NAME", "MyTestProfile", 1)
        defer { unsetenv("TERMINATOR_ITERM_PROFILE_NAME") }

        let tagValue = "execTagITermProfile"
        let projectPath = "/some/test/iterm_profile_path"
        let commandToRun = "echo profile test"

        let result = try TestUtilities.runCommand(arguments: [
            "execute",
            tagValue,
            "--project-path",
            projectPath,
            "--command",
            commandToRun
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("Error executing command:") ||
                result.errorOutput.contains("session not found")
        )
    }
}

// Test tags are defined in TestTags.swift
