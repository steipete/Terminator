set output_list to {}
tell application "{appName}" -- Placeholder
    if not running then error "Terminal application {appName} is not running." -- Placeholder
    try
        set window_indices to index of windows
        repeat with i from 1 to count of window_indices
            set w_index to item i of window_indices
            set w to window id (id of window w_index)
            set w_id_str to id of w as string

            set tab_details to {}
            set tab_indices to index of tabs of w
            repeat with j from 1 to count of tab_indices
                set t_index to item j of tab_indices
                set t to tab id (id of tab t_index of w)
                set t_id_str to id of t as string
                set customTitle to custom title of t
                if customTitle is missing value then set customTitle to ""
                set end of tab_details to {t_id_str, customTitle}
            end repeat
            set end of output_list to {w_id_str, tab_details}
        end repeat
    on error errMsg number errNum
        error "AppleScript Error (Code " & (errNum as string) & "): " & errMsg
    end try
end tell
return output_list