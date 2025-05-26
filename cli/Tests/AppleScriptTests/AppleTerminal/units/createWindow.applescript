tell application "Terminal"
    set wasRunning to running
    if not running then
        run
        -- Wait for Terminal to create its default window
        set waitCount to 0
        repeat while (count of windows) = 0 and waitCount < 20
            delay 0.5
            set waitCount to waitCount + 1
        end repeat
    end if
    activate
    delay 0.5 -- Give Terminal time to activate

    try
        -- If Terminal just started and has a window, use it
        if not wasRunning and (count of windows) > 0 then
            set windowID to id of window 1
            return windowID as string
        else
            -- Otherwise create a new window
            set newWindow to make new window
            set windowID to id of newWindow
            return windowID as string
        end if
    on error errMsg number errNum
        -- If we can't create a new window, return the ID of the front window as fallback
        if (count of windows) > 0 then
            set windowID to id of front window
            return windowID as string
        else
            error "Failed to create window and no existing windows found: " & errMsg
        end if
    end try
end tell