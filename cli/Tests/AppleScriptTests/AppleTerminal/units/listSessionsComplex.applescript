set output_list to {}
tell application "Terminal"
    if not running then
        run
        delay 1.5
    end if
    try
        if (count of windows) > 0 then
            repeat with w in windows
            try
                set w_id to id of w
                repeat with t in tabs of w
                    try
                        set t_id to id of t
                        set ttyPath to tty of t
                        set customTitle to custom title of t
                        if customTitle is missing value then set customTitle to ""

                        set end of output_list to {"win_id:" & (w_id as string), "tab_id:" & (t_id as string), "tty:" & ttyPath, "title:" & customTitle}
                    on error tabErr
                        -- Skip this tab if we can't access it
                    end try
                end repeat
            on error winErr
                -- Skip this window if we can't access it
            end try
        end repeat
        end if
    on error errMsg number errNum
        error "AppleScript Error (Code " & (errNum as string) & "): " & errMsg
    end try
end tell
return output_list