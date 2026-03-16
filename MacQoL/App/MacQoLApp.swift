import SwiftUI
import SwiftData

@main
struct MacQoLApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
        .modelContainer(AppDelegate.sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
