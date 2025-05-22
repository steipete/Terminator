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
            
            -- Simple direct approach: iterate and close immediately
            set continueCleanup to true
            repeat while continueCleanup
                set continueCleanup to false
                set windowList to windows
                
                repeat with i from 1 to count of windowList
                    try
                        set w to item i of windowList
                        set windowHasNonTestTabs to false
                        set windowTestTabs to 0
                        set tabList to tabs of w
                        
                        repeat with j from 1 to count of tabList
                            try
                                set t to item j of tabList
                                set tabTitle to custom title of t
                                if tabTitle starts with "Terminator 🤖💥 " then
                                    -- Check for test patterns
                                    if tabTitle contains "test_" or tabTitle contains "debug" or tabTitle contains "empty" or tabTitle contains "Test" then
                                        set windowTestTabs to windowTestTabs + 1
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
                        
                        -- If window only has test tabs, close entire window
                        if not windowHasNonTestTabs and windowTestTabs > 0 then
                            try
                                close w
                                set totalWindowsClosed to totalWindowsClosed + 1
                                set continueCleanup to true
                                log "🪟 Closed window with " & windowTestTabs & " test tabs"
                                delay 0.3
                                exit repeat -- Start over since window list changed
                            on error windowError
                                log "⚠️  Could not close window: " & windowError
                            end try
                        else if windowTestTabs > 0 then
                            -- Close individual test tabs in mixed windows
                            repeat with j from (count of tabList) to 1 by -1
                                try
                                    set t to item j of tabList
                                    set tabTitle to custom title of t
                                    if tabTitle starts with "Terminator 🤖💥 " then
                                        if tabTitle contains "test_" or tabTitle contains "debug" or tabTitle contains "empty" or tabTitle contains "Test" then
                                            close t
                                            set totalTabsClosed to totalTabsClosed + 1
                                            set continueCleanup to true
                                            log "🗑️  Closed test tab: " & tabTitle
                                            delay 0.1
                                        end if
                                    end if
                                on error tabError
                                    log "⚠️  Could not close tab: " & tabError
                                end try
                            end repeat
                        end if
                    on error windowError
                        log "⚠️  Error accessing window: " & windowError
                    end try
                end repeat
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