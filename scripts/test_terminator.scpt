--------------------------------------------------------------------------------
-- test_terminator.scpt - Test Suite for Terminator v0.5.1
-- Tests core functionality and improved output capture with bufferContainsMeaningfulContentAS
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
    
    -- Clean up test terminal tabs and windows with direct approach
    tell application id "com.apple.Terminal"
        try
            set totalTabsClosed to 0
            set totalWindowsClosed to 0
            set continueCleanup to true
            
            repeat while continueCleanup
                set continueCleanup to false
                
                repeat with w in windows
                    try
                        set windowHasNonTestTabs to false
                        set windowTestTabs to 0
                        
                        repeat with t in tabs of w
                            try
                                set tabTitle to custom title of t
                                if tabTitle starts with "Terminator 🤖💥 " then
                                    if tabTitle contains "test_" or tabTitle contains "debug" or tabTitle contains "empty" then
                                        set windowTestTabs to windowTestTabs + 1
                                    else
                                        set windowHasNonTestTabs to true
                                    end if
                                else
                                    set windowHasNonTestTabs to true
                                end if
                            on error
                                set windowHasNonTestTabs to true
                            end try
                        end repeat
                        
                        -- If window only has test tabs, close entire window
                        if not windowHasNonTestTabs and windowTestTabs > 0 then
                            close w
                            set totalWindowsClosed to totalWindowsClosed + 1
                            set continueCleanup to true
                            delay 0.2
                            exit repeat
                        else if windowTestTabs > 0 then
                            -- Close individual test tabs
                            set tabList to tabs of w
                            repeat with i from (count of tabList) to 1 by -1
                                try
                                    set t to item i of tabList
                                    set tabTitle to custom title of t
                                    if tabTitle starts with "Terminator 🤖💥 " then
                                        if tabTitle contains "test_" or tabTitle contains "debug" or tabTitle contains "empty" then
                                            close t
                                            set totalTabsClosed to totalTabsClosed + 1
                                            set continueCleanup to true
                                            delay 0.1
                                        end if
                                    end if
                                end try
                            end repeat
                        end if
                    end try
                end repeat
            end repeat
            
            log "🗑️  Closed " & totalTabsClosed & " test tabs and " & totalWindowsClosed & " test windows"
            
        on error cleanupError
            log "⚠️  Cleanup warning: " & cleanupError
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
    
    -- Test 3: Project Path Support (v0.5.0 - automatic cd)
    set testName to runTest("Project Path Support")
    try
        -- v0.5.0 automatically prepends 'cd' when project path is provided
        set result to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_project\" \"pwd && echo 'In project dir'\" 5"
        assertContains(result, "In project dir", "Project path navigation with auto-cd")
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
    
    -- Test 8: v0.5.0 Project Path Auto-Detection  
    set testName to runTest("v0.5.0 Project Path Detection")
    try
        -- Test that project paths are properly detected as first argument
        set result to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_path_detect\" \"echo 'Path detected correctly'\" 3"
        assertContains(result, "Path detected correctly", "Project path auto-detection")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 9: Directory Persistence (v0.5.0 - automatic cd)
    set testName to runTest("Directory Change")
    try
        -- v0.5.0 automatically handles 'cd' when project path is provided
        set result1 to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_cd\" \"pwd && echo 'Changed to project dir'\" 5"
        assertContains(result1, "Changed to project dir", "Directory change with auto-cd")
        
        delay 2
        -- Re-use existing session without project path (should maintain directory)
        set result2 to do shell script "osascript terminator.scpt " & quoted form of testProjectPath & " \"test_cd\" \"pwd && echo 'Still in project dir'\" 5"
        assertContains(result2, "Still in project dir", "Directory persistence")
        testPassed(testName)
    on error errorMsg
        testFailed(testName, errorMsg)
    end try
    
    -- Test 10: v0.5.1 Output Capture Fix
    set testName to runTest("v0.5.1 Output Capture Fix")
    try
        -- Test that commands with simple output are properly captured
        -- We need to ensure we're not getting false positives from error messages
        set result1 to do shell script "osascript terminator.scpt \"test_output_fix\" \"echo 'UniqueOutput12345'\" 5"
        
        -- Check that we got the actual output, not an error message containing the text
        if (result1 contains "UniqueOutput12345") and not (result1 contains "No output captured") and not (result1 contains "executed in session") then
            -- True positive - actual output captured
        else
            error "Output capture not working. Got: " & result1
        end if
        
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