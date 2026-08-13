import Foundation
import MeetingInsightDomain
@testable import MeetingInsightRepository
import XCTest

final class ResearchScopeStoreTests: XCTestCase {
    func testPersistsAndUpdatesNamedScopes() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let file = temporary.url.appendingPathComponent("scopes.json")
        let store = ResearchScopeStore(fileURL: file)
        let scopeID = UUID()
        let original = makeScope(id: scopeID, name: "Original")
        let updated = makeScope(id: scopeID, name: "Updated")

        try await store.save(original)
        try await store.save(updated)

        let savedScopes = try await store.scopes()
        let reloadedScope = try await ResearchScopeStore(fileURL: file).scope(idOrName: "Updated")
        XCTAssertEqual(savedScopes, [updated])
        XCTAssertEqual(reloadedScope, updated)
    }

    func testRejectsScopeOutsideSupportedRootCounts() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let store = ResearchScopeStore(fileURL: temporary.url.appendingPathComponent("scopes.json"))
        let invalid = ResearchScope(
            id: UUID(),
            name: "No repositories",
            repositories: [],
            knowledgeRoots: [],
            sourcePolicy: SourcePolicy(allowedSources: [.code], sourcePriority: [.code])
        )

        await XCTAssertThrowsErrorAsync(try await store.save(invalid)) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidScope("repository count must be between 1 and 3"))
        }
    }

    private func makeScope(id: UUID, name: String) -> ResearchScope {
        ResearchScope(
            id: id,
            name: name,
            repositories: [repositoryRoot(path: "/tmp/demo")],
            knowledgeRoots: [],
            sourcePolicy: SourcePolicy(allowedSources: [.code], sourcePriority: [.code])
        )
    }
}
