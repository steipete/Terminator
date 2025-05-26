set windowData to {}
tell application "Terminal"
    set wasRunning to running
    if not running then
        run
        -- Wait for Terminal to be ready
        set waitCount to 0
        repeat while waitCount < 20
            try
                if (count of windows) >= 0 then
                    -- Terminal is responding to window queries
                    exit repeat
                end if
            on error
                -- Terminal not ready yet
            end try
            delay 0.5
            set waitCount to waitCount + 1
        end repeat
    end if

    -- Try to get windows with error handling
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
                                -- Skip this tab
                            end try
                        end repeat
                    on error
                        -- No tabs accessible
                    end try
                    set end of windowData to {windowID, tabList}
                on error
                    -- Skip this window
                end try
            end repeat
        end if
    on error
        -- No windows accessible
    end try
end tell
return windowData