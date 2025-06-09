import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Read Command Tests", .tags(.read))
struct ReadCommandTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    @Test("Read with tag should fail when action fails")
    func withTagActionFails() throws {
        let tagValue = "readTag789"
        let result = try TestUtilities.runCommand(arguments: ["read", "--tag", tagValue])

        #expect(result.exitCode != ExitCode.success)
        #expect(result.errorOutput.contains("Error reading session output for tag \"\(tagValue)\""))
    }

    @Test("Read with tag and project path should fail when action fails", .tags(.projectPath))
    func withTagAndProjectPathActionFails() throws {
        let tagValue = "projectReadTag101"
        let projectPath = "/Users/test/projectY"
        let result = try TestUtilities.runCommand(arguments: ["read", "--tag", tagValue, "--project-path", projectPath])

        #expect(result.exitCode != ExitCode.success)
        #expect(result.errorOutput
            .contains("Error reading session output for tag \"\(tagValue)\" in project \"\(projectPath)\"")
        )
    }

    @Test("Missing tag argument should fail with improper usage", .tags(.parameters))
    func missingTag() throws {
        let result = try TestUtilities.runCommand(arguments: ["read"])

        #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
        #expect(result.errorOutput.lowercased().contains("error: missing expected argument '--tag <tag>'"))
    }
}

// Test tags are defined in TestTags.swift
