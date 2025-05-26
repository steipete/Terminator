tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    -- Send Ctrl+C to the tab
    tell application "System Events"
        key code 8 using control down -- 8 is the key code for 'c'
    end tell

    return "OK_CTRL_C_SENT"
end tell