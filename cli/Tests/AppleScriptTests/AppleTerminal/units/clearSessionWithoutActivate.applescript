tell application "Terminal"
    set targetWindow to window id "123456"
    set targetTab to tab "1" of targetWindow
    do script "clear && clear" in targetTab
    delay 0.1 -- Allow clear to process before keystroke
    
end tell