import Foundation
import XCTest
@testable import MeetingInsightDomain

final class DomainContractsTests: XCTestCase {
    func testResearchScopeRoundTrips() throws {
        let scope = makeScope()
        let data = try JSONEncoder().encode(scope)

        XCTAssertEqual(try JSONDecoder().decode(ResearchScope.self, from: data), scope)
    }

    func testInvestigationRequestAndSnapshotsRoundTrip() throws {
        let scope = makeScope()
        let capturedAt = Date(timeIntervalSince1970: 1_786_512_345)
        let request = InvestigationRequest(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000010")!,
            scopeID: scope.id,
            trigger: .manualText,
            spokenQuestion: "Feature A is available to free accounts?",
            contextBefore: ["We are reviewing the plan gate."],
            entities: ["Feature A"],
            repositories: [
                RepoSnapshot(
                    root: scope.repositories[0],
                    commitSHA: "0123456789abcdef0123456789abcdef01234567",
                    branch: "main",
                    isDirty: false,
                    capturedAt: capturedAt
                )
            ],
            knowledge: [
                KnowledgeSnapshot(
                    root: scope.knowledgeRoots[0],
                    revision: "f5f863ec34d1932dd2559cf8332808c4e0c27e50ad49fe3bc7b640eba21e7a4a",
                    fileCount: 3,
                    capturedAt: capturedAt
                )
            ],
            deadline: .seconds(35),
            allowedSources: [.code, .test, .config, .git, .localWiki]
        )

        let data = try JSONEncoder().encode(request)

        XCTAssertEqual(try JSONDecoder().decode(InvestigationRequest.self, from: data), request)
    }

    private func makeScope() -> ResearchScope {
        ResearchScope(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000020")!,
            name: "Demo Product",
            repositories: [
                RepositoryRoot(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000000021")!,
                    displayName: "DemoRepo",
                    rootPath: "/synthetic/DemoRepo",
                    aliases: ["demo"],
                    environmentLabel: "local-main"
                )
            ],
            knowledgeRoots: [
                KnowledgeRoot(
                    id: UUID(uuidString: "00000000-0000-4000-8000-000000000022")!,
                    displayName: "DemoWiki",
                    rootPath: "/synthetic/DemoWiki",
                    kind: .llmWiki,
                    includePatterns: ["**/*.md"],
                    excludePatterns: [".env*"]
                )
            ],
            sourcePolicy: SourcePolicy(
                allowedSources: [.code, .test, .config, .git, .localWiki],
                sourcePriority: [.code, .test, .config, .git, .localWiki]
            )
        )
    }
}
