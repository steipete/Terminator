--------------------------------------------------------------------------------
-- terminator.scpt - v0.5.0 "T-800"
-- AppleScript: Reliable project path detection, automatic 'cd', and window grouping.
--------------------------------------------------------------------------------

--#region Configuration Properties
property maxCommandWaitTime : 10.0 
property pollIntervalForBusyCheck : 0.1 
property startupDelayForTerminal : 0.7 
property minTailLinesOnWrite : 15 
property defaultTailLines : 30 
property tabTitlePrefix : "Terminator 🤖💥 " 
property scriptInfoPrefix : "Terminator 🤖💥: " 
property projectIdentifierInTitle : "Project: " 
property taskIdentifierInTitle : " - Task: "   
property enableFuzzyTagGrouping : true 
property fuzzyGroupingMinPrefixLength : 4 
--#endregion Configuration Properties

--#region Helper Functions
on isValidPath(thePath)
    if thePath is not "" and (thePath starts with "/") then
        -- A simple check: if it doesn't look like a command with flags.
        -- This is a heuristic. A path can technically contain hyphens.
        if not (thePath contains " -") then
            -- Consider it a path if it starts with / and doesn't immediately look like a command with options.
            -- This is to differentiate from a command like "/usr/bin/grep -r" being the first arg.
            -- A more robust solution would be to check if it's a valid accessible directory via 'do shell script "test -d ..." '
            -- but that's slow for initial parsing.
            return true
        end if
    end if
    return false
end isValidPath

on getPathComponent(thePath, componentIndex)
    set oldDelims to AppleScript's text item delimiters
    set AppleScript's text item delimiters to "/"
    set pathParts to text items of thePath
    set AppleScript's text item delimiters to oldDelims
    set nonEmptyParts to {}
    repeat with aPart in pathParts
        if aPart is not "" then set end of nonEmptyParts to aPart
    end repeat
    if (count nonEmptyParts) = 0 then return ""
    try
        if componentIndex is -1 then
            return item -1 of nonEmptyParts
        else if componentIndex > 0 and componentIndex ≤ (count nonEmptyParts) then
            return item componentIndex of nonEmptyParts
        end if
    on error
        return ""
    end try
    return ""
end getPathComponent

on generateWindowTitle(taskTag as text, projectGroup as text)
    if projectGroup is not "" then
        return tabTitlePrefix & projectIdentifierInTitle & projectGroup & taskIdentifierInTitle & taskTag
    else
        return tabTitlePrefix & taskTag 
    end if
end generateWindowTitle

-- (Other helpers: ensureTabAndWindow, tailBufferAS, etc. will be included below)
--#endregion Helper Functions


--#region Main Script Logic (on run)
on run argv
    set appSpecificErrorOccurred to false
    try
        tell application "System Events"
            if not (exists process "Terminal") then
                launch application id "com.apple.Terminal"
                delay startupDelayForTerminal
            end if
        end tell

        set originalArgCount to count argv
        if originalArgCount < 1 then return my usageText()

        --#region Argument Parsing v0.5.0
        set projectPathArg to ""
        set taskTagName to ""
        set doWrite to false
        set shellCmd to ""
        set originalUserShellCmd to "" -- To store command before 'cd' is prepended
        set currentTailLines to defaultTailLines
        set explicitLinesProvided to false
        
        set argOffset to 1 -- Current argument index to parse from argv

        -- 1. Check for Optional Project Path as the very first argument
        if originalArgCount >= argOffset then
            set potentialPath to item argOffset of argv
            if my isValidPath(potentialPath) then
                set projectPathArg to potentialPath
                set argOffset to argOffset + 1 -- Move to next argument for taskTagName
            end if
        end if

        -- 2. Get Task Tag Name
        if originalArgCount >= argOffset then
            set taskTagName to item argOffset of argv
            if (length of taskTagName) > 40 or (not my tagOK(taskTagName)) then
                set errorMsg to scriptInfoPrefix & "Task Tag missing or invalid: \"" & taskTagName & "\"." & linefeed & linefeed & ¬
                    "A 'task tag' (e.g., 'build', 'tests') is a short name (1-40 letters, digits, -, _) " & ¬
                    "to identify a specific task, optionally within a project session." & linefeed & linefeed
                return errorMsg & my usageText()
            end if
            set argOffset to argOffset + 1 -- Move to next argument for command/lines
        else
            -- Not enough arguments for even a tag after potentially consuming a path
            if projectPathArg is not "" then
                return scriptInfoPrefix & "Error: Project path \"" & projectPathArg & "\" provided, but no task tag specified." & linefeed & linefeed & my usageText()
            else
                return my usageText() -- Just 'osascript terminator.scpt'
            end if
        end if

        -- 3. Parse remaining arguments for Shell Command and Tail Lines
        set remainingArgsForCmdAndLines to {}
        if originalArgCount >= argOffset then
            set remainingArgsForCmdAndLines to items argOffset thru -1 of argv
        end if

        if (count remainingArgsForCmdAndLines) > 0 then
            set lastOfRemaining to item -1 of remainingArgsForCmdAndLines
            if my isInteger(lastOfRemaining) then
                set currentTailLines to (lastOfRemaining as integer)
                set explicitLinesProvided to true
                if (count remainingArgsForCmdAndLines) > 1 then
                    set remainingArgsForCmdAndLines to items 1 thru -2 of remainingArgsForCmdAndLines
                else
                    set remainingArgsForCmdAndLines to {}
                end if
            end if
        end if

        if (count remainingArgsForCmdAndLines) > 0 then
            set originalUserShellCmd to my joinList(remainingArgsForCmdAndLines, " ")
            if originalUserShellCmd is not "" and (my trimWhitespace(originalUserShellCmd) is not "") then
                set doWrite to true
                set shellCmd to originalUserShellCmd 
            else
                -- User provided "" or "   " as command
                set shellCmd to "" 
                if projectPathArg is not "" then 
                    set doWrite to true -- Will become 'cd path' command
                else
                    set doWrite to false
                end if
            end if
        else if projectPathArg is not "" then -- No command parts, but project path was given
            set doWrite to true -- Will become 'cd path' command
            set shellCmd to ""   -- User command is empty
        end if
        --#endregion Argument Parsing

        if currentTailLines < 1 then set currentTailLines to 1
        if doWrite and (shellCmd is not "" or projectPathArg is not "") and currentTailLines < minTailLinesOnWrite then
            set currentTailLines to minTailLinesOnWrite
        end if
        
        -- Prepend 'cd' if projectPathArg is set and we are doing a write operation
        if projectPathArg is not "" and doWrite then
            set quotedProjectPath to quoted form of projectPathArg
            if shellCmd is not "" then
                set shellCmd to "cd " & quotedProjectPath & " && " & shellCmd
            else
                set shellCmd to "cd " & quotedProjectPath -- Just cd if no other command
            end if
        end if
        
        set derivedProjectGroup to ""
        if projectPathArg is not "" then
            set derivedProjectGroup to my getPathComponent(projectPathArg, -1)
            if derivedProjectGroup is "" then set derivedProjectGroup to "DefaultProject" 
        end if

        set allowCreation to false
        if doWrite then -- If there's any command to execute (even just 'cd projectPath'), creation is allowed.
            set allowCreation to true
        else if explicitLinesProvided then -- If user specifies lines, implies intent to use/create session.
            set allowCreation to true
        end if
        -- Note: A call with just "/path/to/project" "task_tag" (no command, no lines) will be a read-only attempt.
        -- If the tag doesn't exist, it will error as per logic below, not create.

        set effectiveTabTitleForLookup to my generateWindowTitle(taskTagName, derivedProjectGroup)
        set tabInfo to my ensureTabAndWindow(taskTagName, derivedProjectGroup, allowCreation, effectiveTabTitleForLookup)

        if tabInfo is missing value then
            if not allowCreation then -- This implies it was a read-only call for a non-existent session
                set errorMsg to scriptInfoPrefix & "Error: Terminal session \"" & effectiveTabTitleForLookup & "\" not found." & linefeed & ¬
                    "To create this session, provide a command to run (even an empty string \"\" if you only want to 'cd' to a project path), " & ¬
                    "or specify a number of lines to read (e.g., ... \"" & taskTagName & "\" 1)." & linefeed
                if projectPathArg is not "" then
                    set errorMsg to errorMsg & "Project path was specified as: \"" & projectPathArg & "\"." & linefeed
                else
                    set errorMsg to errorMsg & "If this is for a new project, provide the absolute project path as the first argument." & linefeed
                end if
                return errorMsg & linefeed & my usageText()
            else 
                return scriptInfoPrefix & "Error: Could not find or create Terminal tab for \"" & effectiveTabTitleForLookup & "\". Check permissions/Terminal state."
            end if
        end if

        set targetTab to targetTab of tabInfo
        set parentWindow to parentWindow of tabInfo
        set wasNewlyCreated to wasNewlyCreated of tabInfo 
        set createdInExistingViaFuzzy to createdInExistingWindowViaFuzzy of tabInfo

        set bufferText to ""
        set commandTimedOut to false
        set tabWasBusyOnRead to false
        set previousCommandActuallyStopped to true 
        set attemptMadeToStopPreviousCommand to false
        set identifiedBusyProcessName to ""
        set theTTYForInfo to "" 

        if not doWrite and wasNewlyCreated then
            if createdInExistingViaFuzzy then
                return scriptInfoPrefix & "New tab \"" & effectiveTabTitleForLookup & "\" created in existing project window and ready."
            else
                return scriptInfoPrefix & "New tab \"" & effectiveTabTitleForLookup & "\" (in new window) created and ready."
            end if
        end if

        tell application id "com.apple.Terminal"
            try
                set index of parentWindow to 1
                set selected tab of parentWindow to targetTab
                if wasNewlyCreated and doWrite then 
                    delay 0.4 
                else
                    delay 0.1 
                end if

                --#region Write Operation Logic
                if doWrite and shellCmd is not "" then -- shellCmd now includes 'cd' if projectPathArg was given
                    set canProceedWithWrite to true 
                    if busy of targetTab then
                        if not wasNewlyCreated or createdInExistingViaFuzzy then 
                            set attemptMadeToStopPreviousCommand to true
                            set previousCommandActuallyStopped to false 
                            try
                                set theTTYForInfo to my trimWhitespace(tty of targetTab)
                            end try
                            set processesBefore to {}
                            try
                                set processesBefore to processes of targetTab
                            end try
                            set commonShells to {"login", "bash", "zsh", "sh", "tcsh", "ksh", "-bash", "-zsh", "-sh", "-tcsh", "-ksh", "dtterm", "fish"}
                            set identifiedBusyProcessName to "" 
                            if (count of processesBefore) > 0 then
                                repeat with i from (count of processesBefore) to 1 by -1
                                    set aProcessName to item i of processesBefore
                                    if aProcessName is not in commonShells then
                                        set identifiedBusyProcessName to aProcessName
                                        exit repeat
                                    end if
                                end repeat
                            end if
                            set processToTargetForKill to identifiedBusyProcessName
                            set killedViaPID to false
                            if theTTYForInfo is not "" and processToTargetForKill is not "" then
                                set shortTTY to text 6 thru -1 of theTTYForInfo 
                                set pidsToKillText to ""
                                try
                                    set psCommand to "ps -t " & shortTTY & " -o pid,comm | awk '$2 == \"" & processToTargetForKill & "\" {print $1}'"
                                    set pidsToKillText to do shell script psCommand
                                end try
                                if pidsToKillText is not "" then
                                    set oldDelims to AppleScript's text item delimiters
                                    set AppleScript's text item delimiters to linefeed
                                    set pidList to text items of pidsToKillText
                                    set AppleScript's text item delimiters to oldDelims
                                    repeat with aPID in pidList
                                        set aPID to my trimWhitespace(aPID)
                                        if aPID is not "" then
                                            try
                                                do shell script "kill -INT " & aPID
                                                delay 0.3 
                                                do shell script "kill -0 " & aPID 
                                                try
                                                    do shell script "kill -KILL " & aPID
                                                    delay 0.2
                                                    try
                                                        do shell script "kill -0 " & aPID
                                                    on error 
                                                        set previousCommandActuallyStopped to true
                                                    end try
                                                end try
                                            on error 
                                                set previousCommandActuallyStopped to true
                                            end try
                                        end if
                                        if previousCommandActuallyStopped then
                                            set killedViaPID to true
                                            exit repeat 
                                        end if
                                    end repeat
                                end if
                            end if
                            if not previousCommandActuallyStopped and busy of targetTab then 
                                activate 
                                delay 0.5 
                                tell application "System Events" to keystroke "c" using control down
                                delay 0.6 
                                if not (busy of targetTab) then
                                    set previousCommandActuallyStopped to true 
                                    if identifiedBusyProcessName is not "" and (identifiedBusyProcessName is in (processes of targetTab)) then
                                        set previousCommandActuallyStopped to false 
                                    end if
                                end if
                            else if not busy of targetTab then 
                                 set previousCommandActuallyStopped to true
                            end if
                            if not previousCommandActuallyStopped then
                                set canProceedWithWrite to false
                            end if
                        else if wasNewlyCreated and not createdInExistingViaFuzzy and busy of targetTab then
                            delay 0.4 
                            if busy of targetTab then
                                set attemptMadeToStopPreviousCommand to true 
                                set previousCommandActuallyStopped to false 
                                set identifiedBusyProcessName to "extended initialization"
                                set canProceedWithWrite to false
                            else
                                set previousCommandActuallyStopped to true 
                            end if
                        end if
                    end if 

                    if canProceedWithWrite then 
                        -- If it's a reused tab that was busy (and we stopped it) or wasn't busy, clear it.
                        -- If it's a new tab in an existing fuzzy group window, clear it.
                        -- If it's a brand new window, ensureTabAndWindow already ran 'clear'.
                        if not wasNewlyCreated or createdInExistingViaFuzzy then
                            do script "clear" in targetTab
                            delay 0.1
                        end if
                        
                        do script shellCmd in targetTab -- shellCmd now includes 'cd projectPath &&' if path was given
                        
                        set commandStartTime to current date
                        set commandFinished to false
                        repeat while ((current date) - commandStartTime) < maxCommandWaitTime
                            if not (busy of targetTab) then
                                set commandFinished to true
                                exit repeat
                            end if
                            delay pollIntervalForBusyCheck 
                        end repeat
                        if not commandFinished then set commandTimedOut to true
                        if commandFinished then delay 0.2 -- Increased delay for output to settle
                    end if
                --#endregion Write Operation Logic
                --#region Read Operation Logic
                else if not doWrite then 
                    if busy of targetTab then
                        set tabWasBusyOnRead to true
                        try
                            set theTTYForInfo to my trimWhitespace(tty of targetTab)
                        end try
                        set processesReading to processes of targetTab
                        set commonShells to {"login", "bash", "zsh", "sh", "tcsh", "ksh", "-bash", "-zsh", "-sh", "-tcsh", "-ksh", "dtterm", "fish"}
                        set identifiedBusyProcessName to "" 
                        if (count of processesReading) > 0 then
                            repeat with i from (count of processesReading) to 1 by -1
                                set aProcessName to item i of processesReading
                                if aProcessName is not in commonShells then
                                    set identifiedBusyProcessName to aProcessName
                                    exit repeat
                                end if
                            end repeat
                        end if
                    end if
                end if
                --#endregion Read Operation Logic
                
                -- Enhanced output capture with improved timing
                set bufferText to ""
                try
                    -- Add delay to ensure terminal buffer is updated
                    delay 0.3
                    set bufferText to history of targetTab
                on error
                    -- Fallback with longer delay if first attempt fails
                    delay 0.5
                    try
                        set bufferText to history of targetTab  
                    on error
                        set bufferText to ""
                    end try
                end try
            on error errMsg number errNum
                set appSpecificErrorOccurred to true
                return scriptInfoPrefix & "Terminal Interaction Error (" & errNum & "): " & errMsg
            end try
        end tell

        --#region Message Construction & Output Processing
        set appendedMessage to ""
        set ttyInfoStringForMessage to "" 
        if theTTYForInfo is not "" then set ttyInfoStringForMessage to " (TTY " & theTTYForInfo & ")"
        if attemptMadeToStopPreviousCommand then
            set processNameToReport to "process"
            if identifiedBusyProcessName is not "" and identifiedBusyProcessName is not "extended initialization" then
                set processNameToReport to "'" & identifiedBusyProcessName & "'"
            else if identifiedBusyProcessName is "extended initialization" then
                set processNameToReport to "tab's extended initialization"
            end if
            if previousCommandActuallyStopped then
                set appendedMessage to linefeed & scriptInfoPrefix & "Previous " & processNameToReport & ttyInfoStringForMessage & " was interrupted. ---"
            else
                set appendedMessage to linefeed & scriptInfoPrefix & "Attempted to interrupt previous " & processNameToReport & ttyInfoStringForMessage & ", but it may still be running. New command NOT executed. ---"
            end if
        end if
        if commandTimedOut then 
            set cmdForMsg to originalUserShellCmd
            if projectPathArg is not "" then set cmdForMsg to originalUserShellCmd & " (in " & projectPathArg & ")"
            set appendedMessage to appendedMessage & linefeed & scriptInfoPrefix & "Command '" & cmdForMsg & "' may still be running. Returned after " & maxCommandWaitTime & "s timeout. ---"
        else if tabWasBusyOnRead then 
            set processNameToReportOnRead to "process"
            if identifiedBusyProcessName is not "" then set processNameToReportOnRead to "'" & identifiedBusyProcessName & "'"
            set busyProcessInfoString to ""
            if identifiedBusyProcessName is not "" then set busyProcessInfoString to " with " & processNameToReportOnRead
            set appendedMessage to appendedMessage & linefeed & scriptInfoPrefix & "Tab" & ttyInfoStringForMessage & " was busy" & busyProcessInfoString & " during read. Output may be from an ongoing process. ---"
        end if

        if appendedMessage is not "" then
            if bufferText is "" or my lineIsEffectivelyEmptyAS(bufferText) then
                set bufferText to my trimWhitespace(appendedMessage)
            else
                set bufferText to bufferText & appendedMessage
            end if
        end if
        set scriptInfoPresent to (appendedMessage is not "")
        set contentBeforeInfoIsEmpty to false
        if scriptInfoPresent and bufferText is not "" then
            set tempDelims to AppleScript's text item delimiters
            set AppleScript's text item delimiters to scriptInfoPrefix 
            set firstPart to text item 1 of bufferText
            set AppleScript's text item delimiters to tempDelims
            if my trimBlankLinesAS(firstPart) is "" then
                set contentBeforeInfoIsEmpty to true
            end if
        end if
        
        if bufferText is "" or my lineIsEffectivelyEmptyAS(bufferText) or (scriptInfoPresent and contentBeforeInfoIsEmpty) then
            set baseMsg to "Session \"" & effectiveTabTitleForLookup & "\", requested " & currentTailLines & " lines."
            set anAppendedMessageForReturn to my trimWhitespace(appendedMessage)
            set messageSuffix to ""
            if anAppendedMessageForReturn is not "" then set messageSuffix to linefeed & anAppendedMessageForReturn
            set cmdForMsgContext to originalUserShellCmd
            if projectPathArg is not "" and originalUserShellCmd is not "" then set cmdForMsgContext to originalUserShellCmd & " (in " & projectPathArg & ")"
            if projectPathArg is not "" and originalUserShellCmd is "" then set cmdForMsgContext to "(cd " & projectPathArg & ")"

            if attemptMadeToStopPreviousCommand and not previousCommandActuallyStopped then
                 return scriptInfoPrefix & "Previous command/initialization in session \"" & effectiveTabTitleForLookup & "\"" & ttyInfoStringForMessage & " may not have terminated. New command '" & cmdForMsgContext & "' NOT executed." & messageSuffix
            else if commandTimedOut then
                return scriptInfoPrefix & "Command '" & cmdForMsgContext & "' timed out after " & maxCommandWaitTime & "s. No other output. " & baseMsg & messageSuffix
            else if tabWasBusyOnRead then
                return scriptInfoPrefix & "Tab was busy during read. No other output. " & baseMsg & messageSuffix
            else if doWrite and shellCmd is not "" then -- shellCmd includes cd here
                return scriptInfoPrefix & "Command '" & cmdForMsgContext & "' executed. No output captured. " & baseMsg
            else
                return scriptInfoPrefix & "No text content (history) found. " & baseMsg
            end if
        end if
        
        set tailedOutput to my tailBufferAS(bufferText, currentTailLines)
        set finalResult to my trimBlankLinesAS(tailedOutput)

        if finalResult is not "" then
            set tempCompareResult to finalResult
            if tempCompareResult starts with linefeed then
                try
                    set tempCompareResult to text 2 thru -1 of tempCompareResult
                on error
                    set tempCompareResult to ""
                end try
            end if
            if (tempCompareResult starts with scriptInfoPrefix) then
                set finalResult to my trimWhitespace(finalResult) 
            end if
        end if
        
        if finalResult is "" and bufferText is not "" and not my lineIsEffectivelyEmptyAS(bufferText) then
            set cmdForMsgContextFinal to originalUserShellCmd
            if projectPathArg is not "" and originalUserShellCmd is not "" then set cmdForMsgContextFinal to originalUserShellCmd & " (in " & projectPathArg & ")"
            if projectPathArg is not "" and originalUserShellCmd is "" then set cmdForMsgContextFinal to "(cd " & projectPathArg & ")"
            set baseMsgDetailPart to "Session \"" & effectiveTabTitleForLookup & "\", cmd: '" & cmdForMsgContextFinal & "'. History present."
            set trimmedAppendedMessageForDetail to my trimWhitespace(appendedMessage)
            set messageSuffixForDetail to ""
            if trimmedAppendedMessageForDetail is not "" then set messageSuffixForDetail to linefeed & trimmedAppendedMessageForDetail
            set descriptiveMessage to scriptInfoPrefix 
            if attemptMadeToStopPreviousCommand and not previousCommandActuallyStopped then
                 set descriptiveMessage to descriptiveMessage & baseMsgDetailPart & " Prev cmd not stopped, new cmd not run." & messageSuffixForDetail
            else if commandTimedOut then
                set descriptiveMessage to descriptiveMessage & baseMsgDetailPart & " Output empty after timeout." & messageSuffixForDetail
            else if tabWasBusyOnRead then
                set descriptiveMessage to descriptiveMessage & baseMsgDetailPart & " Output empty after busy read." & messageSuffixForDetail
            else if doWrite and shellCmd is not "" then
                set descriptiveMessage to descriptiveMessage & baseMsgDetailPart & " Output empty post-exec of last " & currentTailLines & " lines."
            else if not doWrite and (appendedMessage is not "" and (bufferText contains appendedMessage)) then
                return my trimWhitespace(appendedMessage)
            else
                set descriptiveMessage to scriptInfoPrefix & baseMsgDetailPart & " Content became empty post-processing."
            end if
            if descriptiveMessage is not "" and descriptiveMessage is not scriptInfoPrefix then return descriptiveMessage
        end if
        
        return finalResult

    on error generalErrorMsg number generalErrorNum
        if appSpecificErrorOccurred then error generalErrorMsg number generalErrorNum 
        return scriptInfoPrefix & "AppleScript Execution Error (" & generalErrorNum & "): " & generalErrorMsg
    end try
end run
--#endregion Main Script Logic (on run)


--#region Helper Functions
-- (ensureTabAndWindow and other helpers from v0.4.6 are largely the same,
-- ensureTabAndWindow takes 'desiredFullTitle' now)
on ensureTabAndWindow(taskTagName as text, projectGroupName as text, allowCreate as boolean, desiredFullTitle as text)
    set wasActuallyCreated to false
    set createdInExistingWin to false -- Renamed for clarity from createdInExistingWindowViaFuzzy

    tell application id "com.apple.Terminal"
        -- 1. Exact Match Search for the full task title
        try
            repeat with w in windows
                repeat with tb in tabs of w
                    try
                        if custom title of tb is desiredFullTitle then
                            set selected tab of w to tb
                            return {targetTab:tb, parentWindow:w, wasNewlyCreated:false, createdInExistingWindowViaFuzzy:false}
                        end if
                    end try
                end repeat
            end repeat
        end try

        -- 2. Fuzzy Grouping Search (if enabled and creation is allowed and we have a project group)
        if allowCreate and enableFuzzyTagGrouping and projectGroupName is not "" then
            set projectGroupSearchPatternForWindowName to tabTitlePrefix & projectIdentifierInTitle & projectGroupName
            try
                repeat with w in windows
                    try
                        if name of w starts with projectGroupSearchPatternForWindowName then
                            if not frontmost then activate
                            delay 0.2
                            set newTabInGroup to do script "clear" in w 
                            delay 0.3
                            set custom title of newTabInGroup to desiredFullTitle 
                            delay 0.2
                            set selected tab of w to newTabInGroup
                            return {targetTab:newTabInGroup, parentWindow:w, wasNewlyCreated:true, createdInExistingWindowViaFuzzy:true}
                        end if
                    end try
                end repeat
            end try
        end if

        -- 3. Create New Window (if allowed and no matches/fuzzy group found)
        if allowCreate then
            try
                if not frontmost then activate 
                delay 0.3
                set newTabInNewWindow to do script "clear" 
                set wasActuallyCreated to true
                delay 0.4 
                set custom title of newTabInNewWindow to desiredFullTitle 
                delay 0.2
                set parentWinOfNew to missing value
                try
                    set parentWinOfNew to window of newTabInNewWindow
                on error
                    if (count of windows) > 0 then set parentWinOfNew to front window
                end try
                if parentWinOfNew is not missing value then
                    if custom title of newTabInNewWindow is desiredFullTitle then 
                        set selected tab of parentWinOfNew to newTabInNewWindow
                        return {targetTab:newTabInNewWindow, parentWindow:parentWinOfNew, wasNewlyCreated:wasActuallyCreated, createdInExistingWindowViaFuzzy:false}
                    end if
                end if
                repeat with w_final_scan in windows
                    repeat with tb_final_scan in tabs of w_final_scan
                        try
                            if custom title of tb_final_scan is desiredFullTitle then
                                set selected tab of w_final_scan to tb_final_scan
                                return {targetTab:tb_final_scan, parentWindow:w_final_scan, wasNewlyCreated:wasActuallyCreated, createdInExistingWindowViaFuzzy:false}
                            end if
                        end try
                    end repeat
                end repeat
                return missing value 
            on error
                return missing value 
            end try
        else
            return missing value 
        end if
    end tell
end ensureTabAndWindow

on tailBufferAS(txt, n)
    set AppleScript's text item delimiters to linefeed
    set lst to text items of txt
    if (count lst) = 0 then return ""
    set startN to (count lst) - (n - 1)
    if startN < 1 then set startN to 1
    set slice to items startN thru -1 of lst 
    set outText to slice as text
    set AppleScript's text item delimiters to "" 
    return outText
end tailBufferAS

on lineIsEffectivelyEmptyAS(aLine)
    if aLine is "" then return true
    set trimmedLine to my trimWhitespace(aLine)
    return (trimmedLine is "")
end lineIsEffectivelyEmptyAS

on trimBlankLinesAS(txt)
    if txt is "" then return ""
    set oldDelims to AppleScript's text item delimiters
    set AppleScript's text item delimiters to {linefeed}
    set originalLines to text items of txt
    set linesToProcess to {}
    repeat with aLineRef in originalLines
        set aLine to contents of aLineRef
        if my lineIsEffectivelyEmptyAS(aLine) then
            set end of linesToProcess to ""
        else
            set end of linesToProcess to aLine
        end if
    end repeat
    set firstContentLine to 1
    repeat while firstContentLine ≤ (count linesToProcess) and (item firstContentLine of linesToProcess is "")
        set firstContentLine to firstContentLine + 1
    end repeat
    set lastContentLine to count linesToProcess
    repeat while lastContentLine ≥ firstContentLine and (item lastContentLine of linesToProcess is "")
        set lastContentLine to lastContentLine - 1
    end repeat
    if firstContentLine > lastContentLine then
        set AppleScript's text item delimiters to oldDelims
        return ""
    end if
    set resultLines to items firstContentLine thru lastContentLine of linesToProcess
    set AppleScript's text item delimiters to linefeed
    set trimmedTxt to resultLines as text
    set AppleScript's text item delimiters to oldDelims
    return trimmedTxt
end trimBlankLinesAS

on trimWhitespace(theText)
    set whitespaceChars to {" ", tab}
    set newText to theText
    repeat while (newText is not "") and (character 1 of newText is in whitespaceChars)
        if (length of newText) > 1 then
            set newText to text 2 thru -1 of newText
        else
            set newText to ""
        end if
    end repeat
    repeat while (newText is not "") and (character -1 of newText is in whitespaceChars)
        if (length of newText) > 1 then
            set newText to text 1 thru -2 of newText
        else
            set newText to ""
        end if
    end repeat
    return newText
end trimWhitespace

on isInteger(v)
    try
        v as integer
        return true
    on error
        return false
    end try
end isInteger

on tagOK(t)
    try
        do shell script "/bin/echo " & quoted form of t & " | /usr/bin/grep -E -q '^[A-Za-z0-9_-]+$'"
        return true
    on error
        return false
    end try
end tagOK

on joinList(theList, theDelimiter)
    set oldDelims to AppleScript's text item delimiters
    set AppleScript's text item delimiters to theDelimiter
    set theText to theList as text
    set AppleScript's text item delimiters to oldDelims
    return theText
end joinList

on usageText()
    set LF to linefeed
    set scriptName to "terminator.scpt"
    set exampleProject to "/Users/name/Projects/FancyApp"
    set exampleProjectNameForTitle to my getPathComponent(exampleProject, -1)
    if exampleProjectNameForTitle is "" then set exampleProjectNameForTitle to "UnknownProject"
    set exampleTaskTag to "build_frontend"
    set exampleFullCommand to "npm run build" -- Command without cd, as script handles cd
    
    set generatedExampleTitle to my generateWindowTitle(exampleTaskTag, exampleProjectNameForTitle)
    
    set outText to scriptName & " - v0.5.0 \"T-800\" – AppleScript Terminal helper" & LF & LF
    set outText to outText & "Manages dedicated, tagged Terminal sessions, grouped by project path." & LF & LF
    
    set outText to outText & "Core Concept:" & LF
    set outText to outText & "  1. For a NEW project, provide the absolute project path FIRST, then task tag, then command:" & LF
    set outText to outText & "     osascript " & scriptName & " \"" & exampleProject & "\" \"" & exampleTaskTag & "\" \"" & exampleFullCommand & "\"" & LF
    set outText to outText & "     The script will 'cd' into the project path and run the command." & LF
    set outText to outText & "     The tab will be titled like: \"" & generatedExampleTitle & "\"" & LF
    set outText to outText & "  2. For SUBSEQUENT commands in THE SAME PROJECT, use the project path and task tag:" & LF
    set outText to outText & "     osascript " & scriptName & " \"" & exampleProject & "\" \"" & exampleTaskTag & "\" \"another_command\"" & LF
    set outText to outText & "  3. To simply READ from an existing session (path & tag must identify an existing session):" & LF
    set outText to outText & "     osascript " & scriptName & " \"" & exampleProject & "\" \"" & exampleTaskTag & "\"" & LF & LF
    
    set outText to outText & "Title Format: \"" & tabTitlePrefix & projectIdentifierInTitle & "<ProjectName>" & taskIdentifierInTitle & "<TaskTag>\"" & LF
    set outText to outText & "Or if no project path provided: \"" & tabTitlePrefix & "<TaskTag>\"" & LF & LF
    
    set outText to outText & "Features:" & LF
    set outText to outText & "  • Automatically 'cd's into project path if provided with a command." & LF
    set outText to outText & "  • Groups new task tabs into existing project windows if fuzzy grouping enabled." & LF
    set outText to outText & "  • Read-only for a non-existent session will error." & LF
    set outText to outText & "  • Interrupts busy processes in reused tabs." & LF & LF
    
    set outText to outText & "Usage Examples:" & LF
    set outText to outText & "  # Start new project session, cd, run command, get 50 lines:" & LF
    set outText to outText & "  osascript " & scriptName & " \"" & exampleProject & "\" \"frontend_build\" \"npm run build\" 50" & LF
    set outText to outText & "  # Run another command in the same frontend_build session:" & LF
    set outText to outText & "  osascript " & scriptName & " \"" & exampleProject & "\" \"frontend_build\" \"npm run test\"" & LF
    set outText to outText & "  # Create/use a 'backend_tests' task tab in the same 'FancyApp' project window:" & LF
    set outText to outText & "  osascript " & scriptName & " \"" & exampleProject & "\" \"backend_tests\" \"pytest\"" & LF
    set outText to outText & "  # Prepare/create a new session by just cd'ing into project path (empty command):" & LF
    set outText to outText & "  osascript " & scriptName & " \"" & exampleProject & "\" \"dev_shell\" \"\" 1" & LF
    set outText to outText & "  # Read from an existing session:" & LF
    set outText to outText & "  osascript " & scriptName & " \"" & exampleProject & "\" \"frontend_build\" 10" & LF & LF
    
    set outText to outText & "Parameters:" & LF
    set outText to outText & "  [\"/absolute/project/path\"]: (Optional First Arg) Base path for project. Enables 'cd' and grouping." & LF
    set outText to outText & "  \"<task_tag_name>\": Required. Specific task name for the tab (e.g., 'build', 'tests')." & LF
    set outText to outText & "  [\"<shell_command_parts...>\"]: (Optional) Command. If path provided, 'cd path &&' is prepended." & LF
    set outText to outText & "                                Use \"\" for no command (will just 'cd' if path given)." & LF
    set outText to outText & "  [[lines_to_read]]: (Optional Last Arg) Number of history lines. Default: " & defaultTailLines & "." & LF & LF
        
    set outText to outText & "Notes:" & LF
    set outText to outText & "  • Provide project path on first use for a project for best window grouping and auto 'cd'." & LF
    set outText to outText & "  • Ensure Automation permissions for Terminal.app & System Events.app." & LF
    
    return outText
end usageText
--#endregion