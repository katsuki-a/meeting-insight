import Foundation
import MeetingInsightDomain

public enum RepoResolution: Equatable, Sendable {
    case resolved(RepositoryRoot)
    case ambiguous([RepositoryRoot])
    case unresolved
}

public struct RepoResolver: Sendable {
    private let git: GitProcess
    private let now: @Sendable () -> Date

    public init(
        git: GitProcess = GitProcess(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.git = git
        self.now = now
    }

    public func snapshot(_ root: RepositoryRoot) async throws -> RepoSnapshot {
        let requestedURL = URL(fileURLWithPath: root.rootPath, isDirectory: true)
        let canonicalURL = requestedURL.resolvingSymlinksInPath().standardizedFileURL
        try validateDirectory(canonicalURL, originalPath: root.rootPath)

        let discoveredRoot: String
        do {
            discoveredRoot = try await git.run(["rev-parse", "--show-toplevel"], in: canonicalURL)
        } catch let error as RepositoryError {
            if case .commandFailed = error {
                throw RepositoryError.notGitRepository(root.rootPath)
            }
            throw error
        }

        let discoveredURL = URL(fileURLWithPath: discoveredRoot, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard discoveredURL.path == canonicalURL.path else {
            throw RepositoryError.repositoryRootMismatch(
                expected: canonicalURL.path,
                actual: discoveredURL.path
            )
        }

        let commit = try await git.run(["rev-parse", "HEAD"], in: canonicalURL)
        guard commit.range(of: #"^[0-9a-fA-F]{40,64}$"#, options: .regularExpression) != nil else {
            throw RepositoryError.invalidGitOutput("HEAD")
        }
        let branchOutput = try await git.execute(
            ["symbolic-ref", "--short", "HEAD"],
            in: canonicalURL,
            allowedExitCodes: [0, 1]
        )
        let branchValue = branchOutput.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = branchOutput.exitCode == 0 && !branchValue.isEmpty ? branchValue : nil
        let status = try await git.run(["status", "--porcelain=v1"], in: canonicalURL)
        let canonicalRoot = RepositoryRoot(
            id: root.id,
            displayName: root.displayName,
            rootPath: canonicalURL.path,
            aliases: root.aliases,
            environmentLabel: root.environmentLabel
        )
        return RepoSnapshot(
            root: canonicalRoot,
            commitSHA: commit.lowercased(),
            branch: branch,
            isDirty: !status.isEmpty,
            capturedAt: now()
        )
    }

    public func resolvePrimaryRepository(
        in scope: ResearchScope,
        entities: [String]
    ) -> RepoResolution {
        let normalizedEntities = Set(entities.map(normalize).filter { !$0.isEmpty })
        guard !normalizedEntities.isEmpty else { return .unresolved }

        let matches = scope.repositories.filter { repository in
            let names = [repository.displayName] + repository.aliases
            return !normalizedEntities.isDisjoint(with: names.map(normalize))
        }
        if matches.count == 1, let match = matches.first {
            return .resolved(match)
        }
        if matches.count > 1 {
            return .ambiguous(matches)
        }
        return .unresolved
    }

    private func validateDirectory(_ url: URL, originalPath: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw RepositoryError.pathDoesNotExist(originalPath)
        }
        guard isDirectory.boolValue else {
            throw RepositoryError.pathNotDirectory(originalPath)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw RepositoryError.pathNotReadable(originalPath)
        }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}
