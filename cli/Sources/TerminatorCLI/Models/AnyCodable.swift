import Foundation

// Helper to allow mixed types in JSON for active_configuration and managed_sessions
struct AnyCodable: Codable {
    private let value: Any

    var stringValue: String? {
        value as? String
    }

    var intValue: Int? {
        value as? Int
    }

    var boolValue: Bool? {
        value as? Bool
    }

    var doubleValue: Double? {
        value as? Double
    }

    init(_ value: (some Any)?) {
        self.value = value ?? ()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let string as String: try container.encode(string)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let array as [Any?]: try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any?]: try container.encode(dictionary.mapValues { AnyCodable($0) })
        // Handle NSNull for nil values from dictionaries explicitly if necessary, though Any? should cover it.
        case is NSNull: try container.encodeNil() // Ensure NSNull is encoded as nil
        case Optional<Any>.none: try container.encodeNil() // Explicitly handle Optional.none
        default:
            // Attempt to encode if it's one of the known Codable primitive types, otherwise nil
            // This part is tricky and might need more robust type checking or be limited
            // For safety, if it's not a directly encodable type, encode nil.
            // Consider logging a warning here if a type is not handled as expected.
            // fputs("Warning: AnyCodable encountered a type it cannot directly encode: \(type(of: value))\n", stderr)
            try container.encodeNil()
        }
    }

    // Add a basic init(from decoder: Decoder) to make it fully Codable, though its primary use here is encoding.
    // A full decoding implementation for AnyCodable is complex and might not be needed if only used for InfoOutput.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyCodable value cannot be decoded"
            )
        }
    }
}
