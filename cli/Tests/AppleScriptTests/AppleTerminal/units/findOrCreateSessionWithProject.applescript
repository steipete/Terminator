tell application "Terminal"
    if not running then
        run
        delay 1.0
    end if
    activate
    -- First, look for an existing session with the tag
    set foundSession to false
    set targetWindow to missing value
    set selectedTab to missing value

    if (count of windows) > 0 then
        repeat with aWindow in windows
            set windowID to id of aWindow
            repeat with aTab in tabs of aWindow
                set tabTitle to custom title of aTab
                if tabTitle contains "[project-tag]" then
                    set foundSession to true
                    set targetWindow to aWindow
                    set selectedTab to aTab
                    exit repeat
                end if
            end repeat
            if foundSession then exit repeat
        end repeat
    end if

    if not foundSession then
        -- No existing session found, create a new tab
        if (count of windows) = 0 then
            -- No windows exist, create one
            set targetWindow to make new window
        else
            -- Use the frontmost window
            set targetWindow to front window
        end if

        -- Create a new tab
        tell application "System Events" to keystroke "t" using command down

        -- The newly created tab becomes the selected tab
        set selectedTab to selected tab of targetWindow
        set custom title of selectedTab to "Project Session [project-tag]"
    end if

    -- Navigate to project directory
    do script "cd '/path/to/project'" in selectedTab
    delay 0.5

    set selected of selectedTab to true
    set frontmost of targetWindow to true
    -- Return session info
    set windowID to id of targetWindow
    set tabID to index of selectedTab
    set ttyDevice to tty of selectedTab
    set tabTitle to custom title of selectedTab

    return {windowID as string, tabID as string, ttyDevice, tabTitle, foundSession}
end tell