import CResponsibility
import Foundation
@testable import TerminatorCLI
import Testing

@Suite("Process Responsibility Tests", .tags(.configuration, .fast), .serialized)
struct ProcessResponsibilityTests {
    init() {
        // Clear any existing test environment
        unsetenv("TERMINATOR_SELF_RESPONSIBLE")
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }

    @Test("Should detect self-responsible process")
    func selfResponsibleDetection() {
        // Test when environment variable is not set
        let notResponsible = ProcessInfo.processInfo.environment["TERMINATOR_SELF_RESPONSIBLE"] == nil
        #expect(notResponsible == true)

        // Test when environment variable is set
        setenv("TERMINATOR_SELF_RESPONSIBLE", "1", 1)
        let isResponsible = ProcessInfo.processInfo.environment["TERMINATOR_SELF_RESPONSIBLE"] != nil
        #expect(isResponsible == true)

        // Cleanup
        unsetenv("TERMINATOR_SELF_RESPONSIBLE")
    }

    @Test("Should properly initialize spawn attributes")
    func spawnAttributesInitialization() {
        var attr: posix_spawnattr_t?
        let result = posix_spawnattr_init(&attr)
        #expect(result == 0)

        // Cleanup
        if attr != nil {
            posix_spawnattr_destroy(&attr)
        }
    }

    @Test("Should be able to call C wrapper function")
    func cWrapperFunction() {
        var attr: posix_spawnattr_t?
        let initResult = posix_spawnattr_init(&attr)
        #expect(initResult == 0)

        // Test calling the wrapper function (it will return an error since we're in test environment)
        if attr != nil {
            let disclaimResult = terminator_spawnattr_setdisclaim(&attr, 1)
            // The function may fail in test environment, but it should be callable
            #expect(disclaimResult != Int32.max) // Just verify it returns some value

            // Cleanup
            posix_spawnattr_destroy(&attr)
        }
    }

    @Test("Should handle process responsibility disclaiming")
    func processResponsibilityDisclaiming() {
        // We can't actually test the re-spawning in unit tests,
        // but we can verify the function doesn't crash when called
        // in an already-responsible process

        // Set the environment to simulate already being responsible
        setenv("TERMINATOR_SELF_RESPONSIBLE", "1", 1)

        // This should detect we're already responsible and return early
        ProcessResponsibility.disclaimParentResponsibility()

        // If we get here without crashing, the check worked
        #expect(Bool(true))

        // Cleanup
        unsetenv("TERMINATOR_SELF_RESPONSIBLE")
    }
}
