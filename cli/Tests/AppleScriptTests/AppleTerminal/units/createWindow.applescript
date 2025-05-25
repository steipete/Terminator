tell application "Terminal"
    if not running then
        if true then
            activate
        else
            run
        end if
        delay 0.5
    else if true then
        activate
    end if
    
    set new_window_ref to make new window
    delay 0.5 -- Increased delay
    try
        set new_window_id to id of new_window_ref
        return new_window_id as string
    on error err_msg number err_num
        error "Failed to get ID of new window. Error: (" & err_num & ") " & err_msg
    end try
end tell