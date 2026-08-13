import Foundation
import MeetingInsightDomain
import MeetingInsightOrchestration
import MeetingInsightResearch
import XCTest

final class MeetingInsightCLIApplicationTests: XCTestCase {
    func testHelpPublishesRequiredVerticalSliceCommands() async {
        let result = await MeetingInsightCLIApplication().execute(arguments: ["--help"])

        XCTAssertEqual(result.exitCode, 0)
        for command in ["doctor", "scope", "snapshot", "validate", "ask"] {
            XCTAssertTrue(result.standardOutput.contains(command), command)
        }
    }

    func testUnknownCommandFailsWithUsageExitCode() async {
        let result = await MeetingInsightCLIApplication().execute(arguments: ["unknown"])

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.standardError.contains("Unknown command"))
    }
}
