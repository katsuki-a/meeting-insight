import Foundation
@testable import MeetingInsightOrchestration
import XCTest

final class AppSettingsStoreTests: XCTestCase {
    func testDefaultsAndRoundTripPersistOnlyExplicitSettings() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-insight-settings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = AppSettingsStore(fileURL: temporary.appendingPathComponent("settings.json"))

        let initial = try await store.load()
        XCTAssertEqual(initial, AppSettings())
        let expected = AppSettings(
            activeScopeID: UUID(),
            codexExecutablePath: "/Applications/ChatGPT.app/Contents/Resources/codex",
            hasAcknowledgedPrivacy: true
        )
        try await store.save(expected)

        let reloaded = try await store.load()
        XCTAssertEqual(reloaded, expected)
    }
}
