import Foundation

public enum InsightCardSchema {
    public static let version = 1

    public static func data() throws -> Data {
        guard let url = Bundle.module.url(
            forResource: "insight-card.schema",
            withExtension: "json"
        ) else {
            throw InsightCardSchemaError.resourceMissing
        }
        return try Data(contentsOf: url)
    }
}

public enum InsightCardSchemaError: Error, Equatable, Sendable {
    case resourceMissing
}

public enum InsightCardCoding {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
