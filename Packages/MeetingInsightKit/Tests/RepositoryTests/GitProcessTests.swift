import Foundation
@testable import MeetingInsightRepository
import XCTest

final class GitProcessTests: XCTestCase {
    func testGitProcessUsesFixedExecutableArgumentsTimeoutAndOutputLimit() async throws {
        let executor = RecordingCommandExecutor()
        let git = GitProcess(executor: executor)
        let workingDirectory = URL(fileURLWithPath: "/tmp/repo; touch escaped")

        _ = try await git.run(["status", "--porcelain=v1"], in: workingDirectory)

        let invocations = await executor.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable.path, "/usr/bin/git")
        XCTAssertEqual(invocation.arguments, ["status", "--porcelain=v1"])
        XCTAssertEqual(invocation.currentDirectory, workingDirectory)
        XCTAssertEqual(invocation.timeout, .seconds(3))
        XCTAssertEqual(invocation.outputLimit, 1_048_576)
    }

    func testFoundationExecutorEnforcesAnInjectedTimeout() async {
        let timeout = Duration.milliseconds(10)
        let invocation = CommandInvocation(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["1"],
            currentDirectory: URL(fileURLWithPath: "/tmp"),
            timeout: timeout,
            outputLimit: 1_024
        )

        await XCTAssertThrowsErrorAsync(
            try await FoundationCommandExecutor().run(invocation)
        ) { error in
            XCTAssertEqual(
                error as? RepositoryError,
                .commandTimedOut(executable: "/bin/sleep", timeout: timeout)
            )
        }
    }

    func testFoundationExecutorDrainsAndClosesPipesForShortLivedCommands() async throws {
        for _ in 0..<20 {
            let output = try await FoundationCommandExecutor().run(
                CommandInvocation(
                    executable: URL(fileURLWithPath: "/usr/bin/printf"),
                    arguments: ["ok"],
                    currentDirectory: URL(fileURLWithPath: "/tmp"),
                    timeout: .seconds(1),
                    outputLimit: 1_024
                )
            )
            XCTAssertEqual(output.exitCode, 0)
            XCTAssertEqual(output.standardOutput, "ok")
            XCTAssertEqual(output.standardError, "")
        }
    }
}

private actor RecordingCommandExecutor: CommandExecuting {
    private(set) var invocations: [CommandInvocation] = []

    func run(_ invocation: CommandInvocation) async throws -> CommandOutput {
        invocations.append(invocation)
        return CommandOutput(exitCode: 0, standardOutput: "", standardError: "")
    }
}
