import SwiftUI

struct FocusView: View {
    @ObservedObject var focusManager = FocusManager.shared

    @State private var newWebsite = ""
    @State private var showAppPicker = false
    @State private var availableApps: [(name: String, bundleID: String)] = []
    @State private var appSearchText = ""

    private var filteredApps: [(name: String, bundleID: String)] {
        if appSearchText.isEmpty {
            return availableApps
        }
        return availableApps.filter { $0.name.localizedCaseInsensitiveContains(appSearchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Timer section
                timerSection

                Divider()

                // Duration picker (only when idle)
                if focusManager.state == .idle {
                    durationSection
                    Divider()
                }

                // Blocked apps
                blockedAppsSection

                Divider()

                // Blocked websites
                blockedWebsitesSection
            }
            .padding(24)
        }
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "moon.fill")
                    .font(.title2)
                    .foregroundColor(focusManager.state == .active ? .purple : .secondary)

                Text("Focus Mode")
                    .font(.title2)

                Spacer()

                if focusManager.state != .idle {
                    Text(focusManager.state == .paused ? "Paused" : "Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(focusManager.state == .active ? Color.purple.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
            }

            if focusManager.state != .idle {
                // Timer display
                Text(focusManager.formattedTimeRemaining)
                    .font(.system(size: 64, weight: .light, design: .monospaced))
                    .foregroundColor(focusManager.state == .active ? .primary : .secondary)

                // Progress bar
                ProgressView(value: focusManager.progress)
                    .tint(.purple)
            }

            // Controls
            HStack(spacing: 12) {
                if focusManager.state == .idle {
                    Button(action: { focusManager.startSession() }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Start Focus")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                } else {
                    Button(action: { focusManager.toggleSession() }) {
                        HStack {
                            Image(systemName: focusManager.state == .active ? "pause.fill" : "play.fill")
                            Text(focusManager.state == .active ? "Pause" : "Resume")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button(action: { focusManager.stopSession() }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration")
                .font(.headline)

            Picker("Minutes", selection: $focusManager.durationMinutes) {
                Text("15 min").tag(15)
                Text("25 min").tag(25)
                Text("45 min").tag(45)
                Text("60 min").tag(60)
                Text("90 min").tag(90)
                Text("120 min").tag(120)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Blocked Apps

    private var blockedAppsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Blocked Apps")
                    .font(.headline)
                Spacer()
                Button(action: {
                    availableApps = AppBlocker.installedApps()
                    appSearchText = ""
                    showAppPicker = true
                }) {
                    Image(systemName: "plus")
                }
                .disabled(focusManager.state != .idle)
            }

            if focusManager.blockedAppBundleIDs.isEmpty {
                Text("No apps blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focusManager.blockedAppBundleIDs, id: \.self) { bundleID in
                    HStack {
                        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(FileManager.default.displayName(atPath: appURL.path).replacingOccurrences(of: ".app", with: ""))
                        } else {
                            Text(bundleID)
                                .font(.system(.body, design: .monospaced))
                        }
                        Spacer()
                        Button(action: {
                            focusManager.blockedAppBundleIDs.removeAll { $0 == bundleID }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(focusManager.state != .idle)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .popover(isPresented: $showAppPicker) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Select App to Block")
                    .font(.headline)

                TextField("Search apps...", text: $appSearchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredApps, id: \.bundleID) { app in
                            Button(action: {
                                if !focusManager.blockedAppBundleIDs.contains(app.bundleID) {
                                    focusManager.blockedAppBundleIDs.append(app.bundleID)
                                }
                                showAppPicker = false
                            }) {
                                HStack(spacing: 8) {
                                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                    }
                                    Text(app.name)
                                    Spacer()
                                    if focusManager.blockedAppBundleIDs.contains(app.bundleID) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(4)
                            .disabled(focusManager.blockedAppBundleIDs.contains(app.bundleID))
                        }
                    }
                }
            }
            .padding()
            .frame(width: 400, height: 400)
        }
    }

    // MARK: - Blocked Websites

    private var blockedWebsitesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blocked Websites")
                .font(.headline)

            HStack {
                TextField("e.g. twitter.com", text: $newWebsite)
                    .textFieldStyle(.roundedBorder)
                    .disabled(focusManager.state != .idle)

                Button("Add") {
                    let site = newWebsite.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !site.isEmpty && !focusManager.blockedWebsites.contains(site) {
                        focusManager.blockedWebsites.append(site)
                        newWebsite = ""
                    }
                }
                .disabled(newWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || focusManager.state != .idle)
            }

            if focusManager.blockedWebsites.isEmpty {
                Text("No websites blocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focusManager.blockedWebsites, id: \.self) { site in
                    HStack {
                        Text(site)
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(action: {
                            focusManager.blockedWebsites.removeAll { $0 == site }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(focusManager.state != .idle)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}
