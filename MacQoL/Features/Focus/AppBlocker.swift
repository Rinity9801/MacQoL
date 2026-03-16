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

    /// Returns a list of all installed applications on the system
    static func installedApps() -> [(name: String, bundleID: String)] {
        var seen = Set<String>()
        var results: [(name: String, bundleID: String)] = []

        let directories = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSHomeDirectory() + "/Applications"
        ]

        for dir in directories {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }
                guard !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                results.append((name: name, bundleID: bundleID))
            }
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
