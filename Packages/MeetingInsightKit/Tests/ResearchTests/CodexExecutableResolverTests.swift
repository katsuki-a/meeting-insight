import Foundation
@testable import MeetingInsightResearch
import XCTest

final class CodexExecutableResolverTests: XCTestCase {
    func testResolutionOrderPrefersExplicitThenPATHThenKnownLocations() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-resolver-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let explicit = try makeExecutable(named: "explicit-codex", in: temporary)
        let pathDirectory = temporary.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)
        let pathCodex = try makeExecutable(named: "codex", in: pathDirectory)
        let known = try makeExecutable(named: "known-codex", in: temporary)
        let resolver = CodexExecutableResolver(
            environmentPath: pathDirectory.path,
            knownLocations: [known],
            homeDirectory: temporary
        )

        XCTAssertEqual(try resolver.resolve(explicitPath: explicit.path), explicit)
        XCTAssertEqual(try resolver.resolve(explicitPath: nil), pathCodex)
        try FileManager.default.removeItem(at: pathCodex)
        XCTAssertEqual(try resolver.resolve(explicitPath: nil), known)
    }

    func testRejectsRelativeNonRegularAndNonExecutableCandidates() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-resolver-invalid-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let plain = temporary.appendingPathComponent("codex")
        try Data().write(to: plain)
        let resolver = CodexExecutableResolver(
            environmentPath: "",
            knownLocations: [],
            homeDirectory: temporary
        )

        XCTAssertThrowsError(try resolver.resolve(explicitPath: "relative/codex"))
        XCTAssertThrowsError(try resolver.resolve(explicitPath: temporary.path))
        XCTAssertThrowsError(try resolver.resolve(explicitPath: plain.path))
    }

    private func makeExecutable(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("fixture".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }
}
