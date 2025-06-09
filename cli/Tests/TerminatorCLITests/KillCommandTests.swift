import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Kill Command Tests", .tags(.kill))
struct KillCommandTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    deinit {
        unsetenv("TERMINATOR_LOG_LEVEL")
    }

    @Test("Kill with tag should fail when action fails")
    func withTagActionFails() throws {
        let tagValue = "killTag123"
        let result = try TestUtilities.runCommand(arguments: ["kill", "--tag", tagValue, "--focus-on-kill", "false"])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("not found for kill") ||
                result.errorOutput.contains("Error: AppleScript failed during kill operation.") ||
                result.errorOutput.contains("Failed to kill session process.")
        )
    }

    @Test("Kill with tag and project path should fail when action fails", .tags(.projectPath))
    func withTagAndProjectPathActionFails() throws {
        let tagValue = "projectKillTag456"
        let projectPath = "/Users/test/projectZ"
        let result = try TestUtilities.runCommand(arguments: [
            "kill",
            "--tag",
            tagValue,
            "--project-path",
            projectPath,
            "--focus-on-kill",
            "false"
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(
            result.errorOutput.contains("not found for kill") ||
                result.errorOutput.contains("Error: AppleScript failed during kill operation.") ||
                result.errorOutput.contains("Failed to kill session process.")
        )
    }

    @Test("Missing tag argument should fail with improper usage", .tags(.parameters))
    func missingTag() throws {
        let result = try TestUtilities.runCommand(arguments: ["kill", "--focus-on-kill", "false"])

        #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
        #expect(result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"))
    }

    @Test("Missing focus-on-kill argument should fail with improper usage", .tags(.parameters))
    func missingFocusOnKill() throws {
        let result = try TestUtilities.runCommand(arguments: ["kill", "--tag", "someTag"])

        #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
        #expect(result.errorOutput.lowercased()
            .contains("error: missing expected argument '--focus-on-kill <focus-on-kill>'")
        )
    }
}

// Test tags are defined in TestTags.swift
