import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Combine
import UserNotifications

enum RecordingState: Equatable {
    case idle
    case buffering
    case saving
    case error(String)
}

@MainActor
final class RecordingManager: ObservableObject {
    static let shared = RecordingManager()

    @Published private(set) var state: RecordingState = .idle
    @Published private(set) var bufferDuration: TimeInterval = 0
    @Published private(set) var availableDisplays: [SCDisplay] = []
    @Published private(set) var availableWindows: [SCWindow] = []
    @Published var selectedDisplayIndex: Int = 0
    @Published var selectedWindowIndex: Int = 0

    private let captureEngine = CaptureEngine()
    private let audioEngine = AudioEngine()
    private nonisolated(unsafe) let videoEncoder = VideoEncoder()
    private let fileWriter = FileWriter()
    private nonisolated(unsafe) var ringBuffer: RingBuffer?

    private let settings = RecordingSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var bufferUpdateTimer: Timer?

    private var captureWidth: Int = 1920
    private var captureHeight: Int = 1080

    private init() {
        setupDelegates()
        setupNotifications()
    }

    private func setupDelegates() {
        captureEngine.delegate = self
        audioEngine.delegate = self
        videoEncoder.delegate = self
        fileWriter.delegate = self
    }

    private func setupNotifications() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func refreshSources() async {
        do {
            availableDisplays = try await captureEngine.getAvailableDisplays()
            availableWindows = try await captureEngine.getAvailableWindows()
        } catch {
            state = .error("Failed to get available sources: \(error.localizedDescription)")
        }
    }

    func startBuffering() async {
        guard state == .idle || state == .error("") else { return }

        let hasScreenPermission = await PermissionManager.shared.requestScreenRecordingPermission()
        guard hasScreenPermission else {
            state = .error("Screen recording permission required")
            PermissionManager.shared.openScreenRecordingPreferences()
            return
        }

        if settings.microphoneEnabled {
            let hasMicPermission = await PermissionManager.shared.requestMicrophonePermission()
            if !hasMicPermission {
                state = .error("Microphone permission required")
                PermissionManager.shared.openMicrophonePreferences()
                return
            }
        }

        do {
            ringBuffer = RingBuffer(maxDurationSeconds: settings.bufferDuration.rawValue)

            if settings.captureMode == .display {
                if availableDisplays.isEmpty {
                    await refreshSources()
                }
                guard !availableDisplays.isEmpty else {
                    state = .error("No displays available")
                    return
                }

                let display = availableDisplays[min(selectedDisplayIndex, availableDisplays.count - 1)]
                captureWidth = display.width
                captureHeight = display.height

                try videoEncoder.setup(
                    width: captureWidth,
                    height: captureHeight,
                    frameRate: settings.frameRate.rawValue,
                    useHEVC: settings.encoderType == .hevc
                )

                try await captureEngine.startCapture(
                    display: display,
                    frameRate: settings.frameRate.rawValue,
                    quality: settings.videoQuality,
                    captureSystemAudio: settings.systemAudioEnabled
                )
            } else {
                if availableWindows.isEmpty {
                    await refreshSources()
                }
                guard !availableWindows.isEmpty else {
                    state = .error("No windows available")
                    return
                }

                let window = availableWindows[min(selectedWindowIndex, availableWindows.count - 1)]
                captureWidth = Int(window.frame.width)
                captureHeight = Int(window.frame.height)

                try videoEncoder.setup(
                    width: captureWidth,
                    height: captureHeight,
                    frameRate: settings.frameRate.rawValue,
                    useHEVC: settings.encoderType == .hevc
                )

                try await captureEngine.startCapture(
                    window: window,
                    frameRate: settings.frameRate.rawValue,
                    quality: settings.videoQuality,
                    captureSystemAudio: settings.systemAudioEnabled
                )
            }

            if settings.microphoneEnabled {
                try audioEngine.startCapture(deviceID: settings.selectedMicrophoneID.isEmpty ? nil : settings.selectedMicrophoneID)
            }

            startBufferUpdateTimer()

            state = .buffering
        } catch {
            state = .error("Failed to start capture: \(error.localizedDescription)")
        }
    }

    func stopBuffering() async {
        guard state == .buffering else { return }

        await captureEngine.stopCapture()
        audioEngine.stopCapture()
        videoEncoder.stop()
        stopBufferUpdateTimer()
        ringBuffer?.clear()

        state = .idle
    }

    func saveClip() {
        guard state == .buffering, let ringBuffer = ringBuffer else { return }

        state = .saving

        let (videoFrames, audioFrames, formatDescription) = ringBuffer.getFrames()

        guard !videoFrames.isEmpty else {
            state = .buffering
            sendNotification(title: "Save Failed", body: "No frames in buffer")
            return
        }

        guard formatDescription != nil else {
            state = .buffering
            sendNotification(title: "Save Failed", body: "No format description available")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "MacQoL_\(dateFormatter.string(from: Date())).mov"
        let outputURL = settings.saveLocationURL.appendingPathComponent(filename)

        try? FileManager.default.createDirectory(at: settings.saveLocationURL, withIntermediateDirectories: true)

        fileWriter.writeFrames(
            videoFrames: videoFrames,
            audioFrames: audioFrames,
            videoFormatDescription: formatDescription,
            to: outputURL
        )
    }

    func toggleBuffering() async {
        if state == .buffering {
            await stopBuffering()
        } else if state == .idle || state == .error("") {
            await startBuffering()
        }
    }

    // MARK: - Timer

    private func startBufferUpdateTimer() {
        bufferUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateBufferDuration()
            }
        }
    }

    private func stopBufferUpdateTimer() {
        bufferUpdateTimer?.invalidate()
        bufferUpdateTimer = nil
        bufferDuration = 0
    }

    private func updateBufferDuration() {
        bufferDuration = ringBuffer?.currentDuration ?? 0
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - CaptureEngineDelegate

extension RecordingManager: CaptureEngineDelegate {
    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoEncoder.encode(sampleBuffer: sampleBuffer)
    }

    nonisolated func captureEngine(_ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        // System audio — skip for now
    }

    nonisolated func captureEngine(_ engine: CaptureEngine, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
}

// MARK: - AudioEngineDelegate

extension RecordingManager: AudioEngineDelegate {
    nonisolated func audioEngine(_ engine: AudioEngine, didOutputSampleBuffer sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let dataPointer = dataPointer else { return }

        let data = Data(bytes: dataPointer, count: length)
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        let frame = EncodedFrame(
            data: data,
            presentationTime: presentationTime,
            duration: duration,
            isKeyframe: true,
            isVideo: false
        )

        ringBuffer?.appendAudio(frame)
    }

    nonisolated func audioEngine(_ engine: AudioEngine, didFailWithError error: Error) {
        Task { @MainActor in
            print("Audio engine error: \(error)")
        }
    }
}

// MARK: - VideoEncoderDelegate

extension RecordingManager: VideoEncoderDelegate {
    nonisolated func videoEncoder(_ encoder: VideoEncoder, didOutputEncodedFrame frame: EncodedFrame) {
        ringBuffer?.appendVideo(frame)
    }

    nonisolated func videoEncoder(_ encoder: VideoEncoder, didOutputFormatDescription formatDescription: CMFormatDescription) {
        ringBuffer?.setVideoFormatDescription(formatDescription)
    }

    nonisolated func videoEncoder(_ encoder: VideoEncoder, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .error(error.localizedDescription)
        }
    }
}

// MARK: - FileWriterDelegate

extension RecordingManager: FileWriterDelegate {
    nonisolated func fileWriter(_ writer: FileWriter, didFinishWritingTo url: URL) {
        Task { @MainActor in
            self.state = .buffering
            self.sendNotification(title: "Clip Saved", body: url.lastPathComponent)

            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }

    nonisolated func fileWriter(_ writer: FileWriter, didFailWithError error: Error) {
        Task { @MainActor in
            self.state = .buffering
            self.sendNotification(title: "Save Failed", body: error.localizedDescription)
        }
    }
}
