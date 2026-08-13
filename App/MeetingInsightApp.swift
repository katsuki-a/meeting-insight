import AppKit
import MeetingInsightOrchestration
import SwiftUI

@main
struct MeetingInsightApp: App {
    @State private var model = AppModel(service: MeetingInsightAppService())

    var body: some Scene {
        MenuBarExtra("Meeting Insight", systemImage: "lightbulb") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Meeting Insight", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 720, height: 760)
    }
}
