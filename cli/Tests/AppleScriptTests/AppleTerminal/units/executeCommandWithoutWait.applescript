tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    
    -- Execute the command
    do script "echo 'hello world'" in targetTab

    -- Return command result info
    set tabTitle to custom title of targetTab
    set tabBusy to busy of targetTab
    return {"123456", "1", tabTitle, tabBusy}
end tell