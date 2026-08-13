import Foundation
import MeetingInsightDomain
@testable import MeetingInsightRepository
import XCTest

final class RepositorySnapshotTests: XCTestCase {
    func testSnapshotCapturesCanonicalPathBranchCommitAndDirtyState() async throws {
        let temporary = try TemporaryDirectory(name: "repo with spaces 日本語; touch escaped")
        defer { temporary.remove() }
        let expectedSHA = try makeGitRepository(at: temporary.url)
        try Data("changed\n".utf8).write(to: temporary.url.appendingPathComponent("README.md"))
        let root = repositoryRoot(path: temporary.url.path)
        let capturedAt = Date(timeIntervalSince1970: 1_786_512_345)

        let snapshot = try await RepoResolver(now: { capturedAt }).snapshot(root)

        XCTAssertEqual(snapshot.root.rootPath, temporary.url.resolvingSymlinksInPath().standardizedFileURL.path)
        XCTAssertEqual(snapshot.commitSHA, expectedSHA)
        XCTAssertEqual(snapshot.branch, "main")
        XCTAssertTrue(snapshot.isDirty)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.url.deletingLastPathComponent().appendingPathComponent("escaped").path))
    }

    func testSnapshotSupportsGitWorktreeWhereDotGitIsAFile() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let primary = temporary.url.appendingPathComponent("primary")
        let worktree = temporary.url.appendingPathComponent("linked worktree 日本語")
        let expectedSHA = try makeGitRepository(at: primary)
        try runGit(["worktree", "add", "--quiet", "-b", "linked", worktree.path], at: primary)

        let snapshot = try await RepoResolver().snapshot(repositoryRoot(path: worktree.path))

        var isDirectory: ObjCBool = true
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent(".git").path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
        XCTAssertEqual(snapshot.commitSHA, expectedSHA)
        XCTAssertEqual(snapshot.branch, "linked")
        XCTAssertFalse(snapshot.isDirty)
    }

    func testSnapshotRejectsMissingAndNonGitDirectories() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let missing = temporary.url.appendingPathComponent("missing")

        await XCTAssertThrowsErrorAsync(
            try await RepoResolver().snapshot(repositoryRoot(path: missing.path))
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .pathDoesNotExist(missing.path))
        }
        await XCTAssertThrowsErrorAsync(
            try await RepoResolver().snapshot(repositoryRoot(path: temporary.url.path))
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .notGitRepository(temporary.url.path))
        }
    }
}

func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
