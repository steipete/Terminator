tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    do script "echo 'hello world'" in targetTab

    return "OK"
end tell