set windowData to {}
tell application "Terminal"
    repeat with aWindow in windows
        set windowID to id of aWindow
        set tabList to {}
        repeat with aTab in tabs of aWindow
            set tabIndex to index of aTab
            set tabTitle to custom title of aTab
            if tabTitle is missing value then
                set tabTitle to ""
            end if
            set end of tabList to {tabIndex, tabTitle}
        end repeat
        set end of windowData to {windowID, tabList}
    end repeat
end tell
return windowData