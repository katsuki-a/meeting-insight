import Foundation
@testable import MeetingInsightResearch
import XCTest

final class CodexEventDecoderTests: XCTestCase {
    func testDecodesRecordedJSONLAndPreservesUnknownEvents() throws {
        let card = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Fixtures/ExpectedCards/feature-a-paid-and-flag.json"
            ),
            encoding: .utf8
        )
        let template = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Fixtures/AgentEvents/success.jsonl"),
            encoding: .utf8
        )
        let encodedCard = try XCTUnwrap(
            String(
                data: JSONEncoder().encode(card),
                encoding: .utf8
            )
        )
        let stream = template.replacingOccurrences(of: "\"__CARD_JSON__\"", with: encodedCard)

        let events = try stream.split(separator: "\n").map {
            try CodexEventDecoder().decode(Data($0.utf8))
        }

        XCTAssertEqual(events.count, 6)
        XCTAssertTrue(events.contains { event in
            if case .unknown("future.event") = event { return true }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .turnCompleted(let usage) = event {
                return usage.inputTokens == 1_200 && usage.outputTokens == 300
            }
            return false
        })
    }

    func testMalformedRecordedLineFailsWithoutPartialAcceptance() throws {
        let lines = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Fixtures/AgentEvents/malformed.jsonl"),
            encoding: .utf8
        ).split(separator: "\n")

        XCTAssertNoThrow(try CodexEventDecoder().decode(Data(lines[0].utf8)))
        XCTAssertThrowsError(try CodexEventDecoder().decode(Data(lines[1].utf8)))
    }
}
