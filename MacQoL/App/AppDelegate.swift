import AppKit
import SwiftUI
import SwiftData
import Carbon

/// Application lifecycle coordinator.
///
/// Sets up the menu bar status item, clipboard monitoring, global hotkeys,
/// and the main hub window. All feature managers are initialized here or
/// lazily via their `.shared` singletons.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hubWindow: NSWindow?
    private let appState = AppState.shared

    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TodoItem.self,
            MindmapDocument.self,
            MindmapNode.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Clipboard
    private var clipboardManager: ClipboardManager?
    private var clipboardOverlayController: ClipboardOverlayController?

    // Recording
    private let recordingManager = RecordingManager.shared

    // Unified hotkeys
    private let hotkeyManager = HotkeyManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permissions
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // Hide the default window that SwiftUI creates
        for window in NSApplication.shared.windows {
            window.close()
        }

        setupMenuBar()
        setupClipboard()
        setupHotkeys()
        refreshRecordingSources()

        // Show hub window on first launch
        showHubWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager?.stopMonitoring()
        hotkeyManager.unregisterAllHotkeys()
        FocusManager.shared.stopSession()
        Task { @MainActor in
            await recordingManager.stopBuffering()
        }
    }

    // MARK: - Clipboard

    private func setupClipboard() {
        let manager = ClipboardManager()
        manager.startMonitoring()
        clipboardManager = manager
        clipboardOverlayController = ClipboardOverlayController(clipboardManager: manager)
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.onClipboardHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.clipboardOverlayController?.showOverlay()
            }
        }

        hotkeyManager.onSaveClipHotkeyPressed = { [weak self] in
            Task { @MainActor in
                self?.recordingManager.saveClip()
            }
        }

        hotkeyManager.onToggleRecordingHotkeyPressed = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.recordingManager.toggleBuffering()
            }
        }

        hotkeyManager.onToggleFocusHotkeyPressed = {
            Task { @MainActor in
                let fm = FocusManager.shared
                if fm.state == .idle {
                    fm.startSession()
                } else {
                    fm.stopSession()
                }
            }
        }
    }

    // MARK: - Recording

    private func refreshRecordingSources() {
        Task { @MainActor in
            await recordingManager.refreshSources()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "MacQoL")
            button.action = #selector(menuBarClicked)
            button.target = self
        }

        // Update menu bar icon based on recording state
        Task { @MainActor in
            for await _ in recordingManager.$state.values {
                updateMenuBarIcon()
            }
        }
    }

    private func updateMenuBarIcon() {
        guard let button = statusItem?.button else { return }

        let imageName: String
        let tintColor: NSColor?

        switch recordingManager.state {
        case .buffering:
            imageName = "record.circle.fill"
            tintColor = .systemRed
        case .saving:
            imageName = "arrow.down.circle.fill"
            tintColor = .systemOrange
        case .error:
            imageName = "exclamationmark.circle"
            tintColor = .systemYellow
        default:
            imageName = "square.grid.2x2"
            tintColor = nil
        }

        var image = NSImage(systemSymbolName: imageName, accessibilityDescription: "MacQoL")

        if let tintColor = tintColor {
            image = image?.withSymbolConfiguration(.init(paletteColors: [tintColor]))
        }

        button.image = image
    }

    @objc private func menuBarClicked() {
        if let hubWindow, hubWindow.isVisible {
            hubWindow.orderOut(nil)
            appState.isHubWindowVisible = false
        } else {
            showHubWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showHubWindow()
        }
        return true
    }

    func showHubWindow() {
        if hubWindow == nil {
            let hubView = HubView()
                .modelContainer(AppDelegate.sharedModelContainer)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MacQoL"
            window.contentView = NSHostingView(rootView: hubView)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            hubWindow = window
        }

        hubWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        appState.isHubWindowVisible = true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === hubWindow else { return }
        appState.isHubWindowVisible = false
    }
}
