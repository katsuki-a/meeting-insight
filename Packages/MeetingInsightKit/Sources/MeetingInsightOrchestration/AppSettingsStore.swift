import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var activeScopeID: UUID?
    public var codexExecutablePath: String?
    public var hasAcknowledgedPrivacy: Bool

    public init(
        activeScopeID: UUID? = nil,
        codexExecutablePath: String? = nil,
        hasAcknowledgedPrivacy: Bool = false
    ) {
        self.activeScopeID = activeScopeID
        self.codexExecutablePath = codexExecutablePath
        self.hasAcknowledgedPrivacy = hasAcknowledgedPrivacy
    }
}

public actor AppSettingsStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return AppSettings() }
        return try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: fileURL, options: [.atomic])
    }
}
