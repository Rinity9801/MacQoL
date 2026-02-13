import SwiftUI

/// Clipboard history view shown in the hub sidebar (not the overlay popup)
struct ClipboardHubView: View {
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "doc.on.clipboard")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Clipboard History")
                    .font(.title2)
                Spacer()
            }

            Text("Clipboard history is managed via the overlay popup.")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Press")
                    .foregroundStyle(.secondary)
                Text(hotkeyManager.clipboardHotkeyDisplay)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
                Text("to open the clipboard overlay at cursor position.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Features:")
                    .font(.headline)
                Label("Arrow keys to navigate", systemImage: "arrow.up.arrow.down")
                Label("Enter to paste selected item", systemImage: "return")
                Label("1-9 to quick paste by number", systemImage: "number")
                Label("Escape to dismiss", systemImage: "escape")
                Label("Supports text and images", systemImage: "photo.on.rectangle")
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(24)
    }
}
