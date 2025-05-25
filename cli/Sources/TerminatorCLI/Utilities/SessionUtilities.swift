import CryptoKit // Required for SHA256
import Foundation

// Constants related to session identification and naming
enum SessionConstants {
    // Prefix for iTerm2 session GUIDs when stored in comments or metadata
    static let iTermSessionGuidPrefix = "ITERM_SESSION_GUID:"
    // Prefix for iTerm2 session tags embedded in session names for easier parsing
    static let iTermSessionTagPrefix = "[tag:"
    // Prefix for project path hashes used in default tag generation
    static let projectHashPrefix = "project@"
}

enum SessionUtilities {
    static let noProjectIdentifier = "NO_PROJECT" // SDD 3.2.4
    static let sessionPrefix = "::TERMINATOR_SESSION::"

    struct ParsedTitleInfo {
        let projectHash: String?
        let tag: String?
        let ttyPath: String? // Decoded TTY path from title
        let pid: pid_t? // PID from title
    }

    static func parseSessionTitle(title: String) -> ParsedTitleInfo? {
        Logger.log(level: .debug, "Parsing session title: \(title)")
        guard title.hasPrefix(sessionPrefix) else {
            return nil
        }

        var projectHash: String?
        var tag: String?
        var ttyPath: String?
        var pid: pid_t?

        let trimmedTitle = title.hasPrefix(sessionPrefix) ? String(title.dropFirst(sessionPrefix.count)) : title
        let components = trimmedTitle.split(separator: "::").filter { !$0.isEmpty }

        for component in components {
            let parts = component.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0]
                var value = parts[1]

                // General URL decoding for values that might need it.
                // Specifically TAG and TTY_PATH were encoded.
                if key == "TAG" || key == "TTY_PATH" {
                    value = value.removingPercentEncoding ?? value
                }

                switch key {
                case "PROJECT_HASH":
                    projectHash = (value == noProjectIdentifier) ? nil : value
                case "TAG":
                    tag = value
                case "TTY_PATH":
                    ttyPath = value
                case "PID":
                    if let intValue = Int32(value) {
                        pid = intValue
                    }
                default:
                    break // Ignore unknown keys
                }
            }
        }

        // A valid session title must at least have a tag for our purposes.
        // Project hash can be nil (NO_PROJECT).
        guard tag != nil else {
            Logger.log(level: .debug, "Parsed title missing TAG component.")
            return nil
        }

        Logger.log(
            level: .debug,
            "Parsed title - Project Hash: \(projectHash ?? "nil"), Tag: \(tag ?? "nil"), TTY: \(ttyPath ?? "nil"), PID: \(pid != nil ? String(pid!) : "nil")"
        )
        return ParsedTitleInfo(projectHash: projectHash, tag: tag, ttyPath: ttyPath, pid: pid)
    }

    static func generateProjectHash(projectPath: String?) -> String {
        guard let projPath = projectPath, !projPath.isEmpty else {
            return noProjectIdentifier
        }
        if let data = projPath.data(using: .utf8) {
            let hashed = SHA256.hash(data: data)
            return hashed.compactMap { String(format: "%02x", $0) }.joined()
        }
        Logger.log(
            level: .warn,
            "Failed to generate SHA256 hash for project path: \(projPath). Using basename as fallback hash component."
        )
        let basename = (projPath as NSString).lastPathComponent
        return basename
            .isEmpty ? "PROJECT_HASH_GENERATION_FAILED" : "BASENAME_" +
            basename // Prefix to avoid collision with real hashes
    }

    static func generateSessionTitle(
        projectPath: String?,
        tag: String,
        ttyDevicePath: String?,
        processId: pid_t?
    ) -> String {
        let projectHashString = generateProjectHash(projectPath: projectPath)
        let projectHashComponent = "PROJECT_HASH=\(projectHashString)"

        // SDD 3.2.4: resolvedTag_urlEncoded. Using .urlQueryAllowed for broader character set support.
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? tag
        let tagComponent = "TAG=\(encodedTag)"

        var titleParts = [sessionPrefix, projectHashComponent, tagComponent]

        if let tty = ttyDevicePath, !tty.isEmpty {
            // SDD 3.2.4: ttyDevicePath_urlEncoded. .urlPathAllowed is suitable for file paths.
            let encodedTTY = tty.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tty
            titleParts.append("TTY_PATH=\(encodedTTY)")
        }
        if let pid = processId {
            titleParts.append("PID=\(pid)")
        }

        let title = titleParts
            .joined(separator: "::") + (titleParts.count > 1 ? "::" : "") // Ensure trailing :: if there are components

        Logger.log(level: .debug, "Generated session title: \(title)")
        return title
    }

    static func generateUserFriendlySessionIdentifier(projectPath: String?, tag: String) -> String {
        let projectName: String
        if let projPath = projectPath, !projPath.isEmpty {
            let baseName = (projPath as NSString).lastPathComponent
            if baseName.isEmpty { // Should not happen if projPath is not empty, but as a safeguard
                projectName = "UnnamedProject"
            } else {
                projectName = baseName
            }
        } else {
            projectName = "Global"
        }
        return "\(projectName): \(tag)"
    }
}
