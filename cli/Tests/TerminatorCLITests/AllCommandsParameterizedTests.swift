import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("All Commands Parameterized Tests", .timeLimit(.minutes(1)))
struct AllCommandsParameterizedTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Command Missing Arguments Tests

    struct MissingArgumentTestCase: CustomTestStringConvertible, Sendable {
        let command: String
        let baseArgs: [String]
        let expectedError: String
        let tags: [Tag]

        var testDescription: String {
            "Command '\(command)' with args: \(baseArgs.joined(separator: " "))"
        }
    }

    @Test(
        "Missing required arguments across commands",
        arguments: [
            MissingArgumentTestCase(
                command: "exec",
                baseArgs: [],
                expectedError: "missing expected argument '<tag>'",
                tags: [.exec]
            ),
            MissingArgumentTestCase(
                command: "read",
                baseArgs: [],
                expectedError: "missing expected argument '--tag <tag>'",
                tags: [.read]
            ),
            MissingArgumentTestCase(
                command: "focus",
                baseArgs: [],
                expectedError: "missing expected argument '--tag <tag>'",
                tags: [.focus]
            ),
            MissingArgumentTestCase(
                command: "kill",
                baseArgs: ["--focus-on-kill", "false"],
                expectedError: "missing expected argument '--tag <tag>'",
                tags: [.kill]
            ),
            MissingArgumentTestCase(
                command: "kill",
                baseArgs: ["--tag", "someTag"],
                expectedError: "missing expected argument '--focus-on-kill <focus-on-kill>'",
                tags: [.kill]
            )
        ]
    )
    func missingRequiredArguments(_ testCase: MissingArgumentTestCase) throws {
        var args = [testCase.command]
        args.append(contentsOf: testCase.baseArgs)

        try TestUtilities.assertCommand(
            CommandTestCase(
                arguments: args,
                expectedExitCode: ExitCode(ErrorCodes.improperUsage),
                errorShouldContain: [testCase.expectedError]
            )
        )
    }

    // MARK: - Common Parameter Tests Across Commands

    struct CommandWithTagTestCase: CustomTestStringConvertible, Sendable {
        let command: String
        let tag: String
        let projectPath: String?
        let additionalArgs: [String]
        let expectedErrors: [String]

        var testDescription: String {
            "\(command) with tag '\(tag)'" + (projectPath.map { " and project '\($0)'" } ?? "")
        }
    }

    @Test(
        "Commands with tag and optional project path",
        arguments: [
            CommandWithTagTestCase(
                command: "read",
                tag: "readTag789",
                projectPath: nil,
                additionalArgs: [],
                expectedErrors: ["Error reading session output for tag \"readTag789\""]
            ),
            CommandWithTagTestCase(
                command: "read",
                tag: "projectReadTag101",
                projectPath: "/Users/test/projectY",
                additionalArgs: [],
                expectedErrors: [
                    "Error reading session output for tag \"projectReadTag101\" in project \"/Users/test/projectY\""
                ]
            ),
            CommandWithTagTestCase(
                command: "focus",
                tag: "testTag123",
                projectPath: nil,
                additionalArgs: [],
                expectedErrors: ["Error focusing session with tag \"testTag123\""]
            ),
            CommandWithTagTestCase(
                command: "focus",
                tag: "projectTag456",
                projectPath: "/Users/test/projectX",
                additionalArgs: [],
                expectedErrors: [
                    "Error focusing session with tag \"projectTag456\" for project \"/Users/test/projectX\""
                ]
            ),
            CommandWithTagTestCase(
                command: "kill",
                tag: "killTag123",
                projectPath: nil,
                additionalArgs: ["--focus-on-kill", "false"],
                expectedErrors: [
                    "not found for kill",
                    "Error: AppleScript failed during kill operation.",
                    "Failed to kill session process."
                ]
            )
        ]
    )
    func commandsWithTag(_ testCase: CommandWithTagTestCase) throws {
        var args = [testCase.command, "--tag", testCase.tag]

        if let projectPath = testCase.projectPath {
            args.append(contentsOf: ["--project-path", projectPath])
        }

        args.append(contentsOf: testCase.additionalArgs)

        try TestUtilities.assertActionFails(
            arguments: args,
            expectedErrors: testCase.expectedErrors
        )
    }

    // MARK: - Configuration Error Tests

    struct ConfigurationErrorTestCase: CustomTestStringConvertible, Sendable {
        let envVar: String
        let value: String
        let command: String
        let expectedError: String

        var testDescription: String {
            "\(envVar)=\(value) for \(command) command"
        }
    }

    @Test(
        "Configuration errors across commands",
        arguments: [
            ConfigurationErrorTestCase(
                envVar: "TERMINATOR_APP",
                value: "UnknownApp123",
                command: "info",
                expectedError: "Unknown terminal application: UnknownApp123"
            ),
            ConfigurationErrorTestCase(
                envVar: "TERMINATOR_APP",
                value: "Ghosty",
                command: "info",
                expectedError: "Configuration Error: TERMINATOR_APP is set to Ghosty"
            )
        ]
    )
    func configurationErrors(_ testCase: ConfigurationErrorTestCase) throws {
        var env = EnvironmentSetup()
        env.set(testCase.envVar, testCase.value)
        defer { env.restore() }

        let args = testCase.command == "info" ? ["info", "--json"] : [testCase.command]
        let result = try TestUtilities.runCommand(arguments: args)

        #expect(result.exitCode == ExitCode(ErrorCodes.configurationError))

        if testCase.command == "info" && args.contains("--json") {
            // For JSON output, parse and check the error field
            if let jsonData = result.output.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let error = json["error"] as? String {
                #expect(error.contains(testCase.expectedError))
            } else {
                #expect(result.errorOutput.contains(testCase.expectedError))
            }
        } else {
            #expect(result.errorOutput.contains(testCase.expectedError))
        }
    }
}

// Test tags are defined in TestTags.swift
