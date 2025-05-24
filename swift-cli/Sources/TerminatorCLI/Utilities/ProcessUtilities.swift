import Foundation

struct ProcessUtilities {
    static func getForegroundProcessInfo(forTTY ttyPath: String) -> (pgid: pid_t, pid: pid_t, command: String)? {
        let ttyName = (ttyPath as NSString).lastPathComponent
        if ttyName.isEmpty {
            Logger.log(level: .warn, "Could not extract TTY name from path: \(ttyPath)")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-t", ttyName, "-o", "pgid=,pid=,stat=,comm="]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                Logger.log(level: .warn, "Failed to get output from ps for TTY \(ttyName)")
                return nil
            }
            
            Logger.log(level: .debug, "ps output for TTY \(ttyName):\n\(output)")
            
            if output.isEmpty { return nil }
            
            let lines = output.split(whereSeparator: \.isNewline)
            let commonShells = ["bash", "zsh", "fish", "sh", "tcsh", "csh", "login", "script"]
            
            for line in lines {
                let columns = line.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
                guard columns.count >= 4 else { continue }
                
                let pgidStr = columns[0]
                let pidStr = columns[1]
                let state = columns[2]
                let commandName = (columns[3] as NSString).lastPathComponent
                
                if state.contains("+") && !state.contains("s") && !commonShells.contains(commandName.lowercased()) {
                    guard let pgid = pid_t(pgidStr), let pid = pid_t(pidStr) else {
                        Logger.log(level: .warn, "Failed to parse PGID or PID from ps output")
                        continue
                    }
                    Logger.log(level: .info, "TTY \(ttyName) has foreground process: \(commandName) (PGID: \(pgid), PID: \(pid), State: \(state))")
                    return (pgid: pgid, pid: pid, command: commandName)
                }
            }
            
            Logger.log(level: .debug, "TTY \(ttyName) has no non-shell foreground process.")
            return nil
        } catch {
            Logger.log(level: .error, "Failed to run ps for TTY \(ttyName): \(error.localizedDescription)")
            return nil
        }
    }
    
    static func getTTYBusyStatus(tty: String?) -> Bool {
        guard let ttyPath = tty, !ttyPath.isEmpty else {
            Logger.log(level: .debug, "TTY path is nil or empty, cannot determine busy status.")
            return false
        }
        
        return getForegroundProcessInfo(forTTY: ttyPath) != nil
    }
    
    static func isProcessRunning(pid: pid_t) -> Bool {
        if pid <= 0 { // Invalid PID
            Logger.log(level: .debug, "isProcessRunning check for invalid PID \(pid): assuming not running.")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/kill")
        process.arguments = ["-0", "\\(pid)"]

        let nullPipe = Pipe()
        process.standardOutput = nullPipe
        process.standardError = nullPipe

        do {
            try process.run()
            process.waitUntilExit()
            Logger.log(level: .debug, "isProcessRunning check for PID \(pid): kill -0 exit code \(process.terminationStatus)")
            return process.terminationStatus == 0 // kill -0 returns 0 if process exists and signal can be sent
        } catch {
            Logger.log(level: .error, "Failed to run kill -0 for PID \(pid): \(error.localizedDescription)")
            return false
        }
    }
    
    // Helper to kill a process group
    // Returns true if kill command was issued without immediate error, false otherwise.
    // It does not guarantee the process group is terminated, only that the signal was sent.
    static func killProcessGroup(pgid: pid_t, signal: Int32) -> Bool {
        if pgid <= 0 { // Invalid PGID
            Logger.log(level: .warn, "Attempted to kill invalid PGID: \(pgid)")
            return false
        }
        Logger.log(level: .info, "Sending signal \(signal) to process group \(pgid).")
        if Darwin.killpg(pgid, signal) == 0 {
            return true
        } else {
            let errorNumber = errno
            Logger.log(level: .error, "Failed to send signal \(signal) to PGID \(pgid). Errno: \(errorNumber) (\(String(cString: strerror(errorNumber))))")
            return false
        }
    }

    static func isProcessGroupRunning(pgid: pid_t) -> Bool {
        if pgid <= 0 { // Invalid PGID
            Logger.log(level: .debug, "isProcessGroupRunning check for invalid PGID \(pgid): assuming not running.")
            return false
        }
        // Sending signal 0 to a PGID checks if any process in the group exists
        // and if we have permission to signal them.
        // killpg returns 0 on success, -1 on error.
        // ESRCH means no process in the group could be found.
        // EPERM means a process exists but we don't have permission (treat as running for safety).
        if Darwin.killpg(pgid, 0) == 0 {
            Logger.log(level: .debug, "isProcessGroupRunning check for PGID \(pgid): killpg(0) successful, group is running.")
            return true // Process group exists
        } else {
            let errorNumber = errno
            if errorNumber == ESRCH {
                Logger.log(level: .debug, "isProcessGroupRunning check for PGID \(pgid): killpg(0) failed with ESRCH, group not running.")
                return false // No such process group
            } else {
                // For other errors (like EPERM), assume it might be running or in a state we can't fully determine as "not running".
                Logger.log(level: .debug, "isProcessGroupRunning check for PGID \(pgid): killpg(0) failed with errno \(errorNumber) (\(String(cString: strerror(errorNumber)))). Assuming running or indeterminate.")
                return true 
            }
        }
    }

    /// Attempts to gracefully kill a process group with a sequence of signals.
    /// - Parameters:
    ///   - pgid: The process group ID to kill.
    ///   - config: AppConfig containing timeout values for SIGINT and SIGTERM.
    ///   - message: An inout string to append messages about the kill process.
    /// - Returns: `true` if the process group was confirmed to be terminated, `false` otherwise.
    static func attemptGracefulKill(pgid: pid_t, config: AppConfig, message: inout String) -> Bool {
        var killSuccess = false

        // 1. SIGINT
        if killProcessGroup(pgid: pgid, signal: SIGINT) {
            message += " Sent SIGINT to PGID \(pgid)."
            Logger.log(level: .debug, "Sent SIGINT to PGID \(pgid). Waiting for \(config.sigintWaitSeconds)s...")
            Thread.sleep(forTimeInterval: TimeInterval(config.sigintWaitSeconds))
            if !isProcessGroupRunning(pgid: pgid) { 
                killSuccess = true
                message += " Process group terminated after SIGINT."
                Logger.log(level: .info, "Process group \(pgid) terminated after SIGINT.")
            }
        } else {
            message += " Failed to send SIGINT to PGID \(pgid)."
        }

        // 2. SIGTERM (if not already killed)
        if !killSuccess {
            if killProcessGroup(pgid: pgid, signal: SIGTERM) {
                message += " Sent SIGTERM to PGID \(pgid)."
                Logger.log(level: .debug, "Sent SIGTERM to PGID \(pgid). Waiting for \(config.sigtermWaitSeconds)s...")
                Thread.sleep(forTimeInterval: TimeInterval(config.sigtermWaitSeconds))
                if !isProcessGroupRunning(pgid: pgid) {
                    killSuccess = true
                    message += " Process group terminated after SIGTERM."
                    Logger.log(level: .info, "Process group \(pgid) terminated after SIGTERM.")
                }
            } else {
                 message += " Failed to send SIGTERM to PGID \(pgid)."
            }
        }

        // 3. SIGKILL (if still not killed)
        if !killSuccess {
            Logger.log(level: .warn, "Process group \(pgid) still running after SIGINT/SIGTERM. Sending SIGKILL.")
            if killProcessGroup(pgid: pgid, signal: SIGKILL) {
                message += " Sent SIGKILL to PGID \(pgid)."
                Thread.sleep(forTimeInterval: 0.2) // Short delay for SIGKILL to take effect
                if !isProcessGroupRunning(pgid: pgid) {
                    killSuccess = true
                    message += " Process group terminated after SIGKILL."
                    Logger.log(level: .info, "Process group \(pgid) terminated after SIGKILL.")
                } else {
                    message += " Process group still running after SIGKILL."
                    Logger.log(level: .warn, "Process group \(pgid) did not terminate even after SIGKILL.")
                }
            } else {
                 message += " Failed to send SIGKILL to PGID \(pgid)."
                 Logger.log(level: .error, "Failed to send SIGKILL to PGID \(pgid).")
            }
        }
        return killSuccess
    }

    static func tailLogFileForMarker(logFilePath: String, marker: String, timeoutSeconds: Int, linesToCapture: Int, controlIdentifier: String = "LogTailing") -> (output: String, timedOut: Bool) {
        Logger.log(level: .debug, "[\\(controlIdentifier)] Tailing \\\\(logFilePath) for marker '\\\\(marker)' with timeout \\\\(timeoutSeconds)s")
        let startTime = Date()
        var capturedOutput = ""

        while Date().timeIntervalSince(startTime) < Double(timeoutSeconds) {
            usleep(200_000) // Check every 200ms

            guard FileManager.default.fileExists(atPath: logFilePath) else {
                continue // Log file might not be created immediately
            }

            do {
                let content = try String(contentsOfFile: logFilePath, encoding: .utf8)
                if content.contains(marker) {
                    Logger.log(level: .info, "[\\(controlIdentifier)] Marker '\\\\(marker)' found in \\\\(logFilePath).")
                    var lines = content.components(separatedBy: .newlines)
                    if let markerIndex = lines.firstIndex(where: { $0.contains(marker) }) {
                        lines.remove(at: markerIndex) // Remove the marker line itself
                    }
                    if linesToCapture > 0 && lines.count > linesToCapture {
                        capturedOutput = lines.suffix(linesToCapture).joined(separator: "\\n")
                    } else {
                        capturedOutput = lines.joined(separator: "\\n")
                    }
                    return (capturedOutput, false)
                }
            } catch {
                Logger.log(level: .warn, "[\\(controlIdentifier)] Error reading log file \\\\(logFilePath): \\\\(error.localizedDescription)")
            }
        }

        Logger.log(level: .warn, "[\\(controlIdentifier)] Timeout waiting for marker '\\\\(marker)' in \\\\(logFilePath).")
        if FileManager.default.fileExists(atPath: logFilePath) {
            do {
                let content = try String(contentsOfFile: logFilePath, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                if linesToCapture > 0 && lines.count > linesToCapture {
                    capturedOutput = lines.suffix(linesToCapture).joined(separator: "\\n")
                } else {
                    capturedOutput = lines.joined(separator: "\\n")
                }
                capturedOutput += "\\n---[MARKER NOT FOUND, TIMEOUT OCURRED] ---" // Append timeout info
            } catch {
                Logger.log(level: .error, "[\\(controlIdentifier)] Error reading log file \\\\(logFilePath) on timeout: \\\\(error.localizedDescription)")
                capturedOutput = "Error reading log file on timeout: \\\\(error.localizedDescription)"
            }
        } else {
            capturedOutput = "Log file \\\\(logFilePath) not found or empty after timeout."
        }
        return (capturedOutput, true)
    }
}

extension ProcessUtilities {
    /// Attempts to kill a process group with SIGTERM, then SIGKILL if it persists, specifically for command timeouts.
    /// - Parameters:
    ///   - pgid: The process group ID to kill.
    ///   - config: AppConfig containing timeout values (uses `sigtermWaitSeconds`).
    ///   - message: An inout string to append messages about the kill process.
    /// - Returns: `true` if the process group was confirmed to be terminated, `false` otherwise.
    static func attemptExecuteTimeoutKill(pgid: pid_t, config: AppConfig, message: inout String) -> Bool {
        var killSuccess = false
        Logger.log(level: .warn, "Foreground command timed out. Attempting to kill PGID \(pgid).")

        // 1. SIGTERM
        if killProcessGroup(pgid: pgid, signal: SIGTERM) {
            message += " Sent SIGTERM to PGID \(pgid) due to command timeout."
            Logger.log(level: .debug, "Sent SIGTERM to PGID \(pgid). Waiting for \(config.sigtermWaitSeconds)s...")
            Thread.sleep(forTimeInterval: TimeInterval(config.sigtermWaitSeconds)) // Use sigtermWaitSeconds from config
            if !isProcessGroupRunning(pgid: pgid) {
                killSuccess = true
                message += " Process group terminated after SIGTERM."
                Logger.log(level: .info, "Process group \(pgid) terminated after SIGTERM (post-timeout).")
            }
        } else {
            message += " Failed to send SIGTERM to PGID \(pgid) (post-timeout)."
        }

        // 2. SIGKILL (if still not killed)
        if !killSuccess {
            Logger.log(level: .warn, "Process group \(pgid) still running after SIGTERM (post-timeout). Sending SIGKILL.")
            if killProcessGroup(pgid: pgid, signal: SIGKILL) {
                message += " Sent SIGKILL to PGID \(pgid)."
                Thread.sleep(forTimeInterval: 0.2) // Short delay for SIGKILL to take effect
                if !isProcessGroupRunning(pgid: pgid) {
                    killSuccess = true
                    message += " Process group terminated after SIGKILL."
                    Logger.log(level: .info, "Process group \(pgid) terminated after SIGKILL (post-timeout).")
                } else {
                    message += " Process group still running after SIGKILL."
                    Logger.log(level: .warn, "Process group \(pgid) did not terminate even after SIGKILL (post-timeout).")
                }
            } else {
                 message += " Failed to send SIGKILL to PGID \(pgid) (post-timeout)."
                 Logger.log(level: .error, "Failed to send SIGKILL to PGID \(pgid) (post-timeout).")
            }
        }
        return killSuccess
    }
} 