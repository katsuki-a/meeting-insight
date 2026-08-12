import XCTest
@testable import MeetingInsightDomain

final class SessionStatusTests: XCTestCase {
    func testInitialStatusIsIdle() {
        XCTAssertEqual(SessionStatus.idle.rawValue, "idle")
    }
}
