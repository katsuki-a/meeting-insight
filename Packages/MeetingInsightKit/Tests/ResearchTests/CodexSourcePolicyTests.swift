import Foundation
@testable import MeetingInsightResearch
import XCTest

final class CodexSourcePolicyTests: XCTestCase {
    func testRejectsRecordedWebMCPAndFileChangeEvents() throws {
        for (name, kind) in [
            ("web-search", CodexItemKind.webSearch),
            ("mcp-tool-call", CodexItemKind.mcpToolCall),
            ("file-change", CodexItemKind.fileChange),
        ] {
            let line = try XCTUnwrap(
                String(
                    contentsOf: repositoryRoot().appendingPathComponent("Fixtures/AgentEvents/\(name).jsonl"),
                    encoding: .utf8
                ).split(separator: "\n").last
            )
            let event = try CodexEventDecoder().decode(Data(line.utf8))
            XCTAssertEqual(CodexSourcePolicy().violation(for: event), .forbiddenItem(kind))
        }
    }

    func testAllowsRepositoryReadCommandsAndUnknownFutureEvents() throws {
        let command = try CodexEventDecoder().decode(
            Data(#"{"type":"item.started","item":{"id":"1","type":"command_execution","command":"git show HEAD"}}"#.utf8)
        )
        let unknown = try CodexEventDecoder().decode(
            Data(#"{"type":"future.event"}"#.utf8)
        )

        XCTAssertNil(CodexSourcePolicy().violation(for: command))
        XCTAssertNil(CodexSourcePolicy().violation(for: unknown))
    }
}
