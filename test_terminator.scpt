--------------------------------------------------------------------------------
-- test_terminator.scpt - Test Suite for Terminator
-- Tests common functionality to ensure the script works correctly
-- Usage: osascript test_terminator.scpt
--------------------------------------------------------------------------------

property testProjectPath : "/tmp/terminator_test_project"
property testCounter : 0
property passedTests : 0
property failedTests : 0

--#region Test Framework
on runTest(testName)
    set testCounter to testCounter + 1
    log "🧪 Test " & testCounter & ": " & testName
    return testName
end runTest

on testPassed(testName)
    set passedTests to passedTests + 1
    log "✅ PASSED: " & testName
end testPassed

on testFailed(testName, errorMsg)
    set failedTests to failedTests + 1
    log "❌ FAILED: " & testName & " - " & errorMsg
end testFailed

on assertContains(haystack, needle, message)
    if haystack does not contain needle then
        error "Expected to find '" & needle & "' in output (" & message & ")"
    end if
end assertContains
--#endregion Test Framework

--#region Setup and Cleanup
on setupTestEnvironment()
    log "🔧 Setting up test environment..."
    
    -- Create test project directory
    try
        do shell script "mkdir -p " & quoted form of testProjectPath
        do shell script "echo 'Test project for Terminator' > " & quoted form of (testProjectPath & "/README.txt")
    end try
    
    -- Ensure Terminal is running
    tell application "System Events"
        if not (exists process "Terminal") then
            launch application id "com.apple.Terminal"
            delay 1
        end if
    end tell
end setupTestEnvironment

on cleanupTestEnvironment()
    log "🧹 Cleaning up test environment..."
    
    -- Remove test project
    try
        do shell script "rm -rf " & quoted form of testProjectPath
    end try
    
    -- Clean up test terminal tabs (be careful not to close user tabs)
    tell application id "com.apple.Terminal"
        try
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set tabTitle to custom title of t
                        if tabTitle starts with "Terminator 🤖💥 " then
                            if tabTitle contains "test_" then
                                close t
                            end if
                        end if
                    end try
                end repeat
            end repeat
        end try
    end tell
end cleanupTestEnvironment
--#endregion Setup and Cleanup

--#region Main Test Runner
on run
    log "🚀 Starting Terminator Test Suite"
    log "=================================="
    
    setupTestEnvironment()
    
    -- Test 1: Basic Command Execution
    set testName to runTest("Basic Command Execution")
    try
        set result to do shell script "osascript terminator.scpt \"test_basic\" \"echo 'Hello Terminator'\" 5"
        assertContains(result, "Hello Terminator", "Basic command output")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 2: Session Creation and Persistence
    set testName to runTest("Session Creation")
    try
        set result to do shell script "osascript terminator.scpt \"test_session\" \"echo 'Session created' && sleep 1\" 5"
        assertContains(result, "Session created", "Session creation output")
        
        delay 2
        set result2 to do shell script "osascript terminator.scpt \"test_session\" \"echo 'Still here'\" 3"
        assertContains(result2, "Still here", "Session persistence")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 3: Project Path Support
    set testName to runTest("Project Path Support")
    try
        set result to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_project\" \"cd " & testProjectPath & " && pwd && echo 'In project dir'\" 5"
        assertContains(result, "In project dir", "Project path navigation")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 4: Multiple Commands in Same Session
    set testName to runTest("Multiple Commands")
    try
        set result1 to do shell script "osascript terminator.scpt \"test_multi\" \"echo 'First command'\" 5"
        assertContains(result1, "First command", "First command output")
        
        delay 1
        set result2 to do shell script "osascript terminator.scpt \"test_multi\" \"echo 'Second command'\" 5"
        assertContains(result2, "Second command", "Second command output")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 5: Empty Session Creation
    set testName to runTest("Empty Session Creation")
    try
        set result to do shell script "osascript terminator.scpt \"test_empty_" & (random number from 1000 to 9999) & "\" \"\" 1"
        assertContains(result, "created and ready", "Empty session creation")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 6: Usage Display
    set testName to runTest("Usage Display")
    try
        set usageResult to do shell script "osascript terminator.scpt"
        assertContains(usageResult, "terminator.scpt", "Usage display")
        assertContains(usageResult, "Usage Examples", "Usage examples section")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 7: Invalid Tag Handling
    set testName to runTest("Invalid Tag")
    try
        try
            do shell script "osascript terminator.scpt \"test@invalid\" \"echo test\""
            error "Should have failed with invalid tag"
        on error errorMsg
            assertContains(errorMsg, "invalid", "Invalid tag error message")
        end try
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 8: Directory Persistence
    set testName to runTest("Directory Change")
    try
        set result1 to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_cd\" \"cd " & testProjectPath & " && pwd && echo 'Changed to project dir'\" 5"
        assertContains(result1, "Changed to project dir", "Directory change")
        
        delay 2
        set result2 to do shell script "osascript terminator.scpt \"test_cd\" \"pwd && echo 'Still in project dir'\" 5"
        assertContains(result2, "Still in project dir", "Directory persistence")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    cleanupTestEnvironment()
    
    -- Report results
    log "=================================="
    log "🏁 Test Suite Complete"
    log "✅ Passed: " & passedTests
    log "❌ Failed: " & failedTests
    log "📊 Total: " & testCounter
    
    if failedTests > 0 then
        log "💀 Some tests failed. Check the output above."
        return "FAILED: " & failedTests & " out of " & testCounter & " tests failed."
    else
        log "🎉 All tests passed!"
        return "SUCCESS: All " & testCounter & " tests passed."
    end if
end run
--#endregion Main Test Runner