import Foundation

struct AnyCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    func strictContainer<Key>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> where Key: CodingKey & CaseIterable {
        let rawContainer = try container(keyedBy: AnyCodingKey.self)
        let allowedKeys = Set(Key.allCases.map(\.stringValue))

        if let unknownKey = rawContainer.allKeys.first(where: { !allowedKeys.contains($0.stringValue) }) {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath + [unknownKey],
                    debugDescription: "Unknown field: \(unknownKey.stringValue)"
                )
            )
        }

        return try container(keyedBy: type)
    }
}

enum ContractValidation {
    static func require(
        _ condition: @autoclosure () -> Bool,
        codingPath: [any CodingKey],
        description: String
    ) throws {
        guard condition() else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: codingPath, debugDescription: description)
            )
        }
    }

    static func requireString(
        _ value: String,
        minimum: Int = 1,
        maximum: Int? = nil,
        codingPath: [any CodingKey]
    ) throws {
        try require(
            value.count >= minimum,
            codingPath: codingPath,
            description: "String must contain at least \(minimum) character(s)"
        )
        if let maximum {
            try require(
                value.count <= maximum,
                codingPath: codingPath,
                description: "String must contain no more than \(maximum) characters"
            )
        }
    }

    static func requireHex(
        _ value: String,
        lengths: ClosedRange<Int>,
        codingPath: [any CodingKey]
    ) throws {
        let isHex = value.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
        try require(
            lengths.contains(value.utf8.count) && isHex,
            codingPath: codingPath,
            description: "Value must be hexadecimal with length \(lengths.lowerBound)...\(lengths.upperBound)"
        )
    }
}
