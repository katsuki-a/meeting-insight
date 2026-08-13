import Foundation
import MeetingInsightDomain
import MeetingInsightOrchestration
import MeetingInsightRepository
import MeetingInsightResearch
import XCTest

final class MeetingInsightCLIApplicationIntegrationTests: XCTestCase {
    func testAllVerticalSliceCommandsUseTheSameScopedPipeline() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let scopesURL = fixture.temporaryRoot.appendingPathComponent("scopes.json")
        try await ResearchScopeStore(fileURL: scopesURL).save(fixture.scope)
        let engine = try FixtureAgentEngine(fixtureRootURL: repositoryRoot())
        let app = MeetingInsightCLIApplication(
            configuration: CLIConfiguration(scopesFileURL: scopesURL),
            agentEngine: engine,
            resolveExecutable: { _ in URL(fileURLWithPath: "/tmp/codex") },
            inspectExecutable: { executable in
                CodexDoctorReport(
                    executablePath: executable.path,
                    version: "codex-cli fixture",
                    authentication: .authenticated,
                    issues: []
                )
            }
        )

        let doctor = await app.execute(arguments: ["doctor", "--json"])
        XCTAssertEqual(doctor.exitCode, 0)
        XCTAssertTrue(doctor.standardOutput.contains("codex-cli fixture"))

        let list = await app.execute(arguments: ["scope", "list", "--json"])
        XCTAssertEqual(list.exitCode, 0)
        XCTAssertTrue(list.standardOutput.contains("Demo Product"))

        let inspect = await app.execute(
            arguments: ["scope", "inspect", "--scope", "Demo Product"]
        )
        XCTAssertEqual(inspect.exitCode, 0)
        XCTAssertTrue(inspect.standardOutput.contains("repository: DemoRepo"))

        let snapshot = await app.execute(
            arguments: ["snapshot", "--scope", "Demo Product"]
        )
        XCTAssertEqual(snapshot.exitCode, 0)
        XCTAssertTrue(snapshot.standardOutput.contains("dff70ec90a888327b71dfd07db0ece964ab7d56a"))
        XCTAssertTrue(snapshot.standardOutput.contains("f31242bfbc5e3400"))

        let scenario = try XCTUnwrap(fixture.scenarios().first)
        let validate = await app.execute(
            arguments: [
                "validate",
                "--scope", "Demo Product",
                "--card", repositoryRoot().appendingPathComponent(scenario.expectedCard).path,
            ]
        )
        XCTAssertEqual(validate.exitCode, 0, validate.standardError)
        XCTAssertTrue(validate.standardOutput.contains("verdict: verified"))

        let ask = await app.execute(
            arguments: [
                "ask",
                "--scope", "Demo Product",
                "--question", scenario.spokenQuestion,
                "--context", "Synthetic context",
            ]
        )
        XCTAssertEqual(ask.exitCode, 0, ask.standardError)
        XCTAssertTrue(ask.standardOutput.contains("verdict: verified"))
        XCTAssertTrue(
            ask.standardOutput.contains(
                "Sources/DemoApp/FeatureAccessPolicy.swift:10-15 @ dff70ec90a888327b71dfd07db0ece964ab7d56a"
            )
        )
    }

    func testAmbiguousRepositoryIsNotSelectedAutomatically() async throws {
        let fixture = try IntegrationFixture()
        defer { fixture.remove() }
        let second = RepositoryRoot(
            id: UUID(),
            displayName: "OtherRepo",
            rootPath: fixture.repositoryURL.path,
            aliases: ["other"],
            environmentLabel: "synthetic-main"
        )
        let scope = ResearchScope(
            id: fixture.scope.id,
            name: fixture.scope.name,
            repositories: fixture.scope.repositories + [second],
            knowledgeRoots: fixture.scope.knowledgeRoots,
            sourcePolicy: fixture.scope.sourcePolicy
        )
        let pipeline = InvestigationPipeline(
            agentEngine: try FixtureAgentEngine(fixtureRootURL: repositoryRoot())
        )

        do {
            _ = try await pipeline.prepare(scope: scope, question: "どのrepoか判断できない質問")
            XCTFail("Expected an ambiguous primary repository")
        } catch {
            XCTAssertEqual(
                error as? InvestigationPipelineError,
                .ambiguousPrimaryRepository(["DemoRepo", "OtherRepo"])
            )
        }
    }
}
