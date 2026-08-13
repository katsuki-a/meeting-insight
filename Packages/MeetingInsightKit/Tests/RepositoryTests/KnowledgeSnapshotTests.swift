import CryptoKit
import Foundation
@testable import MeetingInsightRepository
import XCTest

final class KnowledgeSnapshotTests: XCTestCase {
    func testSameFileSetProducesSameRevisionRegardlessOfRootAndCreationOrder() throws {
        let first = try TemporaryDirectory(name: "first")
        let second = try TemporaryDirectory(name: "second")
        defer {
            first.remove()
            second.remove()
        }
        try write("beta", to: first.url.appendingPathComponent("b.md"))
        try write("alpha", to: first.url.appendingPathComponent("nested/a.md"))
        try write("alpha", to: second.url.appendingPathComponent("nested/a.md"))
        try write("beta", to: second.url.appendingPathComponent("b.md"))
        let capturedAt = Date(timeIntervalSince1970: 1_786_512_345)
        let provider = LocalKnowledgeProvider()

        let firstSnapshot = try provider.snapshot(
            knowledgeRoot(path: first.url.path),
            capturedAt: capturedAt
        )
        let secondSnapshot = try provider.snapshot(
            knowledgeRoot(path: second.url.path),
            capturedAt: capturedAt
        )

        XCTAssertEqual(firstSnapshot.revision, secondSnapshot.revision)
        XCTAssertEqual(firstSnapshot.fileCount, 2)
        XCTAssertEqual(firstSnapshot.capturedAt, capturedAt)
        try write("changed", to: second.url.appendingPathComponent("b.md"))
        XCTAssertNotEqual(
            firstSnapshot.revision,
            try provider.snapshot(knowledgeRoot(path: second.url.path), capturedAt: capturedAt).revision
        )
    }

    func testDocumentsExposeStablePerFileDigestAndModificationDate() throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let file = temporary.url.appendingPathComponent("guide.md")
        try write("content", to: file)

        let document = try XCTUnwrap(
            LocalKnowledgeProvider().documents(in: knowledgeRoot(path: temporary.url.path)).first
        )

        XCTAssertEqual(document.relativePath, "guide.md")
        XCTAssertEqual(document.contentDigest, SHA256.hash(data: Data("content".utf8)).hexString)
        XCTAssertNotNil(document.modifiedAt)
    }

    private func write(_ value: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url)
    }
}

private extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
