import Foundation

extension String {
    func sanitizedForFileName() -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return components(separatedBy: invalidChars).joined(separator: "_")
    }
}
