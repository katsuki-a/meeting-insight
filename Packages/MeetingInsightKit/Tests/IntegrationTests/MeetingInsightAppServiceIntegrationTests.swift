import Foundation
import MeetingInsightOrchestration
import XCTest

final class MeetingInsightAppServiceIntegrationTests: XCTestCase {
    func testAppServiceUsesEvidenceVerticalSliceAndReturnsValidatedPresentation() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let scenario = try XCTUnwrap(fixture.scenarios().first)
        let configuration = MeetingInsightAppService.Configuration(
            scopesFileURL: fixture.temporaryRoot.appendingPathComponent("scopes.json"),
            settingsFileURL: fixture.temporaryRoot.appendingPathComponent("settings.json"),
            fixtureRootURL: repositoryRoot()
        )
        let service = MeetingInsightAppService(configuration: configuration)
        let bootstrap = try await service.saveScope(
            ResearchScopeDraft(
                id: fixture.scope.id,
                name: fixture.scope.name,
                repositories: fixture.scope.repositories.map {
                    RepositoryDraft(
                        id: $0.id,
                        displayName: $0.displayName,
                        rootPath: $0.rootPath,
                        aliases: $0.aliases,
                        environmentLabel: $0.environmentLabel
                    )
                },
                knowledge: fixture.scope.knowledgeRoots.map {
                    KnowledgeDraft(
                        id: $0.id,
                        displayName: $0.displayName,
                        rootPath: $0.rootPath,
                        kind: $0.kind,
                        includePatterns: $0.includePatterns,
                        excludePatterns: $0.excludePatterns
                    )
                }
            )
        )
        let scopeID = try XCTUnwrap(bootstrap.scopes.first?.id)

        let presentation = try await service.investigate(
            scopeID: scopeID,
            question: scenario.spokenQuestion,
            requestID: scenario.requestID
        )

        XCTAssertEqual(presentation.requestID, scenario.requestID)
        XCTAssertEqual(presentation.verdict, scenario.expectedVerdict.rawValue)
        XCTAssertEqual(
            Set(presentation.evidence.map(\.path)),
            Set(scenario.requiredEvidencePaths)
        )
        XCTAssertEqual(presentation.scope, "DemoRepo@dff70ec9")
    }
}
