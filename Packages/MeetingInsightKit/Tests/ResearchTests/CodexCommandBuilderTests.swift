import Foundation
@testable import MeetingInsightResearch
import XCTest

final class CodexCommandBuilderTests: XCTestCase {
    func testBuildsFixedReadOnlyEphemeralCommandFromCurrentHelpContract() throws {
        let repository = URL(fileURLWithPath: "/tmp/repo with spaces 日本語")
        let schema = URL(fileURLWithPath: "/tmp/insight-card.schema.json")
        let executable = URL(fileURLWithPath: "/Applications/Codex")

        let command = CodexCommandBuilder().command(
            executableURL: executable,
            repositoryURL: repository,
            schemaURL: schema
        )

        XCTAssertEqual(command.executableURL, executable)
        XCTAssertEqual(
            command.arguments,
            [
                "exec",
                "--cd", repository.path,
                "--sandbox", "read-only",
                "--ephemeral",
                "--ignore-user-config",
                "--ignore-rules",
                "--json",
                "--color", "never",
                "--output-schema", schema.path,
                "-",
            ]
        )

        let help = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Fixtures/CodexHelp/codex-exec-help.txt"),
            encoding: .utf8
        )
        for flag in [
            "--sandbox", "read-only", "--ephemeral", "--ignore-user-config", "--ignore-rules",
            "--json", "--color", "never", "--output-schema",
        ] {
            XCTAssertTrue(help.contains(flag), "captured help is missing \(flag)")
        }
    }
}
