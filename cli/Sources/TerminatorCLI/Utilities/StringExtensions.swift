import Foundation

extension String {
    func sanitizedForFileName() -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalidChars).joined(separator: "_")
    }

    func escapedForShell() -> String {
        // Escape single quotes by replacing ' with '\''
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
