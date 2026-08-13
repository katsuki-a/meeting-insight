import Foundation
import MeetingInsightOrchestration
@testable import MeetingInsight
import XCTest

@MainActor
final class MeetingInsightAppTests: XCTestCase {
    func testLoadShowsActiveScopeSourcesAndPrivacyBoundary() async throws {
        let scope = AppScopeSummary.fixture
        let service = FakeAppService(
            bootstrap: AppBootstrap(
                scopes: [scope],
                activeScopeID: scope.id,
                hasAcknowledgedPrivacy: false,
                codexExecutablePath: nil
            )
        )
        let model = AppModel(service: service)

        model.load()
        try await waitUntil { model.activeScope?.id == scope.id }

        XCTAssertEqual(model.activeScope?.repositories.map(\.name), ["DemoRepo"])
        XCTAssertEqual(model.activeScope?.knowledge.map(\.name), ["DemoWiki"])
        XCTAssertFalse(model.hasAcknowledgedPrivacy)
    }

    func testInvestigationReturnsImmediatelyAndDisplaysValidatedPresentation() async throws {
        let scope = AppScopeSummary.fixture
        let service = FakeAppService(
            bootstrap: AppBootstrap(
                scopes: [scope],
                activeScopeID: scope.id,
                hasAcknowledgedPrivacy: true,
                codexExecutablePath: nil
            )
        )
        let model = AppModel(service: service)
        model.load()
        try await waitUntil { model.activeScope != nil }
        model.question = "Feature Aの条件は？"

        model.investigate()
        XCTAssertEqual(model.sessionState, .investigating)
        model.question = "Main actor remains responsive"
        XCTAssertEqual(model.question, "Main actor remains responsive")

        try await waitUntil { await service.hasPendingInvestigation }
        await service.completeInvestigation(with: .fixture)
        try await waitUntil { model.insight != nil }
        XCTAssertEqual(model.insight, .fixture)
        XCTAssertEqual(model.sessionState, .idle)
    }

    func testCancelForwardsRequestAndClearsInvestigatingState() async throws {
        let scope = AppScopeSummary.fixture
        let service = FakeAppService(
            bootstrap: AppBootstrap(
                scopes: [scope],
                activeScopeID: scope.id,
                hasAcknowledgedPrivacy: true,
                codexExecutablePath: nil
            )
        )
        let model = AppModel(service: service)
        model.load()
        try await waitUntil { model.activeScope != nil }
        model.question = "cancel me"
        model.investigate()
        let requestID = try XCTUnwrap(model.activeRequestID)

        model.cancelInvestigation()
        try await waitUntil { await service.cancelledRequestIDs.contains(requestID) }

        XCTAssertEqual(model.sessionState, .idle)
        XCTAssertNil(model.activeRequestID)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition was not met")
    }
}

private actor FakeAppService: MeetingInsightAppServicing {
    private let initialBootstrap: AppBootstrap
    private var investigationContinuation: CheckedContinuation<AppInsightPresentation, Error>?
    private(set) var cancelledRequestIDs: Set<UUID> = []

    var hasPendingInvestigation: Bool { investigationContinuation != nil }

    init(bootstrap: AppBootstrap) {
        initialBootstrap = bootstrap
    }

    func bootstrap() async throws -> AppBootstrap { initialBootstrap }

    func saveScope(_ draft: ResearchScopeDraft) async throws -> AppBootstrap { initialBootstrap }

    func selectActiveScope(_ id: UUID?) async throws {}

    func acknowledgePrivacy() async throws {}

    func doctor() async -> AppDoctorPresentation {
        AppDoctorPresentation(version: "fixture", authentication: "authenticated", issues: [])
    }

    func investigate(
        scopeID: UUID,
        question: String,
        requestID: UUID
    ) async throws -> AppInsightPresentation {
        try await withCheckedThrowingContinuation { continuation in
            investigationContinuation = continuation
        }
    }

    func cancel(requestID: UUID) async {
        cancelledRequestIDs.insert(requestID)
        investigationContinuation?.resume(throwing: CancellationError())
        investigationContinuation = nil
    }

    func completeInvestigation(with insight: AppInsightPresentation) {
        investigationContinuation?.resume(returning: insight)
        investigationContinuation = nil
    }
}

private extension AppScopeSummary {
    static let fixture = AppScopeSummary(
        id: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!,
        name: "Demo Product",
        repositories: [AppSourceSummary(name: "DemoRepo", detail: "synthetic-main")],
        knowledge: [AppSourceSummary(name: "DemoWiki", detail: "llm_wiki")]
    )
}

private extension AppInsightPresentation {
    static let fixture = AppInsightPresentation(
        requestID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        verdict: "verified",
        headline: "Feature Aの条件は実装と一致",
        answer: "有料プランかつflag有効時に利用できます。",
        confidence: 0.9,
        scope: "DemoRepo@dff70ec",
        evidence: [
            AppEvidencePresentation(
                path: "Sources/DemoApp/FeatureAccessPolicy.swift",
                lineStart: 10,
                lineEnd: 15,
                revision: "dff70ec90a888327b71dfd07db0ece964ab7d56a"
            )
        ]
    )
}
