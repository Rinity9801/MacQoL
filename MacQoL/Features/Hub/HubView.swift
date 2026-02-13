import SwiftUI

struct HubView: View {
    @State private var appState = AppState.shared

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $appState.activeFeature) { feature in
                Label(feature.rawValue, systemImage: feature.icon)
                    .tag(feature)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.activeFeature {
        case .hub:
            DashboardView()
        case .clipboard:
            ClipboardHubView()
        case .recording:
            RecordingView()
        case .focus:
            FocusView()
        case .todo:
            TodoListView()
        case .mindmap:
            MindmapCanvasView()
        case .settings:
            SettingsView()
        }
    }
}

struct PlaceholderView: View {
    let feature: Feature

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(feature.rawValue)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
