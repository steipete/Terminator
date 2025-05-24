import XCTest
import class Foundation.Bundle
@testable import TerminatorCLI
import ArgumentParser

// Test structs for decoding JSON output
struct TestInfoOutput: Codable {
    let version: String
    let sessions: [TestAnyCodable]
    let configuration: [String: TestAnyCodable]
    
    enum CodingKeys: String, CodingKey {
        case version
        case sessions
        case configuration
    }
}

struct TestErrorOutput: Codable {
    let version: String
    let error: String
    let activeConfiguration: [String: String]
}

// Simplified AnyCodable for testing - handles basic types
struct TestAnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([TestAnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: TestAnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "TestAnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let array as [Any]: try container.encode(array.map { TestAnyCodable(value: $0) })
        case let dictionary as [String: Any]: try container.encode(dictionary.mapValues { TestAnyCodable(value: $0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
    
    init(value: Any) {
        self.value = value
    }
}

final class TerminatorCLITests: XCTestCase {

    // Helper function to execute the CLI and capture output
    func runCommand(arguments: [String]) throws -> (standardOutput: String, standardError: String, exitCode: ExitCode) {
        let pipe = Pipe()
        let errorPipe = Pipe()

        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("terminator")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        
        // ArgumentParser's ExitCode is Int32
        let exitCodeValue = process.terminationStatus
        return (output, errorOutput, ExitCode(exitCodeValue))
    }

    /// Returns path to the built products directory.
    var productsDirectory: URL {
      #if os(macOS)
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("couldn't find the products directory")
      #else
        return Bundle.main.bundleURL
      #endif
    }

    override func setUp() {
        super.setUp()
        // Clear any environment variables that might interfere with tests
        unsetenv("TERMINATOR_APP")
        unsetenv("TERMINATOR_LOG_LEVEL")
        unsetenv("TERMINATOR_LOG_DIR")

        // Configure logger for the test process itself (e.g. if tests directly use Logger)
        // For the spawned CLI process, LOG_LEVEL will be set via environment variables per test.
        let tempLogDir = FileManager.default.temporaryDirectory.appendingPathComponent("TerminatorCLITestsLogs_TestRunner")
        try? FileManager.default.createDirectory(at: tempLogDir, withIntermediateDirectories: true, attributes: nil)
        Logger.configure(level: .none, directory: tempLogDir)
    }

    func testInfoCommand_DefaultOutput() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }
        let result = try runCommand(arguments: ["info"])

        XCTAssertEqual(result.exitCode, ExitCode.success)
        XCTAssertTrue(result.standardOutput.contains("Terminator CLI Version:"))
        XCTAssertTrue(result.standardOutput.contains("--- Active Configuration ---"))
        XCTAssertTrue(result.standardOutput.contains("TERMINATOR_APP:"))
        XCTAssertTrue(result.standardOutput.contains("--- Managed Sessions ---"))
        XCTAssertTrue(result.standardError.contains("Warning: Failed to list active sessions"), "Stderr should contain session listing warning.")
    }

    func testInfoCommand_JsonOutput() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }
        let result = try runCommand(arguments: ["info", "--json"])

        XCTAssertEqual(result.exitCode, ExitCode.success, "Info --json should exit with success. Actual: \(result.exitCode.rawValue)")
        
        if !result.standardError.isEmpty && !result.standardError.contains("Logger shutting down") {
            print("Unexpected stderr for testInfoCommand_JsonOutput was not empty:\n---\n\(result.standardError)---")
        }

        guard let jsonData = result.standardOutput.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.standardOutput)")
            return
        }

        do {
             let decodedOutput = try JSONDecoder().decode(TestInfoOutput.self, from: jsonData)
             
             XCTAssertFalse(decodedOutput.version.isEmpty, "JSON output should contain a non-empty version string.")
             XCTAssertFalse(decodedOutput.configuration.isEmpty, "JSON output should contain non-empty configuration.")
             
             let configContainsTerminatorApp = decodedOutput.configuration.keys.contains("TERMINATOR_APP")
             XCTAssertTrue(configContainsTerminatorApp, "Active configuration should include TERMINATOR_APP")
             
             XCTAssertNotNil(decodedOutput.sessions, "JSON output should contain sessions array (even if empty).")
             XCTAssertTrue(decodedOutput.sessions.isEmpty, "Sessions array should be empty in this test context.")

        } catch {
            XCTFail("Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.standardOutput)\nstderr:\n\(result.standardError)")
        }
    }
    
    func testInfoCommand_UnknownTerminalApp_Json() throws {
        // Temporarily set an unknown terminal app via environment variable
        setenv("TERMINATOR_APP", "UnknownApp123", 1)
        setenv("TERMINATOR_LOG_LEVEL", "none", 1) // Tell CLI process to be quiet
        defer { 
            unsetenv("TERMINATOR_APP") 
            unsetenv("TERMINATOR_LOG_LEVEL")
        }

        let result = try runCommand(arguments: ["info", "--json"])
        
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.configurationError), "Info with unknown app should lead to configurationError (2). Actual: \(result.exitCode.rawValue)")

        if !result.standardError.isEmpty && !result.standardError.contains("Logger shutting down") {
            print("Unexpected stderr for testInfoCommand_UnknownTerminalApp_Json was not empty:\n---\n\(result.standardError)---")
        }

        guard let jsonData = result.standardOutput.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data for unknown app test. stdout: \(result.standardOutput)")
            return
        }
        
        do {
            let decodedOutput = try JSONDecoder().decode(TestErrorOutput.self, from: jsonData)

            XCTAssertEqual(decodedOutput.version, TerminatorCLI.APP_VERSION, "Version mismatch in error JSON")
            XCTAssertTrue(decodedOutput.error.contains("Unknown terminal application: UnknownApp123"), "Error message mismatch in error JSON. Got: \(decodedOutput.error)")
            
            XCTAssertNotNil(decodedOutput.activeConfiguration, "JSON output for unknown app should contain activeConfiguration.")
            // The TestErrorOutput.activeConfiguration is [String: String], so direct access is fine.
            XCTAssertEqual(decodedOutput.activeConfiguration["TERMINATOR_APP"], "UnknownApp123", "TERMINATOR_APP in JSON should match the unknown app")

        } catch {
            XCTFail("Error decoding JSON output for unknown app test: \(error.localizedDescription). stdout:\n\(result.standardOutput)")
        }
    }
    
    // Test for Ghosty validation failure (SDD 3.2.3)
    func testGhostyValidationFailure_ExitCode() throws {
        // This test assumes Ghosty is NOT installed or will fail AppleScript validation.
        // We set TERMINATOR_APP to Ghosty and expect a specific exit code.
        setenv("TERMINATOR_APP", "Ghosty", 1)
        setenv("TERMINATOR_LOG_LEVEL", "error", 1) // Allow error logs for this test to see the fputs from AppConfig
        defer { 
            unsetenv("TERMINATOR_APP")
            unsetenv("TERMINATOR_LOG_LEVEL")
        }

        let result = try runCommand(arguments: ["info"]) // Any command would trigger validate()

        // As per TerminatorCLI.validate(), this should be ErrorCodes.configurationError (2)
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.configurationError), "Expected configurationError (2) due to Ghosty validation failure.")
        XCTAssertTrue(result.standardError.contains("Configuration Error: TERMINATOR_APP is set to Ghosty"), "Stderr should contain Ghosty validation error message.")
    }

    // MARK: - ListCommand Tests

    func testListCommand_DefaultOutput_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list"])

        XCTAssertEqual(result.exitCode, ExitCode.success)
        XCTAssertTrue(result.standardOutput.contains("No active sessions found."))
        // Expect a warning on stderr because session listing will fail in test env
        XCTAssertTrue(result.standardError.contains("Warning: Failed to list active sessions"), "Stderr should contain session listing warning.")
    }

    func testListCommand_JsonOutput_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list", "--json"])
        XCTAssertEqual(result.exitCode, ExitCode.success, "list --json should exit with success. Actual: \(result.exitCode.rawValue)")
        
        // Stderr should be clean of app-level warnings in JSON mode for session listing, but might have logger shutdown.
        if !result.standardError.isEmpty && !result.standardError.contains("Logger shutting down") {
             print("Unexpected stderr for testListCommand_JsonOutput_NoSessions was not empty:\n---\n\(result.standardError)---")
        }
        XCTAssertFalse(result.standardError.contains("Warning: Failed to list active sessions"), "Stderr should NOT contain session listing warning in JSON mode.")

        guard let jsonData = result.standardOutput.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.standardOutput)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)
            XCTAssertTrue(decodedOutput.isEmpty, "JSON output should be an empty array when no sessions are found.")
        } catch {
            XCTFail("Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.standardOutput)")
        }
    }

    func testListCommand_JsonOutput_WithTag_NoSessions() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["list", "--json", "--tag", "myTestTag"])
        XCTAssertEqual(result.exitCode, ExitCode.success, "list --json --tag should exit with success. Actual: \(result.exitCode.rawValue)")

        if !result.standardError.isEmpty && !result.standardError.contains("Logger shutting down") {
             print("Unexpected stderr for testListCommand_JsonOutput_WithTag_NoSessions was not empty:\n---\n\(result.standardError)---")
        }
        XCTAssertFalse(result.standardError.contains("Warning: Failed to list active sessions"), "Stderr should NOT contain session listing warning in JSON mode.")

        guard let jsonData = result.standardOutput.data(using: .utf8) else {
            XCTFail("Failed to convert JSON output to Data. stdout: \(result.standardOutput)")
            return
        }

        do {
            let decodedOutput = try JSONDecoder().decode([[String: TestAnyCodable]].self, from: jsonData)
            XCTAssertTrue(decodedOutput.isEmpty, "JSON output should be an empty array when no sessions match the tag.")
        } catch {
            XCTFail("Error decoding JSON output: \(error.localizedDescription). stdout:\n\(result.standardOutput)")
        }
    }

    // Note: Testing ListCommand with actual sessions would require mocking AppleScriptBridge
    // or having a controlled terminal environment.

    // MARK: - FocusCommand Tests

    func testFocusCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "testTag123"
        let result = try runCommand(arguments: ["focus", "--tag", tagValue])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Focus command should fail when underlying action fails in test.")
        // Check for an error message on stderr (FocusCommand should report failure for the tag)
        XCTAssertTrue(result.standardError.contains("Error focusing session with tag \"\(tagValue)\""), "Stderr should contain focus error message for tag. Got: \(result.standardError)")
    }

    func testFocusCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectTag456"
        let projectPath = "/Users/test/projectX"
        let result = try runCommand(arguments: ["focus", "--tag", tagValue, "--project-path", projectPath])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Focus command with tag and project path should fail when action fails.")
        XCTAssertTrue(result.standardError.contains("Error focusing session with tag \"\(tagValue)\" for project \"\(projectPath)\""), "Stderr should contain focus error message for tag with project context. Got: \(result.standardError)")
    }
    
    func testFocusCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["focus"])
        // ArgumentParser should catch missing required argument '--tag'
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.improperUsage), "Focus command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)")
        XCTAssertTrue(result.standardError.lowercased().contains("error: missing expected argument '--tag <tag>'"), "Stderr should indicate missing --tag argument. Got: \(result.standardError)")
    }

    // MARK: - ReadCommand Tests

    func testReadCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "readTag789"
        let result = try runCommand(arguments: ["read", "--tag", tagValue])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Read command should fail when underlying action fails in test.")
        XCTAssertTrue(result.standardError.contains("Error reading session output for tag \"\(tagValue)\""), "Stderr should contain read error message for tag. Got: \(result.standardError)")
    }

    func testReadCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectReadTag101"
        let projectPath = "/Users/test/projectY"
        let result = try runCommand(arguments: ["read", "--tag", tagValue, "--project-path", projectPath])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Read command with tag and project path should fail when action fails.")
        XCTAssertTrue(result.standardError.contains("Error reading session output for tag \"\(tagValue)\" in project \"\(projectPath)\""), "Stderr should contain read error message for tag with project context. Got: \(result.standardError)")
    }

    func testReadCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["read"])
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.improperUsage), "Read command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)")
        XCTAssertTrue(result.standardError.lowercased().contains("error: missing expected argument '--tag <tag>'"), "Stderr should indicate missing --tag argument. Got: \(result.standardError)")
    }

    // MARK: - KillCommand Tests

    func testKillCommand_WithTag_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "killTag123"
        // --focus-on-kill is a required Option, not a Flag
        let result = try runCommand(arguments: ["kill", "--tag", tagValue, "--focus-on-kill", "false"])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Kill command should fail when underlying action fails in test.")
        // Expect session not found or a general AppleScript/controller error
        XCTAssertTrue(
            result.standardError.contains("Error: Session for tag \"\(tagValue)\" in project \"N/A\" not found for kill.") || 
            result.standardError.contains("Error: AppleScript failed during kill operation.") ||
            result.standardError.contains("Failed to kill session process."),
            "Stderr should contain a relevant kill error message for tag. Got: \(result.standardError)"
        )
    }

    func testKillCommand_WithTagAndProjectPath_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "projectKillTag456"
        let projectPath = "/Users/test/projectZ"
        let result = try runCommand(arguments: ["kill", "--tag", tagValue, "--project-path", projectPath, "--focus-on-kill", "false"])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Kill command with tag and project path should fail when action fails.")
        XCTAssertTrue(
            result.standardError.contains("Error: Session for tag \"\(tagValue)\" in project \"\(projectPath)\" not found for kill.") ||
            result.standardError.contains("Error: AppleScript failed during kill operation.") ||
            result.standardError.contains("Failed to kill session process."),
            "Stderr should contain a relevant kill error message for tag with project context. Got: \(result.standardError)"
        )
    }

    func testKillCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        // Missing --tag, but --focus-on-kill is present
        let result = try runCommand(arguments: ["kill", "--focus-on-kill", "false"])
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.improperUsage), "Kill command should fail with improperUsage (64) if --tag is missing. Got \(result.exitCode.rawValue)")
        XCTAssertTrue(result.standardError.lowercased().contains("error: missing expected argument '--tag <tag>'"), "Stderr should indicate missing --tag argument. Got: \(result.standardError)")
    }
    
    func testKillCommand_MissingFocusOnKill() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        // Missing --focus-on-kill, but --tag is present
        let result = try runCommand(arguments: ["kill", "--tag", "someTag"])
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.improperUsage), "Kill command should fail with improperUsage (64) if --focus-on-kill is missing. Got \(result.exitCode.rawValue)")
        XCTAssertTrue(result.standardError.lowercased().contains("error: missing expected argument '--focus-on-kill <focus-on-kill>'"), "Stderr should indicate missing --focus-on-kill argument. Got: \(result.standardError)")
    }

    // MARK: - ExecCommand Tests

    func testExecCommand_MissingTag() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let result = try runCommand(arguments: ["exec"])
        XCTAssertEqual(result.exitCode, ExitCode(ErrorCodes.improperUsage), "Exec command should fail with improperUsage (64) if tag is missing. Got \(result.exitCode.rawValue)")
        XCTAssertTrue(result.standardError.lowercased().contains("error: missing expected argument '<tag>'"), "Stderr should indicate missing tag argument. Got: \(result.standardError)")
    }

    func testExecCommand_PrepareSession_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagNoCommand"
        let result = try runCommand(arguments: ["exec", tagValue]) // No --command, so it's a prepare

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Exec command (prepare session) should fail when underlying action fails.")
        // Expect a general error from the controller or session not found
        XCTAssertTrue(
            result.standardError.contains("Error executing command:") || result.standardError.contains("session not found"),
            "Stderr should contain a relevant error message for prepare session failure. Got: \(result.standardError)"
        )
    }

    func testExecCommand_WithCommand_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagWithCommand"
        let commandToRun = "echo hello"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Exec command with a command should fail when underlying action fails.")
        // Expect a general error from the controller or session not found
        XCTAssertTrue(
            result.standardError.contains("Error executing command:") || result.standardError.contains("session not found"),
            "Stderr should contain a relevant error message for command execution failure. Got: \(result.standardError)"
        )
    }

    func testExecCommand_Background_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagBackground"
        let commandToRun = "sleep 5"
        // --background is a Flag, so it doesn't take a value
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun, "--background"])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Exec command with --background should still report failure if action fails.")
        // Even for background, if the setup/initial dispatch fails (e.g. session not found), it should report an error.
        XCTAssertTrue(
            result.standardError.contains("Error executing command:") || result.standardError.contains("session not found"),
            "Stderr should contain a relevant error message for background command failure. Got: \(result.standardError)"
        )
    }

    func testExecCommand_EmptyCommand_IsPrepareSession_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagEmptyCommand"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", ""])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Exec command with empty command (prepare session) should fail when underlying action fails.")
        XCTAssertTrue(
            result.standardError.contains("Error executing command:") || result.standardError.contains("session not found"),
            "Stderr should contain a relevant error message for empty command (prepare) failure. Got: \(result.standardError)"
        )
    }
    
    func testExecCommand_WithTimeout_ActionFails() throws {
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
        defer { unsetenv("TERMINATOR_LOG_LEVEL") }

        let tagValue = "execTagWithTimeout"
        let commandToRun = "echo hello"
        let result = try runCommand(arguments: ["exec", tagValue, "--command", commandToRun, "--timeout", "1"])

        XCTAssertNotEqual(result.exitCode, ExitCode.success, "Exec command with timeout should fail when underlying action fails.")
        // The timeout itself might not be triggered if basic session setup fails first.
        // So we expect either a generic execution error or a session not found error primarily.
        // If a timeout error specific to AppConfig/Controller were to surface directly, the message would be different.
        XCTAssertTrue(
            result.standardError.contains("Error executing command:") || 
            result.standardError.contains("session not found") || 
            result.standardError.contains("timed out"), // Adding timeout as a possible message part
            "Stderr should contain a relevant error message for command execution failure with timeout. Got: \(result.standardError)"
        )
    }
}

// Note: The original testInfoCommand was removed as it was a placeholder.
// The testExample is commented out as it's not a primary test for CLI functionality.
// More tests for other commands, argument parsing, configuration loading, etc., should be added.