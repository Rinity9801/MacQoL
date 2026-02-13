import SwiftUI
import SwiftData

struct DashboardView: View {
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var focusManager = FocusManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared

    @Query(filter: #Predicate<TodoItem> { !$0.isDone }) private var activeTodos: [TodoItem]
    @Query private var allTodos: [TodoItem]
    @Query(sort: \MindmapDocument.modifiedAt, order: .reverse) private var mindmaps: [MindmapDocument]

    @State private var appState = AppState.shared

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16),
            ], spacing: 16) {
                // Clipboard
                DashboardCard(
                    title: "Clipboard",
                    icon: "doc.on.clipboard",
                    color: .blue,
                    status: hotkeyManager.clipboardHotkeyDisplay
                ) {
                    appState.activeFeature = .clipboard
                }

                // Recording
                DashboardCard(
                    title: "Recording",
                    icon: "record.circle",
                    color: recordingManager.state == .buffering ? .red : .secondary,
                    status: recordingStatusText
                ) {
                    appState.activeFeature = .recording
                }

                // Focus
                DashboardCard(
                    title: "Focus",
                    icon: "moon.fill",
                    color: focusManager.state == .active ? .purple : .secondary,
                    status: focusStatusText
                ) {
                    appState.activeFeature = .focus
                }

                // Todo
                DashboardCard(
                    title: "Todo",
                    icon: "checklist",
                    color: .green,
                    status: "\(activeTodos.count) active / \(allTodos.count) total"
                ) {
                    appState.activeFeature = .todo
                }

                // Mindmap
                DashboardCard(
                    title: "Mindmap",
                    icon: "point.3.connected.trianglepath.dotted",
                    color: .orange,
                    status: "\(mindmaps.count) mindmap\(mindmaps.count == 1 ? "" : "s")"
                ) {
                    appState.activeFeature = .mindmap
                }
            }
            .padding(24)

            // Hotkey hints
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                    .padding(.bottom, 4)

                HotkeyHintRow(label: "Clipboard Overlay", shortcut: hotkeyManager.clipboardHotkeyDisplay)
                HotkeyHintRow(label: "Save Clip", shortcut: hotkeyManager.saveClipHotkeyDisplay)
                HotkeyHintRow(label: "Toggle Recording", shortcut: hotkeyManager.toggleRecordingHotkeyDisplay)
                HotkeyHintRow(label: "Toggle Focus", shortcut: hotkeyManager.toggleFocusHotkeyDisplay)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private var recordingStatusText: String {
        switch recordingManager.state {
        case .idle: return "Idle"
        case .buffering: return "Recording \(formatDuration(recordingManager.bufferDuration))"
        case .saving: return "Saving..."
        case .error(let msg): return msg
        }
    }

    private var focusStatusText: String {
        switch focusManager.state {
        case .idle: return "Idle"
        case .active: return "Active \(focusManager.formattedTimeRemaining)"
        case .paused: return "Paused \(focusManager.formattedTimeRemaining)"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

struct DashboardCard: View {
    let title: String
    let icon: String
    let color: Color
    let status: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)
                    Spacer()
                }

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

struct HotkeyHintRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
            Text(shortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
    }
}
