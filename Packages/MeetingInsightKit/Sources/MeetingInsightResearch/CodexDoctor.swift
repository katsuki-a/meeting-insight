import Foundation
import MeetingInsightRepository

public enum CodexAuthenticationStatus: Equatable, Sendable {
    case authenticated
    case unauthenticated
    case unavailable
}

public struct CodexDoctorReport: Equatable, Sendable {
    public let executablePath: String
    public let version: String?
    public let authentication: CodexAuthenticationStatus
    public let issues: [String]

    public init(
        executablePath: String,
        version: String?,
        authentication: CodexAuthenticationStatus,
        issues: [String]
    ) {
        self.executablePath = executablePath
        self.version = version
        self.authentication = authentication
        self.issues = issues
    }
}

public struct CodexDoctor<Executor: CommandExecuting>: Sendable {
    private let executor: Executor

    public init(executor: Executor) {
        self.executor = executor
    }

    public func inspect(executableURL: URL) async -> CodexDoctorReport {
        let directory = executableURL.deletingLastPathComponent()
        let versionOutput: CommandOutput
        do {
            versionOutput = try await executor.run(
                CommandInvocation(
                    executable: executableURL,
                    arguments: ["--version"],
                    currentDirectory: directory,
                    timeout: .seconds(2),
                    outputLimit: 64 * 1_024
                )
            )
        } catch {
            return CodexDoctorReport(
                executablePath: executableURL.path,
                version: nil,
                authentication: .unavailable,
                issues: ["Codex CLIのversion確認に失敗しました。"]
            )
        }
        guard versionOutput.exitCode == 0 else {
            return CodexDoctorReport(
                executablePath: executableURL.path,
                version: nil,
                authentication: .unavailable,
                issues: ["Codex CLIを実行できません。"]
            )
        }

        let version = versionOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let login = try await executor.run(
                CommandInvocation(
                    executable: executableURL,
                    arguments: ["login", "status"],
                    currentDirectory: directory,
                    timeout: .seconds(5),
                    outputLimit: 64 * 1_024
                )
            )
            let authenticated = login.exitCode == 0
            return CodexDoctorReport(
                executablePath: executableURL.path,
                version: version.isEmpty ? nil : version,
                authentication: authenticated ? .authenticated : .unauthenticated,
                issues: authenticated ? [] : ["Codex CLIへのログインが必要です。"]
            )
        } catch {
            return CodexDoctorReport(
                executablePath: executableURL.path,
                version: version.isEmpty ? nil : version,
                authentication: .unavailable,
                issues: ["Codex CLIのログイン状態を確認できません。"]
            )
        }
    }
}

public extension CodexDoctor where Executor == FoundationCommandExecutor {
    init() {
        self.init(executor: FoundationCommandExecutor())
    }
}
