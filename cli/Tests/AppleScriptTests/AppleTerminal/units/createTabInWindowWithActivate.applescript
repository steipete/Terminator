tell application "Terminal"
    activate
    set targetWindow to window id "123456"

    -- Create a new tab
    tell application "System Events" to keystroke "t" using command down

    -- The newly created tab becomes the selected tab
    set newTab to selected tab of targetWindow
    set custom title of newTab to "Test Session"

    -- Get the tab's index (which we'll use as ID)
    set tabID to index of newTab

    -- Get the TTY device
    set ttyDevice to tty of newTab

    -- Get the title
    set tabTitle to custom title of newTab

    return {"123456", tabID as string, ttyDevice, tabTitle}
end tell