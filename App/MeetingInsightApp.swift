import AppKit
import MeetingInsightOrchestration
import SwiftUI

@main
struct MeetingInsightApp: App {
    private let initialStatus = OrchestrationModule.initialStatus

    var body: some Scene {
        MenuBarExtra("Meeting Insight", systemImage: "lightbulb") {
            Text(initialStatus.rawValue.capitalized)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
