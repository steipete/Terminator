import ArgumentParser
@testable import TerminatorCLI
import XCTest

final class ListCommandTests: BaseTerminatorTests {
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

    // MARK: - Tests

    func testListCommand_DefaultOutput_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list"])

        XCTAssertEqual(result.exitCode, ExitCode.success)
        XCTAssertTrue(result.output.contains("No active sessions found."))
        // Expect a warning on stderr because session listing will fail in test env
        XCTAssertTrue(
            result.errorOutput.contains("Warning:") ||
                result.errorOutput.isEmpty ||
                result.errorOutput.contains("Logger shutting down"),
            "Stderr should contain warning, be empty, or just have logger messages. Got: \(result.errorOutput)"
        )
    }

    func testListCommand_JsonOutput_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list", "--json"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode.success,
            "list --json should exit with success. Actual: \(result.exitCode.rawValue)"
        )

        // Stderr should be clean of app-level warnings in JSON mode for session listing
        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            print(
                "Unexpected stderr for testListCommand_JsonOutput_NoSessions was not empty:\n---\n\(result.errorOutput)---"
            )
        }
        XCTAssertFalse(
            result.errorOutput.contains("Warning: Failed to list active sessions"),
            "Stderr should NOT contain session listing warning in JSON mode."
        )

        guard let jsonData = result.output.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.output)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)
            XCTAssertTrue(decodedOutput.isEmpty, "JSON output should be an empty array when no sessions are found.")
        } catch {
            XCTFail("Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.output)")
        }
    }

    func testListCommand_JsonOutput_WithTag_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list", "--json", "--tag", "myTestTag"])
        XCTAssertEqual(
            result.exitCode,
            ExitCode.success,
            "list --json --tag should exit with success. Actual: \(result.exitCode.rawValue)"
        )

        if !result.errorOutput.isEmpty && !result.errorOutput.contains("Logger shutting down") {
            print(
                "Unexpected stderr for testListCommand_JsonOutput_WithTag_NoSessions was not empty:\n---\n\(result.errorOutput)---"
            )
        }
        XCTAssertFalse(
            result.errorOutput.contains("Warning: Failed to list active sessions"),
            "Stderr should NOT contain session listing warning in JSON mode."
        )

        guard let jsonData = result.output.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.output)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)
            XCTAssertTrue(decodedOutput.isEmpty, "JSON output should be an empty array when no sessions match the tag.")
        } catch {
            XCTFail("Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.output)")
        }
    }

    // Note: Testing ListCommand with actual sessions would require mocking AppleScriptBridge
    // or having a controlled terminal environment.
}
