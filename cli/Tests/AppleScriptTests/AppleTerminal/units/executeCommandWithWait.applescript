tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    activate
    -- First, navigate to the project directory
    do script "cd '/path/to/project'" in targetTab
    delay 0.5

    -- Execute the command
    do script "clear && echo 'hello world'" in targetTab

    -- Wait for command to complete
    set startTime to current date
    repeat
        if busy of targetTab is false then
            exit repeat
        end if
        if (current date) - startTime > 30.0 then
            error "Command execution timed out after 30.0 seconds"
        end if
        delay 0.1
    end repeat

    -- Return command result info
    set tabTitle to custom title of targetTab
    set tabBusy to busy of targetTab
    return {"123456", "1", tabTitle, tabBusy}
end tell