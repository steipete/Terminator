import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

/// Tests that simulate scenarios where terminal state might matter
/// These tests use .serialized to ensure they run one at a time
@Suite("Stateful Terminal Tests", .serialized, .timeLimit(.minutes(1)))
struct StatefulTests {
    // Shared state that might be used across tests
    static let sharedProjectPath = "/test/stateful/project"
    static let sharedTag = "stateful-session"

    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Session Lifecycle Tests

    @Test("Create and prepare session")
    func createSession() throws {
        // Simulate creating a new session
        try TestUtilities.assertActionFails(
            arguments: ["execute", Self.sharedTag, "--project-path", Self.sharedProjectPath]
        )
    }

    @Test("Execute command in existing session")
    func executeInSession() throws {
        // Simulate executing in a potentially existing session
        try TestUtilities.assertActionFails(
            arguments: [
                "execute", Self.sharedTag,
                "--project-path", Self.sharedProjectPath,
                "--command", "echo 'Hello from existing session'"
            ]
        )
    }

    @Test("Read from session after execution")
    func readFromSession() throws {
        // Simulate reading from a session that might have output
        try TestUtilities.assertActionFails(
            arguments: [
                "read",
                "--tag", Self.sharedTag,
                "--project-path", Self.sharedProjectPath,
                "--lines", "50"
            ]
        )
    }

    @Test("Kill process in session")
    func killProcessInSession() throws {
        // Simulate killing a process in an existing session
        try TestUtilities.assertActionFails(
            arguments: [
                "kill",
                "--tag", Self.sharedTag,
                "--project-path", Self.sharedProjectPath,
                "--focus-on-kill", "false"
            ],
            expectedErrors: ["not found for kill", "Error: AppleScript failed", "Failed to kill session"]
        )
    }

    // MARK: - Race Condition Tests

    @Suite("Race Condition Simulation", .serialized)
    struct RaceConditionTests {
        @Test("Rapid session creation attempts")
        func rapidSessionCreation() throws {
            // Simulate rapid attempts to create sessions that might conflict
            for i in 0..<3 {
                try TestUtilities.assertActionFails(
                    arguments: [
                        "execute", "rapid-tag-\(i)",
                        "--project-path", "/test/rapid/project",
                        "--command", "echo 'Rapid test \(i)'"
                    ]
                )
            }
        }

        @Test("Concurrent read/write simulation")
        func concurrentReadWrite() throws {
            let tag = "concurrent-test"
            let projectPath = "/test/concurrent/project"

            // Simulate write
            try TestUtilities.assertActionFails(
                arguments: [
                    "execute", tag,
                    "--project-path", projectPath,
                    "--command", "echo 'Writing data'",
                    "--background"
                ]
            )

            // Simulate immediate read
            try TestUtilities.assertActionFails(
                arguments: [
                    "read",
                    "--tag", tag,
                    "--project-path", projectPath
                ]
            )
        }
    }
}

// MARK: - Integration Test Suite

/// Tests that verify the full command flow
@Suite("Integration Tests", .tags(.integration), .timeLimit(.minutes(2)), .serialized)
struct IntegrationTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    @Test("Full command lifecycle")
    func fullCommandLifecycle() throws {
        let tag = "lifecycle-test"
        let projectPath = "/test/lifecycle/project"

        // 1. List sessions (should be empty initially)
        let listResult = try TestUtilities.runCommand(arguments: ["sessions", "--json"])
        #expect(listResult.exitCode == ExitCode.success)

        // 2. Create and execute a command
        try TestUtilities.assertActionFails(
            arguments: [
                "execute", tag,
                "--project-path", projectPath,
                "--command", "echo 'Test output'"
            ]
        )

        // 3. Try to read the output
        try TestUtilities.assertActionFails(
            arguments: [
                "read",
                "--tag", tag,
                "--project-path", projectPath
            ]
        )

        // 4. Focus the session
        try TestUtilities.assertActionFails(
            arguments: [
                "focus",
                "--tag", tag,
                "--project-path", projectPath
            ]
        )

        // 5. Kill any process
        try TestUtilities.assertActionFails(
            arguments: [
                "kill",
                "--tag", tag,
                "--project-path", projectPath,
                "--focus-on-kill", "false"
            ],
            expectedErrors: ["not found for kill", "Error: AppleScript failed", "Failed to kill session"]
        )
    }

    @Test("Info command shows configuration", .tags(.info))
    func infoShowsConfiguration() throws {
        let result = try TestUtilities.runCommand(arguments: ["info"])

        #expect(result.exitCode == ExitCode.success)
        #expect(result.output.contains("Terminator CLI Version:"))
        #expect(result.output.contains("TERMINATOR_APP:"))
    }
}

// Test tags are defined in TestTags.swift
