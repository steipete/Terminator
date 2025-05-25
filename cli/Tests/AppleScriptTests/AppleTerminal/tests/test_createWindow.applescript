-- Get the path to the 'units' directory
tell application "Finder"
	set p to path to me as text -- Ensure it's text for manipulation
	set AppleScript's text item delimiters to ":"
	set pItems to text items of p
	-- Assuming current script is in .../AppleTerminal/tests/
	-- We want to go up from 'tests' to 'AppleTerminal', then down to 'units'
	set pItemsToParentOfTests to items 1 through -2 of pItems -- Removes 'test_createWindow.applescript' from path components
	set parentOfTestsPath to (text items of pItemsToParentOfTests as string) 
	set pItemsToAppleTerminalDir to items 1 through -2 of (text items of parentOfTestsPath) -- Removes 'tests' from path components
	set appleTerminalDirPath to (text items of pItemsToAppleTerminalDir as string)
	-- Ensure a trailing colon for appleTerminalDirPath if it doesn't have one, then append "units:"
    if not (appleTerminalDirPath ends with ":") then
        set appleTerminalDirPath to appleTerminalDirPath & ":"
    end if
	set unitsPath to appleTerminalDirPath & "units:"
end tell

set unitScriptName to "createWindow.applescript"
set unitScriptPath to unitsPath & unitScriptName
set unitScriptFileAlias to alias unitScriptPath -- Attempt to make an alias to check existence

-- Log the path for debugging
log "Unit script path determined as: " & unitScriptPath

set testResult to "FAILED: Unknown error"
set newWindowId to "UNSET_NEW_WINDOW_ID"
set rawUnitResult to "UNSET_RAW_UNIT_RESULT"

try
	-- Check if the unit script file actually exists at that path
	tell application "Finder"
		if not (exists file unitScriptFileAlias) then
			error "Unit script file not found at: " & unitScriptPath
		end if
	end tell

	tell application "Terminal"
		if not running then
			run
			delay 1
		end if
		set initialWindowCount to count of windows
	end tell
	
	set rawUnitResult to run script unitScriptFileAlias -- Run script using alias
	set newWindowId to rawUnitResult
	
	log "Raw result from unit script: " & (rawUnitResult as string)
	
	if newWindowId is missing value or newWindowId is "" or newWindowId is "UNSET_NEW_WINDOW_ID" then
		error "createWindow.applescript did not return a valid window ID. Got: " & (newWindowId as string)
	end if
	
	set newWindowIdAsInt to 0
	try
		set newWindowIdAsInt to newWindowId as integer
	on error
		error "Failed to convert returned window ID '" & (newWindowId as string) & "' to an integer."
	end try
	
	if newWindowIdAsInt is 0 then
		error "Converted window ID is 0, which is invalid. Original: " & (newWindowId as string)
	end if
	
	tell application "Terminal"
		activate
		delay 0.5 
		set finalWindowCount to count of windows
		if finalWindowCount <= initialWindowCount then
			error "Window count did not increase. Initial: " & initialWindowCount & ", Final: " & finalWindowCount & ". newWindowId: " & (newWindowId as string)
		end if
		
		set foundWindow to false
		try
			set targetWindow to first window whose id is newWindowIdAsInt
			if targetWindow exists then
				set foundWindow to true
			end if
		on error
			error "Failed to find window with ID (integer): " & newWindowIdAsInt & ". Original string: " & (newWindowId as string)
		end try
		
		if not foundWindow then
			error "Window with ID (integer) " & newWindowIdAsInt & " does not exist. Original string: " & (newWindowId as string)
		end if
		
		try
			log "Attempting to close window ID (integer): " & newWindowIdAsInt
			close (first window whose id is newWindowIdAsInt)
			delay 0.5
			set finalWindowCountAfterClose to count of windows
			if finalWindowCountAfterClose >= finalWindowCount then
				set testResult to "PASSED_WITH_CLEANUP_WARN: Window count did not decrease after close attempt."
			else
				set testResult to "PASSED"
			end if
		on error errMsgClose
			set testResult to "PASSED_WITH_CLEANUP_ERROR: Error closing new window (ID " & newWindowIdAsInt & "): " & errMsgClose
		end try
	end tell
	
on error errMsg number errNum
	set testResult to "FAILED: (" & errNum & ") " & errMsg & " --- Raw unit result: " & (rawUnitResult as string) & " --- newWindowId variable: " & (newWindowId as string) & " --- Unit script path: " & unitScriptPath
	if newWindowId is not missing value and newWindowId is not "" and newWindowId is not "UNSET_NEW_WINDOW_ID" then
		try
			set tempIdForClose to newWindowId as integer
			tell application "Terminal"
				close (first window whose id is tempIdForClose)
			end tell
		on error
			-- Ignore
		end try
	end if
end try

return testResult