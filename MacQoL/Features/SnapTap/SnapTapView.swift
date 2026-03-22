import SwiftUI

struct SnapTapView: View {
    @ObservedObject private var manager = SnapTapManager.shared
    @State private var isAddingPair = false
    @State private var recordingKeyA = false
    @State private var recordingKeyB = false
    @State private var newKeyA: UInt16 = 0
    @State private var newKeyB: UInt16 = 2
    @State private var newLabelA = "A"
    @State private var newLabelB = "D"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Snap Tap")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("SOCD resolution — when both opposing keys are held, the last pressed wins. Release it to instantly reactivate the other.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { manager.toggle() }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(manager.isActive ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text(manager.isActive ? "Active" : "Inactive")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)

            Divider()

            // Pairs list
            if manager.pairs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No key pairs configured")
                        .foregroundStyle(.secondary)
                    Text("Add opposing key pairs to enable Snap Tap")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.pairs) { pair in
                        pairRow(pair)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Add pair / footer
            HStack {
                if isAddingPair {
                    addPairForm
                } else {
                    Button(action: { isAddingPair = true }) {
                        Label("Add Key Pair", systemImage: "plus")
                    }

                    Spacer()

                    if !manager.isActive {
                        Text("Requires Accessibility permission")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Pair Row

    private func pairRow(_ pair: SnapTapPair) -> some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { pair.enabled },
                set: { _ in manager.togglePair(pair) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            keyBadge(pair.labelA)

            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            keyBadge(pair.labelB)

            Spacer()

            Text(pair.enabled ? "Active" : "Disabled")
                .font(.caption)
                .foregroundStyle(pair.enabled ? .green : .secondary)

            Button(action: { manager.removePair(pair) }) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func keyBadge(_ label: String) -> some View {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Add Pair Form

    private var addPairForm: some View {
        HStack(spacing: 12) {
            Text("Key A:")
                .font(.caption)
            keyRecordButton(label: newLabelA, isRecording: $recordingKeyA) { code, label in
                newKeyA = code
                newLabelA = label
            }

            Text("Key B:")
                .font(.caption)
            keyRecordButton(label: newLabelB, isRecording: $recordingKeyB) { code, label in
                newKeyB = code
                newLabelB = label
            }

            Button("Add") {
                let pair = SnapTapPair(
                    keyA: newKeyA, labelA: newLabelA,
                    keyB: newKeyB, labelB: newLabelB
                )
                manager.addPair(pair)
                isAddingPair = false
                // Reset
                newKeyA = 0; newLabelA = "A"
                newKeyB = 2; newLabelB = "D"
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newKeyA == newKeyB)

            Button("Cancel") {
                isAddingPair = false
                recordingKeyA = false
                recordingKeyB = false
            }
            .controlSize(.small)

            Spacer()
        }
    }

    private func keyRecordButton(label: String, isRecording: Binding<Bool>, onRecord: @escaping (UInt16, String) -> Void) -> some View {
        Button(action: {
            isRecording.wrappedValue.toggle()
            // Turn off the other recording
            if isRecording.wrappedValue {
                if isRecording.wrappedValue == recordingKeyA {
                    recordingKeyB = false
                } else {
                    recordingKeyA = false
                }
            }
        }) {
            Text(isRecording.wrappedValue ? "Press a key..." : label)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isRecording.wrappedValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording.wrappedValue ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onKeyPress(phases: .down) { press in
            guard isRecording.wrappedValue else { return .ignored }
            // Map the key press to a keycode
            // We need the actual keycode — use NSEvent monitor instead
            return .ignored
        }
        .focusable()
        .onAppear {
            if isRecording.wrappedValue {
                setupKeyMonitor(isRecording: isRecording, onRecord: onRecord)
            }
        }
        .onChange(of: isRecording.wrappedValue) { _, newVal in
            if newVal {
                setupKeyMonitor(isRecording: isRecording, onRecord: onRecord)
            }
        }
    }

    @State private var keyMonitor: Any?

    private func setupKeyMonitor(isRecording: Binding<Bool>, onRecord: @escaping (UInt16, String) -> Void) {
        // Remove any existing monitor
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard isRecording.wrappedValue else { return event }
            let code = event.keyCode
            let label = HotkeyManager.shared.keyCodeToString(code)
            onRecord(code, label)
            isRecording.wrappedValue = false
            // Remove monitor
            if let monitor = self.keyMonitor {
                NSEvent.removeMonitor(monitor)
                self.keyMonitor = nil
            }
            return nil // consume the event
        }
    }
}
