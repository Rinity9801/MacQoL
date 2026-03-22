import SwiftUI

struct KeyRemapView: View {
    @ObservedObject private var manager = KeyRemapManager.shared
    @State private var isAddingMapping = false
    @State private var recordingFrom = false
    @State private var recordingTo = false
    @State private var newFrom: UInt16 = 0
    @State private var newTo: UInt16 = 0
    @State private var newFromLabel = ""
    @State private var newToLabel = ""
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Remap")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Remap one key to another globally. Requires Accessibility permission.")
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

            // Mappings list
            if manager.mappings.isEmpty && !isAddingMapping {
                VStack(spacing: 12) {
                    Image(systemName: "keyboard.badge.ellipsis")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No key mappings configured")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.mappings) { mapping in
                        mappingRow(mapping)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                if isAddingMapping {
                    addMappingForm
                } else {
                    Button(action: { isAddingMapping = true }) {
                        Label("Add Mapping", systemImage: "plus")
                    }

                    // Presets menu
                    Menu {
                        ForEach(KeyRemapManager.presets, id: \.name) { preset in
                            Button(preset.name) {
                                let mapping = KeyMapping(
                                    from: preset.from, fromLabel: preset.fromLabel,
                                    to: preset.to, toLabel: preset.toLabel
                                )
                                manager.addMapping(mapping)
                            }
                        }
                    } label: {
                        Label("Presets", systemImage: "list.bullet")
                    }

                    Spacer()
                }
            }
            .padding(12)
        }
    }

    // MARK: - Mapping Row

    private func mappingRow(_ mapping: KeyMapping) -> some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { mapping.enabled },
                set: { _ in manager.toggleMapping(mapping) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            keyBadge(mapping.fromLabel)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            keyBadge(mapping.toLabel)

            Spacer()

            Text(mapping.enabled ? "Active" : "Disabled")
                .font(.caption)
                .foregroundStyle(mapping.enabled ? .green : .secondary)

            Button(action: { manager.removeMapping(mapping) }) {
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

    // MARK: - Add Mapping Form

    private var addMappingForm: some View {
        HStack(spacing: 12) {
            Text("From:")
                .font(.caption)
            recordButton(label: newFromLabel.isEmpty ? "Press key" : newFromLabel, isRecording: $recordingFrom) { code, label in
                newFrom = code
                newFromLabel = label
            }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            Text("To:")
                .font(.caption)
            recordButton(label: newToLabel.isEmpty ? "Press key" : newToLabel, isRecording: $recordingTo) { code, label in
                newTo = code
                newToLabel = label
            }

            Button("Add") {
                guard !newFromLabel.isEmpty && !newToLabel.isEmpty else { return }
                let mapping = KeyMapping(
                    from: newFrom, fromLabel: newFromLabel,
                    to: newTo, toLabel: newToLabel
                )
                manager.addMapping(mapping)
                isAddingMapping = false
                newFromLabel = ""
                newToLabel = ""
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newFromLabel.isEmpty || newToLabel.isEmpty || newFrom == newTo)

            Button("Cancel") {
                isAddingMapping = false
                recordingFrom = false
                recordingTo = false
                cleanupMonitor()
            }
            .controlSize(.small)

            Spacer()
        }
    }

    private func recordButton(label: String, isRecording: Binding<Bool>, onRecord: @escaping (UInt16, String) -> Void) -> some View {
        Button(action: {
            // Turn off other recording
            recordingFrom = false
            recordingTo = false
            cleanupMonitor()
            isRecording.wrappedValue = true
            installMonitor(isRecording: isRecording, onRecord: onRecord)
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
    }

    private func installMonitor(isRecording: Binding<Bool>, onRecord: @escaping (UInt16, String) -> Void) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let code = event.keyCode
            let label = HotkeyManager.shared.keyCodeToString(code)
            onRecord(code, label)
            isRecording.wrappedValue = false
            self.cleanupMonitor()
            return nil
        }
    }

    private func cleanupMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
