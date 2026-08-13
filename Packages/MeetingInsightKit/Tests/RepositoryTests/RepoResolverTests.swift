import Foundation
import MeetingInsightDomain
@testable import MeetingInsightRepository
import XCTest

final class RepoResolverTests: XCTestCase {
    func testResolvesOneRepositoryByDisplayNameOrAlias() {
        let first = repositoryRoot(path: "/tmp/first", aliases: ["feature-a", "mobile"])
        let second = RepositoryRoot(
            id: UUID(),
            displayName: "Backend",
            rootPath: "/tmp/second",
            aliases: ["api"],
            environmentLabel: "test"
        )
        let scope = makeScope(repositories: [first, second])

        XCTAssertEqual(
            RepoResolver().resolvePrimaryRepository(in: scope, entities: ["Feature-A"]),
            .resolved(first)
        )
        XCTAssertEqual(
            RepoResolver().resolvePrimaryRepository(in: scope, entities: ["backend"]),
            .resolved(second)
        )
    }

    func testReturnsAmbiguousOrUnresolvedInsteadOfGuessing() {
        let first = repositoryRoot(path: "/tmp/first", aliases: ["shared"])
        let second = RepositoryRoot(
            id: UUID(),
            displayName: "Other",
            rootPath: "/tmp/second",
            aliases: ["shared"],
            environmentLabel: "test"
        )
        let scope = makeScope(repositories: [first, second])

        XCTAssertEqual(
            RepoResolver().resolvePrimaryRepository(in: scope, entities: ["shared"]),
            .ambiguous([first, second])
        )
        XCTAssertEqual(
            RepoResolver().resolvePrimaryRepository(in: scope, entities: ["unknown"]),
            .unresolved
        )
    }

    private func makeScope(repositories: [RepositoryRoot]) -> ResearchScope {
        ResearchScope(
            id: UUID(),
            name: "Fixture",
            repositories: repositories,
            knowledgeRoots: [],
            sourcePolicy: SourcePolicy(allowedSources: [.code], sourcePriority: [.code])
        )
    }
}
