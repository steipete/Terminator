import ArgumentParser
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Exec Command Grouping Tests", .tags(.exec, .grouping), .timeLimit(.minutes(1)), .serialized)
struct ExecCommandGroupingTests {
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    // Cleanup is handled in individual tests if needed

    // MARK: - Parameterized Grouping Tests

    struct GroupingTestCase: CustomTestStringConvertible, Sendable {
        let groupingMode: String
        let tagValue: String
        let projectPath: String
        let command: String
        let focusMode: String?

        var testDescription: String {
            "Grouping: \(groupingMode), Tag: \(tagValue)\(focusMode.map { ", Focus: \($0)" } ?? "")"
        }
    }

    @Test(
        "Window grouping modes",
        arguments: [
            GroupingTestCase(
                groupingMode: "project",
                tagValue: "execTagProjectGroup",
                projectPath: "/some/test/project_path",
                command: "echo hello",
                focusMode: nil
            ),
            GroupingTestCase(
                groupingMode: "project",
                tagValue: "execTagProjectGroupNoFocus",
                projectPath: "/some/test/project_path_nf",
                command: "echo nofocus",
                focusMode: "no-focus"
            ),
            GroupingTestCase(
                groupingMode: "smart",
                tagValue: "execTagSmartGroup",
                projectPath: "/some/test/smart_project",
                command: "echo smart",
                focusMode: nil
            ),
            GroupingTestCase(
                groupingMode: "off",
                tagValue: "execTagGroupOff",
                projectPath: "/some/test/off_project",
                command: "echo off",
                focusMode: nil
            )
        ]
    )
    func windowGroupingModes(_ testCase: GroupingTestCase) throws {
        var env = EnvironmentSetup()
        env.set("TERMINATOR_WINDOW_GROUPING", testCase.groupingMode)
        defer { env.restore() }

        var args = [
            "execute",
            testCase.tagValue,
            "--project-path", testCase.projectPath,
            "--command", testCase.command
        ]

        if let focusMode = testCase.focusMode {
            args.append(contentsOf: ["--focus-mode", focusMode])
        }

        try TestUtilities.assertActionFails(arguments: args)
    }

    // MARK: - CLI Override Tests

    @Test("CLI grouping flag should override environment variable", .tags(.environment))
    func cliGroupingOverride() throws {
        var env = EnvironmentSetup()
        env.set("TERMINATOR_WINDOW_GROUPING", "off")
        defer { env.restore() }

        // CLI --grouping should override the environment variable
        try TestUtilities.assertActionFails(
            arguments: [
                "execute", "execTagCLIOverride",
                "--project-path", "/some/test/override_project",
                "--command", "echo override",
                "--grouping", "project"
            ]
        )
    }

    // MARK: - Combined Parameter Tests

    struct CombinedTestCase: CustomTestStringConvertible, Sendable {
        let groupingMode: String
        let focusMode: String
        let background: Bool
        let tag: String

        var testDescription: String {
            "Grouping: \(groupingMode), Focus: \(focusMode), Background: \(background)"
        }
    }

    @Test(
        "Combined grouping, focus, and background modes",
        arguments: zip(
            ["project", "smart", "off"],
            ["force-focus", "no-focus", "auto-behavior"]
        ).map { grouping, focus in
            CombinedTestCase(
                groupingMode: grouping,
                focusMode: focus,
                background: false,
                tag: "combined-\(grouping)-\(focus)"
            )
        }
    )
    func combinedModes(_ testCase: CombinedTestCase) throws {
        var env = EnvironmentSetup()
        env.set("TERMINATOR_WINDOW_GROUPING", testCase.groupingMode)
        defer { env.restore() }

        var args = [
            "execute", testCase.tag,
            "--project-path", "/test/combined/path",
            "--command", "echo test",
            "--focus-mode", testCase.focusMode
        ]

        if testCase.background {
            args.append("--background")
        }

        try TestUtilities.assertActionFails(arguments: args)
    }
}

// Test tags are defined in TestTags.swift
