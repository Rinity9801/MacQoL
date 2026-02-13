import Foundation
import ScreenCaptureKit
import CoreMedia
import AVFoundation

protocol CaptureEngineDelegate: AnyObject {
    func captureEngine(_ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer)
    func captureEngine(_ engine: CaptureEngine, didFailWithError error: Error)
}

final class CaptureEngine: NSObject {
    weak var delegate: CaptureEngineDelegate?

    private var stream: SCStream?
    private var streamOutput: CaptureStreamOutput?
    private let videoQueue = DispatchQueue(label: "com.macqol.capture.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.macqol.capture.audio", qos: .userInteractive)

    private(set) var isCapturing = false
    private(set) var selectedDisplay: SCDisplay?
    private(set) var selectedWindow: SCWindow?

    func getAvailableDisplays() async throws -> [SCDisplay] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays
    }

    func getAvailableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.filter { window in
            window.isOnScreen &&
            window.title != nil &&
            !window.title!.isEmpty &&
            window.owningApplication?.bundleIdentifier != "com.apple.dock" &&
            window.owningApplication?.bundleIdentifier != "com.apple.WindowManager"
        }
    }

    func startCapture(
        display: SCDisplay,
        frameRate: Int,
        quality: VideoQuality,
        captureSystemAudio: Bool
    ) async throws {
        guard !isCapturing else { return }

        selectedDisplay = display
        selectedWindow = nil

        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await startStream(filter: filter, frameRate: frameRate, quality: quality, captureSystemAudio: captureSystemAudio)
    }

    func startCapture(
        window: SCWindow,
        frameRate: Int,
        quality: VideoQuality,
        captureSystemAudio: Bool
    ) async throws {
        guard !isCapturing else { return }

        selectedWindow = window
        selectedDisplay = nil

        let filter = SCContentFilter(desktopIndependentWindow: window)
        try await startStream(filter: filter, frameRate: frameRate, quality: quality, captureSystemAudio: captureSystemAudio)
    }

    private func startStream(
        filter: SCContentFilter,
        frameRate: Int,
        quality: VideoQuality,
        captureSystemAudio: Bool
    ) async throws {
        let config = SCStreamConfiguration()

        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))
        config.queueDepth = 6

        if let targetHeight = quality.height {
            let aspectRatio = filter.contentRect.width / filter.contentRect.height
            config.height = targetHeight
            config.width = Int(Double(targetHeight) * aspectRatio)
        } else {
            config.width = Int(filter.contentRect.width)
            config.height = Int(filter.contentRect.height)
        }

        config.pixelFormat = kCVPixelFormatType_32BGRA

        config.capturesAudio = captureSystemAudio
        config.sampleRate = 48000
        config.channelCount = 2

        let stream = SCStream(filter: filter, configuration: config, delegate: self)

        let output = CaptureStreamOutput(delegate: self)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: videoQueue)

        if captureSystemAudio {
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)
        }

        self.stream = stream
        self.streamOutput = output

        try await stream.startCapture()
        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing, let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("Error stopping capture: \(error)")
        }

        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
    }

    func updateConfiguration(frameRate: Int, quality: VideoQuality) async throws {
        guard let stream = stream else { return }

        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(frameRate))

        if let targetHeight = quality.height {
            if let display = selectedDisplay {
                let aspectRatio = display.width / display.height
                config.height = targetHeight
                config.width = Int(Double(targetHeight) * Double(aspectRatio))
            }
        }

        try await stream.updateConfiguration(config)
    }
}

extension CaptureEngine: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isCapturing = false
        delegate?.captureEngine(self, didFailWithError: error)
    }
}

private class CaptureStreamOutput: NSObject, SCStreamOutput {
    weak var delegate: CaptureEngine?

    init(delegate: CaptureEngine) {
        self.delegate = delegate
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        switch type {
        case .screen:
            delegate?.delegate?.captureEngine(delegate!, didOutputVideoSampleBuffer: sampleBuffer)
        case .audio:
            delegate?.delegate?.captureEngine(delegate!, didOutputAudioSampleBuffer: sampleBuffer)
        case .microphone:
            break
        @unknown default:
            break
        }
    }
}
