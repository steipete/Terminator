import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("List Command Tests", .tags(.list), .serialized)
struct ListCommandTests {
    // MARK: - Test Support Types

    struct TestAnyCodable: Codable {
        let value: Any

        init(_ value: Any) {
            self.value = value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = NSNull()
            } else if let bool = try? container.decode(Bool.self) {
                value = bool
            } else if let int = try? container.decode(Int.self) {
                value = int
            } else if let double = try? container.decode(Double.self) {
                value = double
            } else if let string = try? container.decode(String.self) {
                value = string
            } else if let array = try? container.decode([TestAnyCodable].self) {
                value = array.map(\.value)
            } else if let dictionary = try? container.decode([String: TestAnyCodable].self) {
                value = dictionary.mapValues { $0.value }
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "AnyCodable value cannot be decoded"
                )
            }
        }

        func encode(to _: Encoder) throws {
            fatalError("Encoding not needed for tests")
        }
    }

    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Tests

    @Test("Default output with no sessions should show empty message")
    func defaultOutputNoSessions() throws {
        let result = try TestUtilities.runCommand(arguments: ["sessions"])

        #expect(result.exitCode == ExitCode.success)
        #expect(result.output.contains("No active sessions found."))
        #expect(
            result.errorOutput.contains("Warning:") ||
                result.errorOutput.isEmpty ||
                result.errorOutput.contains("Logger shutting down")
        )
    }

    @Test("JSON output with no sessions should return empty array", .tags(.json))
    func jsonOutputNoSessions() throws {
        let result = try TestUtilities.runCommand(arguments: ["sessions", "--json"])

        #expect(result.exitCode == ExitCode.success)

        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            Issue.record("Unexpected stderr for list --json: \(result.errorOutput)")
        }

        #expect(!result.errorOutput.contains("Warning: Failed to list active sessions"))

        let jsonData = try #require(result.output.data(using: .utf8))
        let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)

        #expect(decodedOutput.isEmpty)
    }

    @Test("JSON output with tag filter and no sessions should return empty array", .tags(.json, .filtering))
    func jsonOutputWithTagNoSessions() throws {
        let result = try TestUtilities.runCommand(arguments: ["sessions", "--json", "--tag", "myTestTag"])

        #expect(result.exitCode == ExitCode.success)

        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            Issue.record("Unexpected stderr for list --json --tag: \(result.errorOutput)")
        }

        #expect(!result.errorOutput.contains("Warning: Failed to list active sessions"))

        let jsonData = try #require(result.output.data(using: .utf8))
        let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)

        #expect(decodedOutput.isEmpty)
    }

    // Note: Testing ListCommand with actual sessions would require mocking AppleScriptBridge
    // or having a controlled terminal environment.
}

// Test tags are defined in TestTags.swift
