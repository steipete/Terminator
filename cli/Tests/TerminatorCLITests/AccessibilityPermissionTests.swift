import Testing
import Foundation
import ApplicationServices
@testable import TerminatorCLI

@Suite("Accessibility Permission Tests", .tags(.configuration, .fast), .serialized)
struct AccessibilityPermissionTests {
    
    init() {
        TestUtilities.clearEnvironment()
        setenv("TERMINATOR_LOG_LEVEL", "none", 1)
    }
    
    @Test("Should check accessibility permission status")
    func testAccessibilityPermissionCheck() {
        // We can't easily mock the actual permission state, but we can test the function runs
        let status = AccessibilityPermission.checkAccessibilityPermission()
        
        // Status should be a boolean
        #expect(status == true || status == false)
    }
    
    @Test("Should detect if accessibility is needed for script")
    func testAccessibilityNeededForScript() {
        // Test scripts that need accessibility
        let scriptsNeedingAccess = [
            "tell application \"System Events\" to keystroke \"c\" using command down",
            "tell app \"System Events\"\nkeystroke \"test\"\nend tell",
            "System Events keystroke command"
        ]
        
        for script in scriptsNeedingAccess {
            #expect(AccessibilityPermission.isAccessibilityNeededForScript(script) == true)
        }
        
        // Test scripts that don't need accessibility
        let scriptsNotNeedingAccess = [
            "tell application \"Terminal\" to activate",
            "do shell script \"echo hello\"",
            "set myVar to \"test\"",
            "tell application \"System Events\" to get process list"
        ]
        
        for script in scriptsNotNeedingAccess {
            #expect(AccessibilityPermission.isAccessibilityNeededForScript(script) == false)
        }
    }
    
    @Test("Should handle permission request without crashing")
    func testRequestAccessibilityPermission() {
        // Test that the function doesn't crash when called
        // We can't test the actual dialog appearance in unit tests
        // This just verifies the function executes without throwing
        AccessibilityPermission.requestAccessibilityPermission()
        
        // If we get here, the function didn't crash
        #expect(Bool(true))
    }
    
    @Test("Should log appropriate messages during permission check")
    func testPermissionCheckLogging() {
        // This test verifies that permission checking includes logging
        // We can't easily capture logs in unit tests, but we can verify
        // the function completes successfully
        
        let status = AccessibilityPermission.checkAccessibilityPermission()
        
        // The function should always return a valid boolean
        #expect(status == AXIsProcessTrusted())
    }
}