import AppKit

/// Observes app launches and terminates blocked apps by bundle ID
final class AppBlocker {
    private var observer: NSObjectProtocol?
    private var blockedBundleIDs: Set<String> = []

    func startBlocking(bundleIDs: [String]) {
        blockedBundleIDs = Set(bundleIDs)
        guard !blockedBundleIDs.isEmpty else { return }

        // Terminate any currently running blocked apps
        terminateBlockedApps()

        // Watch for new app launches
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier,
                  self.blockedBundleIDs.contains(bundleID) else { return }

            app.terminate()
        }
    }

    func stopBlocking() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
        blockedBundleIDs.removeAll()
    }

    private func terminateBlockedApps() {
        for app in NSWorkspace.shared.runningApplications {
            if let bundleID = app.bundleIdentifier, blockedBundleIDs.contains(bundleID) {
                app.terminate()
            }
        }
    }

    /// Returns a list of running user applications for picking
    static func runningUserApps() -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName, let bundleID = app.bundleIdentifier else { return nil }
                return (name: name, bundleID: bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
