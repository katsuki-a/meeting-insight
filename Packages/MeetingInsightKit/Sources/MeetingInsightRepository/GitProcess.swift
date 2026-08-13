import Foundation

public struct GitProcess: Sendable {
    public static let defaultTimeout = Duration.seconds(3)
    public static let defaultOutputLimit = 1_048_576

    private let executor: any CommandExecuting
    private let timeout: Duration
    private let outputLimit: Int

    public init(
        executor: any CommandExecuting = FoundationCommandExecutor(),
        timeout: Duration = GitProcess.defaultTimeout,
        outputLimit: Int = GitProcess.defaultOutputLimit
    ) {
        self.executor = executor
        self.timeout = timeout
        self.outputLimit = outputLimit
    }

    public func run(_ arguments: [String], in directory: URL) async throws -> String {
        let output = try await execute(arguments, in: directory)
        return output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func execute(
        _ arguments: [String],
        in directory: URL,
        allowedExitCodes: Set<Int32> = [0]
    ) async throws -> CommandOutput {
        let invocation = CommandInvocation(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            currentDirectory: directory,
            timeout: timeout,
            outputLimit: outputLimit
        )
        let output = try await executor.run(invocation)
        guard allowedExitCodes.contains(output.exitCode) else {
            throw RepositoryError.commandFailed(
                exitCode: output.exitCode,
                standardError: output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return output
    }
}
