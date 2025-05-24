import Foundation

// MARK: - Global Logger (SDD 3.2.7)
struct Logger {
    private static var currentLogLevel: AppConfig.LogLevel = .info // Assuming AppConfig.LogLevel is accessible or moved too
    private static var logFileURL: URL? = nil
    private static let fileHandleQueue = DispatchQueue(label: "com.steipete.terminator.logFileQueue")
    private static var fileHandle: FileHandle? = nil

    static func configure(level: AppConfig.LogLevel, directory: URL) {
        currentLogLevel = level
        logFileURL = directory.appendingPathComponent("terminator_cli.log")
        
        fileHandleQueue.async {
            if let path = logFileURL?.path {
                if !FileManager.default.fileExists(atPath: path) {
                    FileManager.default.createFile(atPath: path, contents: nil, attributes: nil)
                }
                do {
                    fileHandle = try FileHandle(forWritingTo: logFileURL!)
                    fileHandle?.seekToEndOfFile() // Append to existing log
                } catch {
                    fputs("Error: Could not open log file \(path) for writing. Error: \(error.localizedDescription)\n", stderr)
                    fileHandle = nil // Ensure it's nil if open failed
                }
            } else {
                 fputs("Error: Log file URL is nil during configuration.\n", stderr)
            }
        }
        // Avoid logging from within configure itself if it depends on AppConfig being fully set up,
        // or ensure this specific log call is safe.
        // Logger.log(level: .info, "Logger configured. Level: \(level.rawValue), Path: \(logFileURL?.path ?? "N/A")")
        // This initial log can be done after AppConfig is fully initialized and Logger.configure is called from outside.
    }
    
    static func shutdown() {
        // Log shutdown initiation if possible (might be tricky if logger itself is what's shutting down)
        // Logger.log(level: .debug, "Logger shutting down. Closing file handle.") 
        // Consider fputs for this specific message if regular log path is compromised during shutdown
        fputs("[\(timestamp()) DEBUG] Logger shutting down. Closing file handle.\n", stdout) // Or stderr

        fileHandleQueue.sync { // Ensure all pending writes are done
            do {
                try fileHandle?.synchronize()
                try fileHandle?.close()
            } catch {
                fputs("Error closing log file: \(error.localizedDescription)\n", stderr)
            }
            fileHandle = nil
        }
    }

    static func log(level: AppConfig.LogLevel, _ messageToLog: @autoclosure () -> String, file: String = #file, line: Int = #line, function: String = #function) {
        guard level.intValue >= currentLogLevel.intValue else { return }
        
        let message = messageToLog() // Evaluate the autoclosure only if log level is met
        let fileName = (file as NSString).lastPathComponent
        let logEntry = "[\(timestamp()) \(level.rawValue.uppercased()) \(fileName):\(line) \(function)] \(message)\n"
        
        // Print to stdout (or stderr for errors) regardless of file logging success
        if level.intValue >= AppConfig.LogLevel.error.intValue {
            fputs(logEntry, stderr)
        } else {
            fputs(logEntry, stdout)
        }

        fileHandleQueue.async {
            if let handle = fileHandle, let data = logEntry.data(using: .utf8) {
                do {
                    try handle.write(contentsOf: data)
                } catch {
                    // Avoid recursive logging
                    fputs("Critical Error: Could not write to log file. Error: \(error.localizedDescription). Original message: \(logEntry)", stderr)
                }
            } else if logFileURL != nil && fileHandle == nil {
                 // Log file was intended but not opened (e.g. permissions)
                 // This situation should be flagged during configure or first write attempt if possible
                 // fputs("Warning: Log file handle is nil. Message not written to file: \(logEntry)", stderr)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds] // Match common log formats like Zerolog
        return formatter.string(from: Date())
    }
} 