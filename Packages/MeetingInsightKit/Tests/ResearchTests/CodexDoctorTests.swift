import Foundation
import MeetingInsightRepository
@testable import MeetingInsightResearch
import XCTest

final class CodexDoctorTests: XCTestCase {
    func testDoctorChecksVersionAndAuthenticationWithoutReadingCredentialFiles() async throws {
        let executable = URL(fileURLWithPath: "/tmp/codex")
        let executor = DoctorCommandExecutor(outputs: [
            CommandOutput(exitCode: 0, standardOutput: "codex-cli 1.2.3\n", standardError: ""),
            CommandOutput(exitCode: 0, standardOutput: "Logged in using ChatGPT\n", standardError: ""),
        ])

        let report = await CodexDoctor(executor: executor).inspect(executableURL: executable)

        XCTAssertEqual(report.executablePath, executable.path)
        XCTAssertEqual(report.version, "codex-cli 1.2.3")
        XCTAssertEqual(report.authentication, .authenticated)
        XCTAssertTrue(report.issues.isEmpty)
        let invocations = await executor.invocations
        XCTAssertEqual(invocations.map(\.arguments), [["--version"], ["login", "status"]])
        XCTAssertEqual(invocations.map(\.timeout), [.seconds(2), .seconds(5)])
        XCTAssertFalse(invocations.flatMap(\.arguments).contains { $0.contains("auth.json") })
    }

    func testDoctorReportsUnauthenticatedAndUnavailableWithoutExposingStderr() async {
        let executor = DoctorCommandExecutor(outputs: [
            CommandOutput(exitCode: 0, standardOutput: "codex-cli 1.2.3", standardError: ""),
            CommandOutput(exitCode: 1, standardOutput: "", standardError: "secret diagnostic"),
        ])
        let report = await CodexDoctor(executor: executor).inspect(
            executableURL: URL(fileURLWithPath: "/tmp/codex")
        )

        XCTAssertEqual(report.authentication, .unauthenticated)
        XCTAssertFalse(report.issues.joined().contains("secret diagnostic"))
    }
}

private actor DoctorCommandExecutor: CommandExecuting {
    private var outputs: [CommandOutput]
    private(set) var invocations: [CommandInvocation] = []

    init(outputs: [CommandOutput]) {
        self.outputs = outputs
    }

    func run(_ invocation: CommandInvocation) async throws -> CommandOutput {
        invocations.append(invocation)
        return outputs.removeFirst()
    }
}
