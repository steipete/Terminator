tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    set selected of targetTab to true
    set frontmost of targetWindow to true
    activate
end tell