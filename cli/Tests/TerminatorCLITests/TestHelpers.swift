import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

// MARK: - Common Test Data Structures

struct CommandTestCase: CustomTestStringConvertible, Sendable {
    let arguments: [String]
    let expectedExitCode: ExitCode
    let errorShouldContain: [String]
    let errorShouldNotContain: [String]

    init(
        arguments: [String],
        expectedExitCode: ExitCode,
        errorShouldContain: [String] = [],
        errorShouldNotContain: [String] = []
    ) {
        self.arguments = arguments
        self.expectedExitCode = expectedExitCode
        self.errorShouldContain = errorShouldContain
        self.errorShouldNotContain = errorShouldNotContain
    }

    var testDescription: String {
        "Command: \(arguments.joined(separator: " "))"
    }
}

struct ParameterTestCase<T: Equatable & Sendable>: CustomTestStringConvertible, Sendable {
    let input: String
    let expectedValue: T?
    let shouldSucceed: Bool
    let errorKeyword: String?

    init(input: String, expectedValue: T? = nil, shouldSucceed: Bool = true, errorKeyword: String? = nil) {
        self.input = input
        self.expectedValue = expectedValue
        self.shouldSucceed = shouldSucceed
        self.errorKeyword = errorKeyword
    }

    var testDescription: String {
        "Input '\(input)' -> \(shouldSucceed ? "Valid" : "Invalid")"
    }
}

// MARK: - Test Assertions

extension TestUtilities {
    /// Runs a command and validates the result against expected outcomes
    static func assertCommand(
        _ testCase: CommandTestCase,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let result = try runCommand(arguments: testCase.arguments)

        #expect(
            result.exitCode == testCase.expectedExitCode,
            "Expected exit code \(testCase.expectedExitCode.rawValue), got \(result.exitCode.rawValue)",
            sourceLocation: sourceLocation
        )

        for expectedError in testCase.errorShouldContain {
            #expect(
                result.errorOutput.contains(expectedError),
                "Error output should contain '\(expectedError)'. Got: \(result.errorOutput)",
                sourceLocation: sourceLocation
            )
        }

        for unexpectedError in testCase.errorShouldNotContain {
            #expect(
                !result.errorOutput.contains(unexpectedError),
                "Error output should NOT contain '\(unexpectedError)'. Got: \(result.errorOutput)",
                sourceLocation: sourceLocation
            )
        }
    }

    /// Common assertion for "action fails" scenarios
    static func assertActionFails(
        arguments: [String],
        expectedErrors: [String] = ["Error executing command:", "session not found"],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let result = try runCommand(arguments: arguments)

        #expect(result.exitCode != ExitCode.success, sourceLocation: sourceLocation)

        let containsExpectedError = expectedErrors.contains { error in
            result.errorOutput.contains(error)
        }

        #expect(
            containsExpectedError,
            "Error output should contain one of: \(expectedErrors). Got: \(result.errorOutput)",
            sourceLocation: sourceLocation
        )
    }
}

// MARK: - Environment Setup Helpers

struct EnvironmentSetup {
    private var originalValues: [String: String?] = [:]

    mutating func set(_ key: String, _ value: String) {
        if originalValues[key] == nil {
            originalValues[key] = getenv(key).flatMap { String(cString: $0) }
        }
        setenv(key, value, 1)
    }

    mutating func unset(_ key: String) {
        if originalValues[key] == nil {
            originalValues[key] = getenv(key).flatMap { String(cString: $0) }
        }
        unsetenv(key)
    }

    func restore() {
        for (key, value) in originalValues {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
}

// MARK: - Custom Test Result Types

struct TestResult: CustomTestStringConvertible {
    let output: String
    let errorOutput: String
    let exitCode: ExitCode

    var testDescription: String {
        """
        Exit Code: \(exitCode.rawValue)
        Output: \(output.isEmpty ? "<empty>" : output.prefix(100) + (output.count > 100 ? "..." : ""))
        Error: \(errorOutput.isEmpty ? "<empty>" : errorOutput.prefix(100) + (errorOutput.count > 100 ? "..." : ""))
        """
    }
}
