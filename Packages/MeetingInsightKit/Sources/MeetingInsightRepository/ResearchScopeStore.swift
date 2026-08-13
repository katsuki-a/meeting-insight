import Foundation
import MeetingInsightDomain

public actor ResearchScopeStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func scopes() throws -> [ResearchScope] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([ResearchScope].self, from: data)
    }

    public func scope(idOrName value: String) throws -> ResearchScope? {
        let existing = try scopes()
        if let id = UUID(uuidString: value), let match = existing.first(where: { $0.id == id }) {
            return match
        }
        return existing.first {
            $0.name.compare(value, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    public func save(_ scope: ResearchScope) throws {
        try validate(scope)
        var existing = try scopes()
        if let index = existing.firstIndex(where: { $0.id == scope.id }) {
            existing[index] = scope
        } else {
            existing.append(scope)
        }
        try write(existing)
    }

    public func delete(id: UUID) throws {
        let filtered = try scopes().filter { $0.id != id }
        try write(filtered)
    }

    private func validate(_ scope: ResearchScope) throws {
        guard !scope.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RepositoryError.invalidScope("name must not be empty")
        }
        guard (1...3).contains(scope.repositories.count) else {
            throw RepositoryError.invalidScope("repository count must be between 1 and 3")
        }
        guard (0...3).contains(scope.knowledgeRoots.count) else {
            throw RepositoryError.invalidScope("knowledge root count must be between 0 and 3")
        }
        guard Set(scope.repositories.map(\.id)).count == scope.repositories.count else {
            throw RepositoryError.invalidScope("repository IDs must be unique")
        }
        guard Set(scope.knowledgeRoots.map(\.id)).count == scope.knowledgeRoots.count else {
            throw RepositoryError.invalidScope("knowledge root IDs must be unique")
        }
    }

    private func write(_ scopes: [ResearchScope]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(scopes).write(to: fileURL, options: [.atomic])
    }
}
