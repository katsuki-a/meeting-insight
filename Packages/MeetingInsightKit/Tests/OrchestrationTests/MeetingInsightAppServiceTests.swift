import Foundation
import MeetingInsightOrchestration
import XCTest

final class MeetingInsightAppServiceTests: XCTestCase {
    func testScopeAndOnboardingStatePersistAcrossServiceInstances() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-insight-app-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let configuration = MeetingInsightAppService.Configuration(
            scopesFileURL: temporary.appendingPathComponent("scopes.json"),
            settingsFileURL: temporary.appendingPathComponent("settings.json")
        )
        let service = MeetingInsightAppService(configuration: configuration)
        let bootstrap = try await service.saveScope(
            ResearchScopeDraft(
                name: "Product A",
                repositories: [
                    RepositoryDraft(
                        displayName: "product-a",
                        rootPath: "/tmp/product-a",
                        aliases: ["Product A"],
                        environmentLabel: "local-head"
                    )
                ],
                knowledge: [
                    KnowledgeDraft(
                        displayName: "Product A Wiki",
                        rootPath: "/tmp/product-a-wiki"
                    )
                ]
            )
        )
        let scopeID = try XCTUnwrap(bootstrap.scopes.first?.id)
        try await service.selectActiveScope(scopeID)
        try await service.acknowledgePrivacy()

        let reloaded = try await MeetingInsightAppService(configuration: configuration).bootstrap()

        XCTAssertEqual(reloaded.activeScopeID, scopeID)
        XCTAssertTrue(reloaded.hasAcknowledgedPrivacy)
        XCTAssertEqual(reloaded.scopes.first?.repositories.map(\.name), ["product-a"])
        XCTAssertEqual(reloaded.scopes.first?.knowledge.map(\.name), ["Product A Wiki"])
    }
}
