import Darwin
import Foundation
import MeetingInsightDomain
import MeetingInsightRepository
@testable import MeetingInsightResearch
import XCTest

final class CodexProcessRunnerTests: XCTestCase {
    func testRunsFixtureProcessWithPromptAndDecodesStructuredFinalCard() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let card = try fixture.card(named: "feature-a-paid-and-flag")
        let cardJSON = try XCTUnwrap(
            String(data: try InsightCardCoding.encoder().encode(card), encoding: .utf8)
        )
        let executable = try fixtureExecutable()
        let runner = CodexProcessRunner(
            environmentOverrides: [
                "MEETING_INSIGHT_FIXTURE_MODE": "success",
                "MEETING_INSIGHT_FIXTURE_CARD": cardJSON,
                "MEETING_INSIGHT_FIXTURE_EXPECTED_PROMPT": "synthetic prompt",
            ]
        )

        let result = try await runner.run(
            CodexRunRequest(
                requestID: card.requestID,
                executableURL: executable,
                repositoryURL: fixture.repositoryURL,
                schemaURL: repositoryRoot().appendingPathComponent("Schemas/insight-card.schema.json"),
                prompt: "synthetic prompt"
            )
        )

        XCTAssertEqual(result.card, card)
        XCTAssertEqual(result.metrics.exitCode, 0)
        XCTAssertEqual(result.metrics.eventCount, 5)
        XCTAssertEqual(result.metrics.usage?.inputTokens, 1_200)
        XCTAssertGreaterThanOrEqual(result.metrics.durationMilliseconds, 0)
        let snapshotAfterRun = try await RepoResolver().snapshot(fixture.repositorySnapshot.root)
        XCTAssertEqual(snapshotAfterRun.commitSHA, fixture.repositorySnapshot.commitSHA)
        XCTAssertFalse(snapshotAfterRun.isDirty)
    }

    func testMalformedOutputCrashAndLimitsFailClosed() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let executable = try fixtureExecutable()
        for (mode, expected) in [
            ("malformed", CodexRunnerError.malformedJSONL),
            ("crash", CodexRunnerError.nonZeroExit(7)),
            ("output-limit", CodexRunnerError.stdoutLimitExceeded),
        ] {
            let limits = CodexProcessLimits(
                stdoutBytes: mode == "output-limit" ? 100 : 10 * 1_048_576,
                stderrBytes: 2 * 1_048_576,
                lineBytes: mode == "output-limit" ? 100 : 1_048_576,
                softTimeout: .seconds(1),
                hardTimeout: .seconds(2),
                killGrace: .milliseconds(20)
            )
            let runner = CodexProcessRunner(
                limits: limits,
                environmentOverrides: ["MEETING_INSIGHT_FIXTURE_MODE": mode]
            )
            do {
                _ = try await runner.run(request(executable: executable, repository: fixture.repositoryURL))
                XCTFail("Expected \(mode) to fail")
            } catch {
                XCTAssertEqual(error as? CodexRunnerError, expected)
            }
        }
    }

    func testPolicyViolationTerminatesProcessAndDiscardsResult() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let runner = CodexProcessRunner(
            limits: fastLimits,
            environmentOverrides: ["MEETING_INSIGHT_FIXTURE_MODE": "policy"]
        )
        do {
            _ = try await runner.run(
                request(executable: try fixtureExecutable(), repository: fixture.repositoryURL)
            )
            XCTFail("Expected policy violation")
        } catch {
            XCTAssertEqual(
                error as? CodexRunnerError,
                .sourcePolicyViolation(.forbiddenItem(.webSearch))
            )
        }
    }

    func testHardTimeoutKillsIgnoringChildProcess() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let pidPath = fixture.temporaryRoot.appendingPathComponent("hard-timeout.pid")
        let runner = CodexProcessRunner(
            limits: fastLimits,
            environmentOverrides: [
                "MEETING_INSIGHT_FIXTURE_MODE": "hang",
                "MEETING_INSIGHT_FIXTURE_PID_PATH": pidPath.path,
            ]
        )
        do {
            _ = try await runner.run(
                request(executable: try fixtureExecutable(), repository: fixture.repositoryURL)
            )
            XCTFail("Expected hard timeout")
        } catch {
            XCTAssertEqual(error as? CodexRunnerError, .hardTimeout)
        }
        let pid = try processID(at: pidPath)
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testCancelKillsIgnoringChildProcess() async throws {
        let fixture = try ResearchFixture()
        defer { fixture.remove() }
        let pidPath = fixture.temporaryRoot.appendingPathComponent("cancel.pid")
        let request = request(executable: try fixtureExecutable(), repository: fixture.repositoryURL)
        let runner = CodexProcessRunner(
            limits: CodexProcessLimits(
                stdoutBytes: 10 * 1_048_576,
                stderrBytes: 2 * 1_048_576,
                lineBytes: 1_048_576,
                softTimeout: .seconds(1),
                hardTimeout: .seconds(5),
                killGrace: .milliseconds(20)
            ),
            environmentOverrides: [
                "MEETING_INSIGHT_FIXTURE_MODE": "hang",
                "MEETING_INSIGHT_FIXTURE_PID_PATH": pidPath.path,
            ]
        )
        let task = Task { try await runner.run(request) }
        try await waitForFile(pidPath)
        await runner.cancel(requestID: request.requestID)

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? CodexRunnerError, .cancelled)
        }
        let pid = try processID(at: pidPath)
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    private var fastLimits: CodexProcessLimits {
        CodexProcessLimits(
            stdoutBytes: 10 * 1_048_576,
            stderrBytes: 2 * 1_048_576,
            lineBytes: 1_048_576,
            softTimeout: .milliseconds(100),
            hardTimeout: .milliseconds(500),
            killGrace: .milliseconds(50)
        )
    }

    private func request(executable: URL, repository: URL) -> CodexRunRequest {
        CodexRunRequest(
            requestID: UUID(),
            executableURL: executable,
            repositoryURL: repository,
            schemaURL: repositoryRoot().appendingPathComponent("Schemas/insight-card.schema.json"),
            prompt: "fixture"
        )
    }

    private func fixtureExecutable() throws -> URL {
        let executable = repositoryRoot().appendingPathComponent("Fixtures/AgentProcess/codex-fixture.py")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        return executable
    }

    private func processID(at path: URL) throws -> pid_t {
        let value = try String(contentsOf: path, encoding: .utf8)
        return try XCTUnwrap(pid_t(value))
    }

    private func waitForFile(_ path: URL) async throws {
        for _ in 0..<400 {
            if FileManager.default.fileExists(atPath: path.path) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("PID file was not created")
    }
}
