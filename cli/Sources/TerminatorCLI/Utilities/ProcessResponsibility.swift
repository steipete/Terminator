import CResponsibility
import Foundation

/// Utilities for managing process responsibility on macOS
///
/// This implements the undocumented but widely-used `responsibility_spawnattrs_setdisclaim` API
/// to ensure that permission dialogs appear correctly when running through process chains.
///
/// ## Background
/// macOS uses the concept of a "responsible process" to determine which app name appears in
/// permission dialogs. When processes spawn other processes, the responsible process is
/// typically inherited from the parent. This can cause issues when running through chains
/// like Claude → Node.js → Swift CLI, where the permission dialog may not appear or may
/// show the wrong app name.
///
/// ## References
/// - The Curious Case of the Responsible Process: https://www.qt.io/blog/the-curious-case-of-the-responsible-process
/// - LLVM Implementation: https://github.com/llvm/llvm-project/commit/041c7b84a4b925476d1e21ed302786033bb6035f
/// - Chromium Implementation: https://chromium.googlesource.com/chromium/src/+/lkgr/base/process/launch_mac.cc
enum ProcessResponsibility {
    /// The flag value for disclaiming responsibility (same as POSIX_SPAWN_SETDISCLAIM)
    private static let disclaimFlag: Int32 = 1

    /// Attempt to disclaim parent responsibility for the current process
    /// This ensures that Apple Events permission dialogs appear correctly
    static func disclaimParentResponsibility() {
        // Check if we should skip responsibility disclaiming (for tests)
        if ProcessInfo.processInfo.environment["TERMINATOR_SKIP_RESPONSIBILITY"] != nil {
            Logger.log(
                level: .debug,
                "Skipping process responsibility disclaiming (TERMINATOR_SKIP_RESPONSIBILITY set)"
            )
            return
        }

        // Check if we're already running as a self-responsible process
        guard ProcessInfo.processInfo.environment["TERMINATOR_SELF_RESPONSIBLE"] == nil else {
            Logger.log(level: .info, "Already running as self-responsible process (PID: \(getpid()))")
            return
        }

        Logger.log(level: .info, "Attempting to re-spawn as self-responsible process (current PID: \(getpid()))")

        // Get the current executable path
        let executablePath = CommandLine.arguments[0]
        var arguments = CommandLine.arguments
        arguments[0] = executablePath

        // Set environment to indicate we're self-responsible
        var environment = ProcessInfo.processInfo.environment
        environment["TERMINATOR_SELF_RESPONSIBLE"] = "1"

        // Prepare spawn attributes
        var attr: posix_spawnattr_t?
        var result = posix_spawnattr_init(&attr)
        guard result == 0 else {
            let error = String(cString: strerror(result))
            Logger.log(level: .error, "Failed to initialize spawn attributes: \(error)")
            return
        }
        defer { posix_spawnattr_destroy(&attr) }

        // Set the responsibility disclaimer flag
        // This is the key part - it makes the spawned process responsible for itself
        #if os(macOS)
            if #available(macOS 10.14, *) {
                withUnsafeMutablePointer(to: &attr) { attrPtr in
                    result = terminator_spawnattr_setdisclaim(attrPtr, disclaimFlag)
                }

                if result != 0 {
                    // This is not fatal - we can still continue without disclaiming
                    Logger.log(
                        level: .warn,
                        "Failed to set responsibility disclaimer flag (error: \(result)). Continuing without disclaimer."
                    )
                }
            } else {
                Logger.log(level: .info, "Responsibility disclaimer requires macOS 10.14+, skipping")
            }
        #endif

        // Convert arguments for posix_spawn
        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        // Convert environment for posix_spawn
        let envp: [UnsafeMutablePointer<CChar>?] = environment.map { key, value in
            strdup("\(key)=\(value)")
        } + [nil]
        defer { envp.forEach { free($0) } }

        // Spawn ourselves with disclaimed responsibility
        var pid: pid_t = 0
        result = posix_spawn(&pid, executablePath, nil, &attr, argv, envp)

        if result == 0 {
            Logger.log(level: .info, "Successfully spawned self-responsible process with PID: \(pid)")
            Logger.log(
                level: .debug,
                "Parent process (PID: \(getpid())) exiting to hand over to self-responsible child"
            )

            // Flush logger before exiting
            Logger.shutdown()

            // Exit the current process since we've spawned a new one
            exit(0)
        } else {
            let error = String(cString: strerror(result))
            Logger.log(level: .error, "Failed to spawn self-responsible process: \(error) (errno: \(result))")
            Logger.log(
                level: .info,
                "Continuing without responsibility disclaimer - permission dialogs may not appear correctly"
            )
        }
    }
}
