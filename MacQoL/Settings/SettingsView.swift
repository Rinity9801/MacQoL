import SwiftUI
import AVFoundation
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = RecordingSettings.shared
    @ObservedObject var hotkeyManager = HotkeyManager.shared

    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var isRecordingClipboardHotkey = false
    @State private var isRecordingSaveClipHotkey = false
    @State private var isRecordingToggleRecordingHotkey = false
    @State private var isRecordingToggleFocusHotkey = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            videoTab
                .tabItem { Label("Video", systemImage: "video") }
            audioTab
                .tabItem { Label("Audio", systemImage: "waveform") }
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { loadMicrophones() }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker("Buffer Duration", selection: Binding(
                    get: { settings.bufferDuration },
                    set: { settings.bufferDuration = $0 }
                )) {
                    ForEach(BufferDuration.allCases) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }

                HStack {
                    Text("Save Location")
                    Spacer()
                    Text(settings.saveLocationURL.path)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") { chooseSaveLocation() }
                }

                Toggle("Launch at Login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { newValue in
                        settings.launchAtLogin = newValue
                        updateLaunchAtLogin(newValue)
                    }
                ))
            }

            Section {
                Button("Open Save Folder") {
                    NSWorkspace.shared.open(settings.saveLocationURL)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Video Tab

    private var videoTab: some View {
        Form {
            Section("Quality") {
                Picker("Resolution", selection: Binding(
                    get: { settings.videoQuality },
                    set: { settings.videoQuality = $0 }
                )) {
                    ForEach(VideoQuality.allCases) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }

                Picker("Frame Rate", selection: Binding(
                    get: { settings.frameRate },
                    set: { settings.frameRate = $0 }
                )) {
                    ForEach(FrameRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }

                Picker("Encoder", selection: Binding(
                    get: { settings.encoderType },
                    set: { settings.encoderType = $0 }
                )) {
                    ForEach(EncoderType.allCases) { encoder in
                        Text(encoder.displayName).tag(encoder)
                    }
                }
            }

            Section("Capture Mode") {
                Picker("Default Mode", selection: Binding(
                    get: { settings.captureMode },
                    set: { settings.captureMode = $0 }
                )) {
                    ForEach(CaptureMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Audio Tab

    private var audioTab: some View {
        Form {
            Section("Audio Sources") {
                Toggle("Capture System Audio", isOn: $settings.systemAudioEnabled)
                Toggle("Capture Microphone", isOn: $settings.microphoneEnabled)

                if settings.microphoneEnabled {
                    Picker("Microphone", selection: $settings.selectedMicrophoneID) {
                        Text("Default").tag("")
                        ForEach(availableMicrophones, id: \.uniqueID) { device in
                            Text(device.localizedName).tag(device.uniqueID)
                        }
                    }
                }
            }

            Section("Permissions") {
                HStack {
                    Text("Screen Recording")
                    Spacer()
                    Button("Open Settings") {
                        PermissionManager.shared.openScreenRecordingPreferences()
                    }
                    .buttonStyle(.link)
                }

                HStack {
                    Text("Microphone")
                    Spacer()
                    Button("Open Settings") {
                        PermissionManager.shared.openMicrophonePreferences()
                    }
                    .buttonStyle(.link)
                }

                HStack {
                    Text("Accessibility")
                    Spacer()
                    Button("Open Settings") {
                        PermissionManager.shared.openAccessibilityPreferences()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Hotkeys Tab

    private var hotkeysTab: some View {
        Form {
            Section("Keyboard Shortcuts") {
                HStack {
                    Text("Clipboard Overlay")
                    Spacer()
                    HotkeyRecorderButton(
                        displayString: hotkeyManager.clipboardHotkeyDisplay,
                        isRecording: $isRecordingClipboardHotkey
                    ) { keyCode, modifiers in
                        hotkeyManager.setClipboardHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }

                HStack {
                    Text("Save Clip")
                    Spacer()
                    HotkeyRecorderButton(
                        displayString: hotkeyManager.saveClipHotkeyDisplay,
                        isRecording: $isRecordingSaveClipHotkey
                    ) { keyCode, modifiers in
                        hotkeyManager.setSaveClipHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }

                HStack {
                    Text("Toggle Recording")
                    Spacer()
                    HotkeyRecorderButton(
                        displayString: hotkeyManager.toggleRecordingHotkeyDisplay,
                        isRecording: $isRecordingToggleRecordingHotkey
                    ) { keyCode, modifiers in
                        hotkeyManager.setToggleRecordingHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }

                HStack {
                    Text("Toggle Focus")
                    Spacer()
                    HotkeyRecorderButton(
                        displayString: hotkeyManager.toggleFocusHotkeyDisplay,
                        isRecording: $isRecordingToggleFocusHotkey
                    ) { keyCode, modifiers in
                        hotkeyManager.setToggleFocusHotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Click a shortcut button and press your desired key combination.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Supported: \u{2318} \u{2325} \u{2303} \u{21E7} + any key, or fn + F-keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Press Escape to cancel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Actions

    private func loadMicrophones() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoverySession.devices
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            settings.saveLocation = url.path
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderButton: View {
    let displayString: String
    @Binding var isRecording: Bool
    let onRecorded: (UInt16, NSEvent.ModifierFlags) -> Void

    var body: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "Press keys..." : displayString)
                .frame(minWidth: 120)
                .padding(.horizontal, 8)
        }
        .buttonStyle(.bordered)
        .background(
            HotkeyRecorderView(isRecording: $isRecording, onRecorded: onRecorded)
        )
    }
}

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onRecorded: (UInt16, NSEvent.ModifierFlags) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyCapturingView()
        view.onKeyRecorded = { keyCode, modifiers in
            onRecorded(keyCode, modifiers)
            isRecording = false
        }
        view.onCancelled = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? HotkeyCapturingView else { return }
        view.isRecording = isRecording
        if isRecording {
            view.window?.makeFirstResponder(view)
        }
    }
}

class HotkeyCapturingView: NSView {
    var onKeyRecorded: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onCancelled: (() -> Void)?
    var isRecording = false

    private let supportedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control, .function]

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 {
            onCancelled?()
            return
        }

        let modifiers = event.modifierFlags.intersection(supportedModifiers)

        let hasStandardModifier = !modifiers.intersection([.command, .shift, .option, .control]).isEmpty
        let isFunctionKey = (event.keyCode >= 96 && event.keyCode <= 122) ||
                           event.keyCode == 105 || event.keyCode == 107 ||
                           event.keyCode == 113 || event.keyCode == 106

        guard hasStandardModifier || (modifiers.contains(.function) && isFunctionKey) else {
            return
        }

        onKeyRecorded?(event.keyCode, modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }
}
