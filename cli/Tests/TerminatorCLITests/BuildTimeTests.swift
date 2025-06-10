import Testing
import Foundation
import ArgumentParser
@testable import TerminatorCLI

@Suite("Build Time Tests", .tags(.info, .configuration), .serialized)
struct BuildTimeTests {
    
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }
    
    @Test("InfoCommand should include build time")
    func testInfoCommandIncludesBuildTime() throws {
        // Run info command
        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])
        
        #expect(result.exitCode == ExitCode.success)
        
        // Parse JSON output
        let jsonData = Data(result.output.utf8)
        let info = try JSONDecoder().decode(InfoOutput.self, from: jsonData)
        
        // Check that buildTime exists and is not empty
        #expect(!info.buildTime.isEmpty)
        
        // Verify it's a valid ISO 8601 date
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: info.buildTime)
        #expect(date != nil)
    }
    
    @Test("Build time should be embedded at compile time")
    func testBuildTimeFormat() throws {
        // This tests that the inject-version.sh script properly sets BUILD_TIME
        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])
        
        guard result.exitCode == ExitCode.success else {
            throw TestError.commandFailed(
                "Info command failed with exit code: \(result.exitCode)\nError: \(result.errorOutput)"
            )
        }
        
        let jsonData = Data(result.output.utf8)
        let info = try JSONDecoder().decode(InfoOutput.self, from: jsonData)
        
        // Build time should be in the format: YYYY-MM-DDTHH:MM:SSZ
        let regex = try Regex("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
        #expect(info.buildTime.contains(regex))
    }
    
    @Test("Build time should be recent")
    func testBuildTimeRecency() throws {
        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])
        
        guard result.exitCode == ExitCode.success else {
            throw TestError.commandFailed(
                "Info command failed with exit code: \(result.exitCode)\nError: \(result.errorOutput)"
            )
        }
        
        let jsonData = Data(result.output.utf8)
        let info = try JSONDecoder().decode(InfoOutput.self, from: jsonData)
        
        let formatter = ISO8601DateFormatter()
        guard let buildDate = formatter.date(from: info.buildTime) else {
            throw TestError.invalidFormat("Invalid build time format: \(info.buildTime)")
        }
        
        // Build time should be within the last year (reasonable for a development build)
        let oneYearAgo = Date().addingTimeInterval(-365 * 24 * 60 * 60)
        #expect(buildDate > oneYearAgo)
        
        // And not in the future
        #expect(buildDate <= Date())
    }
    
    @Test("Version injection should work correctly")
    func testVersionInjection() throws {
        let result = try TestUtilities.runCommand(arguments: ["info", "--json"])
        
        guard result.exitCode == ExitCode.success else {
            throw TestError.commandFailed(
                "Info command failed with exit code: \(result.exitCode)\nError: \(result.errorOutput)"
            )
        }
        
        let jsonData = Data(result.output.utf8)
        let info = try JSONDecoder().decode(InfoOutput.self, from: jsonData)
        
        // Version should match expected pattern
        let versionRegex = try Regex("^\\d+\\.\\d+\\.\\d+(-\\w+\\.\\d+)?$")
        #expect(info.version.contains(versionRegex))
    }
}

enum TestError: Error, CustomStringConvertible {
    case commandFailed(String)
    case invalidFormat(String)
    
    var description: String {
        switch self {
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .invalidFormat(let message):
            return "Invalid format: \(message)"
        }
    }
}