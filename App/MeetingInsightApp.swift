import AppKit
import MeetingInsightOrchestration
import SwiftUI

@MainActor
final class MeetingInsightApplicationDelegate: NSObject, NSApplicationDelegate {
    private let setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let retryDelay: Duration
    private let maximumActivationAttempts: Int
    private let activateMainWindow: @MainActor () -> Bool

    override init() {
        setActivationPolicy = { policy in
            NSApplication.shared.setActivationPolicy(policy)
        }
        retryDelay = .milliseconds(50)
        maximumActivationAttempts = 20
        activateMainWindow = Self.activateDefaultMainWindow
        super.init()
    }

    init(
        setActivationPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
            NSApplication.shared.setActivationPolicy(policy)
        },
        retryDelay: Duration = .milliseconds(50),
        maximumActivationAttempts: Int = 20,
        activateMainWindow: @escaping @MainActor () -> Bool
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.retryDelay = retryDelay
        self.maximumActivationAttempts = maximumActivationAttempts
        self.activateMainWindow = activateMainWindow
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        setActivationPolicy(.regular)
        Task { @MainActor [activateMainWindow, maximumActivationAttempts, retryDelay] in
            await Task.yield()
            for attempt in 0..<maximumActivationAttempts {
                if activateMainWindow() { return }
                guard attempt < maximumActivationAttempts - 1 else { return }
                try? await Task.sleep(for: retryDelay)
            }
        }
    }

    private static func activateDefaultMainWindow() -> Bool {
        guard let window = NSApplication.shared.windows.first(where: \.canBecomeKey) else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        return true
    }
}

@main
struct MeetingInsightApp: App {
    @NSApplicationDelegateAdaptor(MeetingInsightApplicationDelegate.self)
    private var applicationDelegate
    @State private var model = AppModel(service: MeetingInsightAppService())

    var body: some Scene {
        WindowGroup("Meeting Insight", id: "main") {
            MainView(model: model)
        }
        .defaultSize(width: 720, height: 760)

        MenuBarExtra("Meeting Insight", systemImage: "lightbulb") {
            MenuBarContent(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
