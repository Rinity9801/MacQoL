import Foundation
import AVFoundation
import ScreenCaptureKit

enum PermissionStatus {
    case granted
    case denied
    case notDetermined
}

final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    // MARK: - Screen Recording Permission

    func checkScreenRecordingPermission() async -> PermissionStatus {
        do {
            _ = try await SCShareableContent.current
            return .granted
        } catch {
            if let scError = error as? SCStreamError {
                switch scError.code {
                case .userDeclined:
                    return .denied
                default:
                    return .notDetermined
                }
            }
            return .denied
        }
    }

    func requestScreenRecordingPermission() async -> Bool {
        let status = await checkScreenRecordingPermission()
        return status == .granted
    }

    // MARK: - Microphone Permission

    func checkMicrophonePermission() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    func requestMicrophonePermission() async -> Bool {
        let status = checkMicrophonePermission()

        switch status {
        case .granted:
            return true
        case .denied:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Accessibility Permission

    func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Open System Preferences

    func openScreenRecordingPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophonePreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
