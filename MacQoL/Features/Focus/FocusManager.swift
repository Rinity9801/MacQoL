import Foundation
import Combine

enum FocusState: Equatable {
    case idle
    case active
    case paused
}

@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published private(set) var state: FocusState = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published var durationMinutes: Int = 25

    @Published var blockedAppBundleIDs: [String] = [] {
        didSet {
            UserDefaults.standard.set(blockedAppBundleIDs, forKey: "focusBlockedApps")
        }
    }

    @Published var blockedWebsites: [String] = [] {
        didSet {
            UserDefaults.standard.set(blockedWebsites, forKey: "focusBlockedWebsites")
        }
    }

    private var timer: Timer?
    private let appBlocker = AppBlocker()
    private let websiteBlocker = WebsiteBlocker()

    private init() {
        loadSettings()
    }

    private func loadSettings() {
        durationMinutes = UserDefaults.standard.integer(forKey: "focusDuration")
        if durationMinutes == 0 { durationMinutes = 25 }

        blockedAppBundleIDs = UserDefaults.standard.stringArray(forKey: "focusBlockedApps") ?? []
        blockedWebsites = UserDefaults.standard.stringArray(forKey: "focusBlockedWebsites") ?? []
    }

    func startSession() {
        guard state == .idle else { return }

        totalSeconds = durationMinutes * 60
        remainingSeconds = totalSeconds
        state = .active

        UserDefaults.standard.set(durationMinutes, forKey: "focusDuration")

        // Block apps and websites
        appBlocker.startBlocking(bundleIDs: blockedAppBundleIDs)
        websiteBlocker.block(websites: blockedWebsites)

        startTimer()
    }

    func pauseSession() {
        guard state == .active else { return }
        state = .paused
        timer?.invalidate()
        timer = nil
    }

    func resumeSession() {
        guard state == .paused else { return }
        state = .active
        startTimer()
    }

    func stopSession() {
        guard state != .idle else { return }

        timer?.invalidate()
        timer = nil
        state = .idle
        remainingSeconds = 0

        // Unblock
        appBlocker.stopBlocking()
        websiteBlocker.unblock()
    }

    func toggleSession() {
        switch state {
        case .idle:
            startSession()
        case .active:
            pauseSession()
        case .paused:
            resumeSession()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state == .active else { return }

        remainingSeconds -= 1

        if remainingSeconds <= 0 {
            // Session complete
            stopSession()
            NotificationManager.shared.sendNotification(
                title: "Focus Session Complete",
                body: "Great work! You stayed focused for \(durationMinutes) minutes."
            )
        }
    }

    var formattedTimeRemaining: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingSeconds) / Double(totalSeconds)
    }
}
