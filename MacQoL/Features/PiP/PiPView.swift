import SwiftUI
import ScreenCaptureKit

struct PiPView: View {
    @ObservedObject private var pipManager = PiPManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                Image(systemName: "pip.fill")
                    .font(.title2)
                    .foregroundColor(pipManager.isActive ? .green : .secondary)
                Text("Picture in Picture")
                    .font(.title2)
                Spacer()

                if pipManager.isActive {
                    Button(action: {
                        Task { await pipManager.stopPiP() }
                    }) {
                        HStack {
                            Image(systemName: "stop.fill")
                            Text("Stop PiP")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(16)

            Divider()

            if pipManager.isActive, let window = pipManager.selectedWindow {
                // Active PiP info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                        VStack(alignment: .leading) {
                            Text("PiP Active")
                                .font(.headline)
                            Text(window.title ?? "Unknown Window")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let app = window.owningApplication?.applicationName {
                                Text(app)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Text("The PiP window is floating on your screen. You can drag, resize, or close it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            } else {
                // Window picker
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Select a window")
                            .font(.headline)
                        Spacer()
                        Button(action: {
                            Task { await pipManager.refreshWindows() }
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Refresh window list")
                    }
                    .padding(.horizontal, 16)

                    if pipManager.availableWindows.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "macwindow")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No windows found")
                                .foregroundStyle(.secondary)
                            Button("Refresh") {
                                Task { await pipManager.refreshWindows() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(pipManager.availableWindows, id: \.windowID) { window in
                                WindowRow(window: window) {
                                    Task { await pipManager.startPiP(window: window) }
                                }
                            }
                        }
                    }
                }
            }

            if let error = pipManager.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }

            Spacer()
        }
        .task {
            await pipManager.refreshWindows()
        }
    }
}

struct WindowRow: View {
    let window: SCWindow
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            if let bundleID = window.owningApplication?.bundleIdentifier,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "macwindow")
                    .frame(width: 24, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                let title = (window.title ?? "").isEmpty
                    ? (window.owningApplication?.applicationName ?? "Untitled")
                    : window.title!
                Text(title)
                    .lineLimit(1)
                if let appName = window.owningApplication?.applicationName {
                    Text(appName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(Int(window.frame.width))x\(Int(window.frame.height))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if isHovering {
                Button("PiP") {
                    onSelect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            onSelect()
        }
    }
}
