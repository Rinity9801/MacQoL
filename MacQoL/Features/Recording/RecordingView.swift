import SwiftUI
import ScreenCaptureKit

struct RecordingView: View {
    @ObservedObject private var recordingManager = RecordingManager.shared
    @ObservedObject private var settings = RecordingSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status header
                HStack {
                    Image(systemName: "record.circle")
                        .font(.title2)
                        .foregroundColor(statusColor)

                    Text("Screen Recording")
                        .font(.title2)

                    Spacer()

                    statusBadge
                }

                // Buffer info
                if recordingManager.state == .buffering {
                    bufferInfoSection
                }

                // Quick actions
                actionButtons

                Divider()

                // Capture source
                captureSourceSection

                Divider()

                // Audio
                audioSection
            }
            .padding(24)
        }
    }

    private var statusColor: Color {
        switch recordingManager.state {
        case .idle: return .secondary
        case .buffering: return .red
        case .saving: return .orange
        case .error: return .yellow
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var statusText: String {
        switch recordingManager.state {
        case .idle: return "Idle"
        case .buffering: return "Recording"
        case .saving: return "Saving..."
        case .error(let message): return message
        }
    }

    private var bufferInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Buffer")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDuration(recordingManager.bufferDuration))
                    .font(.subheadline.monospacedDigit())
                Text("/ \(settings.bufferDuration.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red.opacity(0.8))
                        .frame(width: geometry.size.width * bufferProgress)
                }
            }
            .frame(height: 4)
        }
    }

    private var bufferProgress: CGFloat {
        let maxDuration = Double(settings.bufferDuration.rawValue)
        return min(CGFloat(recordingManager.bufferDuration / maxDuration), 1.0)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button(action: {
                Task {
                    await recordingManager.toggleBuffering()
                }
            }) {
                HStack {
                    Image(systemName: recordingManager.state == .buffering ? "stop.fill" : "play.fill")
                    Text(recordingManager.state == .buffering ? "Stop" : "Start")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(recordingManager.state == .buffering ? .red : .accentColor)
            .disabled(recordingManager.state == .saving)

            Button(action: {
                recordingManager.saveClip()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save Clip")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(recordingManager.state != .buffering)
        }
    }

    private var captureSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture Source")
                .font(.headline)

            Picker("Mode", selection: Binding(
                get: { settings.captureMode },
                set: { settings.captureMode = $0 }
            )) {
                ForEach(CaptureMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(recordingManager.state == .buffering)

            if settings.captureMode == .display && !recordingManager.availableDisplays.isEmpty {
                Picker("Display", selection: $recordingManager.selectedDisplayIndex) {
                    ForEach(Array(recordingManager.availableDisplays.enumerated()), id: \.offset) { index, display in
                        Text("Display \(index + 1) (\(display.width)x\(display.height))")
                            .tag(index)
                    }
                }
                .disabled(recordingManager.state == .buffering)
            }

            if settings.captureMode == .window && !recordingManager.availableWindows.isEmpty {
                Picker("Window", selection: $recordingManager.selectedWindowIndex) {
                    ForEach(Array(recordingManager.availableWindows.enumerated()), id: \.offset) { index, window in
                        Text(window.title ?? "Unknown")
                            .tag(index)
                    }
                }
                .disabled(recordingManager.state == .buffering)
            }
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio")
                .font(.headline)

            Toggle("System Audio", isOn: $settings.systemAudioEnabled)
                .disabled(recordingManager.state == .buffering)

            Toggle("Microphone", isOn: $settings.microphoneEnabled)
                .disabled(recordingManager.state == .buffering)
        }
    }
}
