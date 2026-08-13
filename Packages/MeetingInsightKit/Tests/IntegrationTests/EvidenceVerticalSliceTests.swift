import Foundation
import MeetingInsightDomain
import MeetingInsightOrchestration
import MeetingInsightResearch
import XCTest

final class EvidenceVerticalSliceTests: XCTestCase {
    func testFakeEngineRunsAllDemoQuestionsThroughSnapshotAndValidation() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let engine = try FixtureAgentEngine(fixtureRootURL: repositoryRoot())
        let pipeline = InvestigationPipeline(agentEngine: engine)
        let firstScenario = try XCTUnwrap(fixture.scenarios().first)
        let prepared = try await pipeline.prepare(
            scope: fixture.scope,
            question: firstScenario.spokenQuestion,
            requestID: firstScenario.requestID
        )
        XCTAssertEqual(prepared.request.repositories.first?.commitSHA, "dff70ec90a888327b71dfd07db0ece964ab7d56a")
        XCTAssertEqual(prepared.knowledgeExcerpts.map(\.relativePath), ["features/feature-a.md"])
        XCTAssertFalse(
            prepared.knowledgeExcerpts.contains { $0.relativePath.contains(fixture.knowledgeURL.path) }
        )

        for scenario in try fixture.scenarios() {
            let insight = try await pipeline.investigate(
                scope: fixture.scope,
                question: scenario.spokenQuestion,
                context: "Synthetic meeting context",
                requestID: scenario.requestID
            )

            XCTAssertEqual(insight.effectiveVerdict, scenario.expectedVerdict, scenario.id)
            XCTAssertEqual(
                Set(insight.validatedEvidence.map(\.reference.path)),
                Set(scenario.requiredEvidencePaths),
                scenario.id
            )
            XCTAssertEqual(insight.citationIntegrity, 1, scenario.id)
        }
    }

    func testCodeWinsWhenWikiDescriptionIsStale() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let scenario = try XCTUnwrap(
            fixture.scenarios().first { $0.id == "feature-a-free-plan" }
        )
        let pipeline = InvestigationPipeline(
            agentEngine: try FixtureAgentEngine(fixtureRootURL: repositoryRoot())
        )

        let insight = try await pipeline.investigate(
            scope: fixture.scope,
            question: scenario.spokenQuestion,
            requestID: scenario.requestID
        )

        XCTAssertEqual(insight.effectiveVerdict, .contradicted)
        XCTAssertEqual(insight.card.claims.first?.evidence.first?.sourceType, .code)
        XCTAssertTrue(insight.validatedEvidence.contains { $0.reference.sourceType == .localWiki })
    }

    func testRealCodexVerticalSliceIsExplicitlyOptIn() async throws {
        guard ProcessInfo.processInfo.environment["MEETING_INSIGHT_RUN_CODEX_INTEGRATION"] == "1" else {
            throw XCTSkip("Set MEETING_INSIGHT_RUN_CODEX_INTEGRATION=1 to run the live Codex check")
        }
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let executable = try CodexExecutableResolver().resolve(explicitPath: nil)
        let engine = CodexAgentEngine(
            executableURL: executable,
            schemaURL: try InsightCardSchema.url()
        )
        let scenario = try XCTUnwrap(fixture.scenarios().first)
        let insight = try await InvestigationPipeline(agentEngine: engine).investigate(
            scope: fixture.scope,
            question: scenario.spokenQuestion,
            requestID: scenario.requestID
        )
        XCTAssertEqual(insight.citationIntegrity, 1)
    }
}
