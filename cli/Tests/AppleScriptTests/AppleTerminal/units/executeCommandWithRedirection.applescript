tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    activate

    try
        do script "cd '/path/to/project' && clear && echo 'hello world' > output.txt && echo 'END_MARKER'" in targetTab
        return "OK_COMMAND_SUBMITTED"
    on error errMsg number errNum
        return "ERROR: AppleTerminal execute failed: " & errMsg & " (Number: " & (errNum as string) & ")"
    end try
end tell