import Foundation
import MeetingInsightCapture
import MeetingInsightOrchestration
@testable import MeetingInsight
import XCTest

@MainActor
final class MeetingInsightAppTests: XCTestCase {
    func testApplicationLaunchSchedulesMainWindowActivation() async {
        let activated = expectation(description: "main window activated")
        var requestedActivationPolicy: NSApplication.ActivationPolicy?
        var activationAttempts = 0
        let delegate = MeetingInsightApplicationDelegate(
            setActivationPolicy: { requestedActivationPolicy = $0 },
            retryDelay: .zero,
            activateMainWindow: {
                activationAttempts += 1
                guard activationAttempts == 3 else { return false }
                activated.fulfill()
                return true
            }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )
        await fulfillment(of: [activated], timeout: 1)
        XCTAssertEqual(requestedActivationPolicy, .regular)
        XCTAssertEqual(activationAttempts, 3)
    }

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

    func testCaptureStartRemainsResponsiveAndStopReleasesService() async throws {
        let scope = AppScopeSummary.fixture
        let captureService = FakeCaptureService()
        let model = AppModel(
            service: FakeAppService(
                bootstrap: AppBootstrap(
                    scopes: [scope],
                    activeScopeID: scope.id,
                    hasAcknowledgedPrivacy: true,
                    codexExecutablePath: nil
                )
            ),
            captureService: captureService
        )
        model.load()
        try await waitUntil { model.hasAcknowledgedPrivacy }

        model.refreshCaptureApplications()
        try await waitUntil { model.captureApplications.count == 1 }
        model.selectedCaptureApplicationID = model.captureApplications[0].id
        model.startAudioCapture()
        try await waitUntil { model.captureState == .capturing }
        model.question = "Main actor remains responsive during capture"
        XCTAssertEqual(model.question, "Main actor remains responsive during capture")
        await captureService.emit(
            .meter(
                CaptureMeterSample(
                    source: .microphone,
                    level: PCMMeterLevel(peak: 0.8, rootMeanSquare: 0.4),
                    presentationTime: 1,
                    frameCount: 480
                )
            )
        )
        try await waitUntil { model.microphoneMeter.rootMeanSquare == 0.4 }

        model.stopAudioCapture()
        try await waitUntil { model.captureState == .idle }
        let stopCount = await captureService.stopCount
        XCTAssertEqual(stopCount, 1)
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

private actor FakeCaptureService: AudioCaptureServicing {
    private(set) var isCapturing = false
    private(set) var stopCount = 0
    private var continuation: AsyncStream<CaptureEvent>.Continuation?

    func applications() async throws -> [CaptureApplication] {
        [
            CaptureApplication(
                processID: 42,
                bundleIdentifier: "synthetic.meeting",
                applicationName: "Synthetic Meeting"
            )
        ]
    }

    func start(applicationID: CaptureApplication.ID) async throws -> AsyncStream<CaptureEvent> {
        XCTAssertEqual(applicationID, 42)
        isCapturing = true
        let pair = AsyncStream<CaptureEvent>.makeStream()
        continuation = pair.continuation
        return pair.stream
    }

    func stop() async {
        isCapturing = false
        stopCount += 1
        continuation?.yield(.stopped)
        continuation?.finish()
        continuation = nil
    }

    func emit(_ event: CaptureEvent) {
        continuation?.yield(event)
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
