import Foundation

// MARK: - Process Management Scripts

enum AppleTerminalProcessScripts {
    static func findPgidScriptForKill(ttyNameOnly: String) -> String {
        """
        -- Run ps command to find processes on this TTY
        set psCommand to "ps -t \(ttyNameOnly) -o pgid,pid,ppid,command | grep -v 'PID' | head -1 | awk '{print $1}'"
        set psResult to do shell script psCommand
        return psResult
        """
    }

    static func getPGIDAppleScript(ttyNameOnly: String) -> String {
        """
        -- Run ps to get the foreground process group
        set psCommand to "ps -t \(ttyNameOnly) -o pgid,pid,ppid,command | grep -v 'PID' | head -1 | awk '{print $1}'"
        set psResult to do shell script psCommand
        return psResult
        """
    }
}
