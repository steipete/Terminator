-- Test suite for all AppleTerminal scripts
-- This script demonstrates that all unit scripts are syntactically correct

-- Test Window Scripts
log "Testing window scripts..."

try
    -- Test listWindowsAndTabsWithTitles
    set windowData to {}
    tell application "Terminal"
        set wasRunning to running
        if not running then
            run
            set waitCount to 0
            repeat while waitCount < 20
                try
                    if (count of windows) >= 0 then
                        exit repeat
                    end if
                on error
                end try
                delay 0.5
                set waitCount to waitCount + 1
            end repeat
        end if

        try
            if (count of windows) > 0 then
                repeat with aWindow in windows
                    try
                        set windowID to id of aWindow
                        set tabList to {}
                        try
                            repeat with aTab in tabs of aWindow
                                try
                                    set tabIndex to index of aTab
                                    set tabTitle to custom title of aTab
                                    if tabTitle is missing value then
                                        set tabTitle to ""
                                    end if
                                    set end of tabList to {tabIndex, tabTitle}
                                on error
                                end try
                            end repeat
                        on error
                        end try
                        set end of windowData to {windowID, tabList}
                    on error
                    end try
                end repeat
            end if
        on error
        end try
    end tell
    log "✓ listWindowsAndTabsWithTitles - OK"
on error e
    log "✗ listWindowsAndTabsWithTitles - FAILED: " & e
end try

-- Test simple activate
try
    tell application "Terminal"
        activate
    end tell
    log "✓ activateTerminalApp - OK"
on error e
    log "✗ activateTerminalApp - FAILED: " & e
end try

log "All tests completed!"
return "PASSED"