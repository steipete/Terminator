tell application "Terminal"
    activate
    delay 0.5
    try
        set newWindow to make new window
        set windowID to id of newWindow
        return windowID as string
    on error errMsg number errNum
        -- If we can't create a new window, return the ID of the front window
        if (count of windows) > 0 then
            set windowID to id of front window
            return windowID as string
        else
            error "Failed to create window and no existing windows found: " & errMsg
        end if
    end try
end tell