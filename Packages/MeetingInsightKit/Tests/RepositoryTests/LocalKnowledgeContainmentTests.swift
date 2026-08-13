import Foundation
@testable import MeetingInsightRepository
import XCTest

final class LocalKnowledgeContainmentTests: XCTestCase {
    func testListsAndSearchesOnlyIncludedAllowlistedFiles() throws {
        let temporary = try TemporaryDirectory(name: "knowledge 日本語")
        defer { temporary.remove() }
        let outside = temporary.url.deletingLastPathComponent().appendingPathComponent("outside.md")
        try write("outside secret", to: outside)
        try write("Feature A current behavior", to: temporary.url.appendingPathComponent("docs/guide.md"))
        try write("plain note", to: temporary.url.appendingPathComponent("notes.txt"))
        try write("private secret", to: temporary.url.appendingPathComponent("private/secret.md"))
        try write("environment secret", to: temporary.url.appendingPathComponent(".env.local"))
        try write("key material", to: temporary.url.appendingPathComponent("credentials.pem"))
        try write("case-insensitive credential", to: temporary.url.appendingPathComponent("Credentials.JSON"))
        try write("package cache", to: temporary.url.appendingPathComponent(".swiftpm/cache.md"))
        try write("generated", to: temporary.url.appendingPathComponent("build/generated.md"))
        try FileManager.default.createSymbolicLink(
            at: temporary.url.appendingPathComponent("escape.md"),
            withDestinationURL: outside
        )
        let root = knowledgeRoot(path: temporary.url.path, excludes: ["private/**"])
        let provider = LocalKnowledgeProvider()

        let documents = try provider.documents(in: root)
        let matches = try provider.search("Feature A", in: root)

        XCTAssertEqual(documents.map(\.relativePath), ["docs/guide.md", "notes.txt"])
        XCTAssertEqual(matches.map(\.relativePath), ["docs/guide.md"])
        XCTAssertFalse(documents.contains { $0.content.contains("secret") })
    }

    func testRejectsTraversalAndSymlinkReadsOutsideCanonicalRoot() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let outside = temporary.url.deletingLastPathComponent().appendingPathComponent("outside.md")
        try write("outside", to: outside)
        try FileManager.default.createSymbolicLink(
            at: temporary.url.appendingPathComponent("escape.md"),
            withDestinationURL: outside
        )
        let root = knowledgeRoot(path: temporary.url.path)
        let provider = LocalKnowledgeProvider()

        XCTAssertThrowsError(try provider.read(relativePath: "../outside.md", in: root)) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidRelativePath("../outside.md"))
        }
        XCTAssertThrowsError(try provider.read(relativePath: "escape.md", in: root)) { error in
            XCTAssertEqual(error as? RepositoryError, .pathOutsideRoot("escape.md"))
        }
        XCTAssertThrowsError(try provider.read(relativePath: "missing.md", in: root)) { error in
            XCTAssertEqual(error as? RepositoryError, .pathDoesNotExist("missing.md"))
        }
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }
}
