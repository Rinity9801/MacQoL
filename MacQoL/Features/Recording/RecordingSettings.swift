import Foundation
import SwiftUI
import Combine

enum BufferDuration: Int, CaseIterable, Identifiable {
    case seconds30 = 30
    case minute1 = 60
    case minutes2 = 120
    case minutes5 = 300
    case minutes10 = 600

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .seconds30: return "30 seconds"
        case .minute1: return "1 minute"
        case .minutes2: return "2 minutes"
        case .minutes5: return "5 minutes"
        case .minutes10: return "10 minutes"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case original = "original"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low (720p)"
        case .medium: return "Medium (900p)"
        case .high: return "High (1080p)"
        case .original: return "Original"
        }
    }

    var height: Int? {
        switch self {
        case .low: return 720
        case .medium: return 900
        case .high: return 1080
        case .original: return nil
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue) FPS"
    }
}

enum EncoderType: String, CaseIterable, Identifiable {
    case h264 = "h264"
    case hevc = "hevc"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC (H.265)"
        }
    }
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case display = "display"
    case window = "window"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .display: return "Full Screen"
        case .window: return "Specific Window"
        }
    }
}

final class RecordingSettings: ObservableObject {
    static let shared = RecordingSettings()

    @AppStorage("bufferDuration") var bufferDurationRaw: Int = BufferDuration.minutes2.rawValue
    @AppStorage("videoQuality") var videoQualityRaw: String = VideoQuality.high.rawValue
    @AppStorage("frameRate") var frameRateRaw: Int = FrameRate.fps60.rawValue
    @AppStorage("videoEncoder") var videoEncoderRaw: String = EncoderType.h264.rawValue
    @AppStorage("captureMode") var captureModeRaw: String = CaptureMode.display.rawValue

    @AppStorage("systemAudioEnabled") var systemAudioEnabled: Bool = true
    @AppStorage("microphoneEnabled") var microphoneEnabled: Bool = false
    @AppStorage("selectedMicrophoneID") var selectedMicrophoneID: String = ""

    @AppStorage("saveLocation") var saveLocation: String = ""
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false

    // Hotkey settings
    @AppStorage("saveHotkeyCode") var saveHotkeyCode: Int = 1 // S key
    @AppStorage("saveHotkeyModifiers") var saveHotkeyModifiers: Int = 0x100108 // Cmd+Shift

    @AppStorage("toggleHotkeyCode") var toggleHotkeyCode: Int = 15 // R key
    @AppStorage("toggleHotkeyModifiers") var toggleHotkeyModifiers: Int = 0x100108 // Cmd+Shift

    var bufferDuration: BufferDuration {
        get { BufferDuration(rawValue: bufferDurationRaw) ?? .minutes2 }
        set { bufferDurationRaw = newValue.rawValue }
    }

    var videoQuality: VideoQuality {
        get { VideoQuality(rawValue: videoQualityRaw) ?? .high }
        set { videoQualityRaw = newValue.rawValue }
    }

    var frameRate: FrameRate {
        get { FrameRate(rawValue: frameRateRaw) ?? .fps60 }
        set { frameRateRaw = newValue.rawValue }
    }

    var encoderType: EncoderType {
        get { EncoderType(rawValue: videoEncoderRaw) ?? .h264 }
        set { videoEncoderRaw = newValue.rawValue }
    }

    var captureMode: CaptureMode {
        get { CaptureMode(rawValue: captureModeRaw) ?? .display }
        set { captureModeRaw = newValue.rawValue }
    }

    var saveLocationURL: URL {
        if saveLocation.isEmpty {
            let moviesURL = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first!
            return moviesURL.appendingPathComponent("MacQoL")
        }
        return URL(fileURLWithPath: saveLocation)
    }

    private init() {
        try? FileManager.default.createDirectory(at: saveLocationURL, withIntermediateDirectories: true)
    }
}
