import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Exec Command Tests", .tags(.exec))
struct ExecCommandTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Nested Suite for Basic Validation

    @Suite("Basic Validation", .timeLimit(.minutes(1)))
    struct BasicValidation {
        @Test(
            "Missing required arguments",
            arguments: [
                CommandTestCase(
                    arguments: ["execute"],
                    expectedExitCode: ExitCode(ErrorCodes.improperUsage),
                    errorShouldContain: ["missing expected argument '<tag>'"]
                ),
                CommandTestCase(
                    arguments: ["execute", "tag", "--project-path"],
                    expectedExitCode: ExitCode(ErrorCodes.improperUsage),
                    errorShouldContain: ["missing expected argument"]
                )
            ]
        )
        func missingRequiredArguments(_ testCase: CommandTestCase) throws {
            try TestUtilities.assertCommand(testCase)
        }

        @Test(
            "Session preparation scenarios",
            arguments: [
                ("execTagNoCommand", nil, "Prepare session without command"),
                ("execTagEmptyCommand", "", "Empty command string")
            ]
        )
        func sessionPreparation(tag: String, command: String?, description _: String) throws {
            var args = ["execute", tag]
            if let command {
                args.append(contentsOf: ["--command", command])
            }

            try TestUtilities.assertActionFails(arguments: args)
        }
    }

    // MARK: - Nested Suite for Parameter Validation

    @Suite("Parameter Validation", .tags(.parameters), .timeLimit(.minutes(1)))
    struct ParameterValidation {
        @Test(
            "Lines parameter validation",
            arguments: [
                ParameterTestCase<Int>(input: "50", expectedValue: 50),
                ParameterTestCase<Int>(input: "0", expectedValue: 0),
                ParameterTestCase<Int>(input: "50.5", expectedValue: 50), // Should be floored
                ParameterTestCase<Int>(input: "-10", shouldSucceed: false, errorKeyword: "lines"),
                ParameterTestCase<Int>(input: "notanumber", shouldSucceed: false, errorKeyword: "lines")
            ]
        )
        func linesParameter(_ testCase: ParameterTestCase<Int>) throws {
            let result = try TestUtilities.runCommand(arguments: ["execute", "testTag", "--lines", testCase.input])

            if testCase.shouldSucceed {
                #expect(!result.errorOutput.contains("Invalid value for '--lines'"))
            } else {
                #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
                if let errorKeyword = testCase.errorKeyword {
                    #expect(result.errorOutput.contains(errorKeyword))
                }
            }
        }

        @Test(
            "Timeout parameter validation",
            arguments: [
                ParameterTestCase<Int>(input: "60", expectedValue: 60),
                ParameterTestCase<Int>(input: "1", expectedValue: 1),
                ParameterTestCase<Int>(input: "0", shouldSucceed: false, errorKeyword: "timeout"),
                ParameterTestCase<Int>(input: "-5", shouldSucceed: false, errorKeyword: "timeout"),
                ParameterTestCase<Int>(input: "notanumber", shouldSucceed: false, errorKeyword: "timeout")
            ]
        )
        func timeoutParameter(_ testCase: ParameterTestCase<Int>) throws {
            let result = try TestUtilities.runCommand(arguments: ["execute", "testTag", "--timeout", testCase.input])

            if testCase.shouldSucceed {
                #expect(!result.errorOutput.contains("Invalid value for '--timeout'"))
            } else {
                #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
                if let errorKeyword = testCase.errorKeyword {
                    #expect(result.errorOutput.contains(errorKeyword))
                }
            }
        }

        @Test(
            "Focus mode validation",
            arguments: ["force-focus", "no-focus", "auto-behavior"]
        )
        func validFocusModes(mode: String) throws {
            try TestUtilities.assertActionFails(
                arguments: ["execute", "testTag", "--focus-mode", mode]
            )
        }

        @Test("Invalid focus mode should fail with improper usage")
        func invalidFocusMode() throws {
            try TestUtilities.assertCommand(
                CommandTestCase(
                    arguments: ["execute", "testTag", "--focus-mode", "invalid-mode"],
                    expectedExitCode: ExitCode(ErrorCodes.improperUsage),
                    errorShouldContain: ["Invalid value for '--focus-mode'"]
                )
            )
        }
    }

    // MARK: - Nested Suite for Project Path Handling

    @Suite("Project Path Handling", .tags(.projectPath), .timeLimit(.minutes(1)))
    struct ProjectPathHandling {
        @Test(
            "Project path validation",
            arguments: [
                ("/absolute/path", true, nil),
                ("relative/path", false, "project-path"),
                ("~/home/path", false, "must be an absolute path"),
                ("", false, "project-path")
            ]
        )
        func projectPathValidation(path: String, isValid: Bool, errorKeyword: String?) throws {
            let args = path.isEmpty
                ? ["execute", "testTag"]
                : ["execute", "testTag", "--project-path", path]

            let result = try TestUtilities.runCommand(arguments: args)

            if !isValid {
                #expect(result.exitCode == ExitCode(ErrorCodes.improperUsage))
                if let errorKeyword {
                    #expect(result.errorOutput.contains(errorKeyword))
                }
            }
        }
    }

    // MARK: - Nested Suite for Execution Modes

    @Suite("Execution Modes", .tags(.backgroundExecution), .timeLimit(.minutes(1)))
    struct ExecutionModes {
        @Test("Background execution should fail when action fails")
        func backgroundExecution() throws {
            try TestUtilities.assertActionFails(
                arguments: ["execute", "execTagBackground", "--command", "sleep 5", "--background"]
            )
        }

        @Test("Foreground execution should fail when action fails")
        func foregroundExecution() throws {
            try TestUtilities.assertActionFails(
                arguments: ["execute", "execTagForeground", "--command", "echo hello"]
            )
        }
    }

    // MARK: - Nested Suite for Environment Variables

    @Suite("Environment Variables", .tags(.environment), .timeLimit(.minutes(1)))
    struct EnvironmentVariables {
        @Test("Environment variables should be respected")
        func environmentVariablesRespected() throws {
            var env = EnvironmentSetup()
            env.set("TERMINATOR_DEFAULT_LINES", "200")
            env.set("TERMINATOR_FOREGROUND_COMPLETION_SECONDS", "120")
            defer { env.restore() }

            try TestUtilities.assertActionFails(
                arguments: ["exec", "testTag", "--command", "echo test"]
            )
        }

        @Test("Reuse busy session flag should be accepted")
        func reuseBusySessionFlag() throws {
            try TestUtilities.assertActionFails(
                arguments: ["exec", "testTag", "--reuse-busy-session"],
                expectedErrors: ["Error executing command:", "session not found"]
            )
        }
    }
}

// Test tags are defined in TestTags.swift
