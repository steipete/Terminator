tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow

    -- Get the tab's history
    set tabHistory to history of targetTab

    -- Return the history
    return tabHistory
end tell