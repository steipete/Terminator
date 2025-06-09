import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Focus Command Tests", .tags(.focus))
struct FocusCommandTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    @Test("Focus with tag should fail when action fails")
    func withTagActionFails() throws {
        let tagValue = "testTag123"
        let result = try TestUtilities.runCommand(arguments: ["focus", "--tag", tagValue])

        #expect(result.exitCode != ExitCode.success)
        #expect(result.errorOutput.contains("Error focusing session with tag \"\(tagValue)\""))
    }

    @Test("Focus with tag and project path should fail when action fails", .tags(.projectPath))
    func withTagAndProjectPathActionFails() throws {
        let tagValue = "projectTag456"
        let projectPath = "/Users/test/projectX"
        let result = try TestUtilities.runCommand(arguments: [
            "focus",
            "--tag",
            tagValue,
            "--project-path",
            projectPath
        ])

        #expect(result.exitCode != ExitCode.success)
        #expect(result.errorOutput
            .contains("Error focusing session with tag \"\(tagValue)\" for project \"\(projectPath)\"")
        )
    }

    @Test("Missing tag argument should fail with improper usage", .tags(.parameters))
    func missingTag() throws {
        let result = try TestUtilities.runCommand(arguments: ["focus"])

        #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
        #expect(result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"))
    }
}

// Test tags are defined in TestTags.swift
