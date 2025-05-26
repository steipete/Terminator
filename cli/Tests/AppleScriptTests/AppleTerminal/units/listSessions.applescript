set sessionList to {}
tell application "Terminal"
    repeat with aWindow in windows
        set windowID to id of aWindow
        repeat with aTab in tabs of aWindow
            set tabIndex to index of aTab
            set tabTitle to custom title of aTab
            if tabTitle is missing value then
                set tabTitle to ""
            end if
            set end of sessionList to {windowID, tabIndex, tabTitle}
        end repeat
    end repeat
end tell
return sessionList