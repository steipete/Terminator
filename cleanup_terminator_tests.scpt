--------------------------------------------------------------------------------
-- cleanup_terminator_tests.scpt - Cleanup Script for Terminator Test Sessions
-- Removes all test-related terminal tabs and windows
-- Usage: osascript cleanup_terminator_tests.scpt
--------------------------------------------------------------------------------

on run
    log "🧹 Starting Terminator Test Cleanup..."
    
    tell application id "com.apple.Terminal"
        try
            set windowsToClose to {}
            set tabsToClose to {}
            set totalTabsClosed to 0
            set totalWindowsClosed to 0
            
            -- Simplified approach: close all windows that contain only test tabs
            set windowList to windows
            repeat with w in windowList
                try
                    set windowHasNonTestTabs to false
                    set windowTestTabs to {}
                    set tabList to tabs of w
                    
                    repeat with t in tabList
                        try
                            set tabTitle to custom title of t
                            if tabTitle starts with "Terminator 🤖💥 " then
                                -- Check for test patterns
                                if tabTitle contains "test_" or tabTitle contains "debug" or tabTitle contains "empty" or tabTitle contains "Test" then
                                    set end of windowTestTabs to t
                                    log "📋 Found test tab: " & tabTitle
                                else
                                    set windowHasNonTestTabs to true
                                end if
                            else
                                set windowHasNonTestTabs to true
                            end if
                        on error
                            -- Tab might not have custom title, assume it's a user tab
                            set windowHasNonTestTabs to true
                        end try
                    end repeat
                    
                    -- If window only has test tabs, mark entire window for closure
                    if not windowHasNonTestTabs and (count of windowTestTabs) > 0 then
                        set end of windowsToClose to w
                        log "🪟 Marking window for closure (contains only test tabs)"
                    else if (count of windowTestTabs) > 0 then
                        -- Otherwise, just mark test tabs for closure
                        repeat with testTab in windowTestTabs
                            set end of tabsToClose to testTab
                        end repeat
                    end if
                on error windowError
                    log "⚠️  Error accessing window: " & windowError
                end try
            end repeat
            
            -- Close individual test tabs first
            repeat with tabToClose in tabsToClose
                try
                    close tabToClose
                    set totalTabsClosed to totalTabsClosed + 1
                    delay 0.1
                on error tabError
                    log "⚠️  Could not close tab: " & tabError
                end try
            end repeat
            
            -- Close windows that contained only test tabs
            repeat with windowToClose in windowsToClose
                try
                    close windowToClose
                    set totalWindowsClosed to totalWindowsClosed + 1
                    delay 0.2
                on error windowError
                    log "⚠️  Could not close window: " & windowError
                end try
            end repeat
            
            -- Clean up temporary test files
            try
                do shell script "rm -rf /tmp/terminator_test_project"
                log "📁 Removed temporary test project directory"
            on error
                -- Directory might not exist, that's fine
            end try
            
            log "🗑️  Cleanup complete!"
            log "✅ Closed " & totalTabsClosed & " test tabs"
            log "✅ Closed " & totalWindowsClosed & " test windows"
            
            if totalTabsClosed = 0 and totalWindowsClosed = 0 then
                return "No Terminator test sessions found to clean up."
            else
                return "Successfully cleaned up " & totalTabsClosed & " test tabs and " & totalWindowsClosed & " test windows."
            end if
            
        on error cleanupError
            log "❌ Cleanup error: " & cleanupError
            return "Cleanup failed: " & cleanupError
        end try
    end tell
end run