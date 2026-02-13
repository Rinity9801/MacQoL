import AppKit
import SwiftUI
import Carbon

/// Manages the clipboard overlay window lifecycle — extracted from clipboard-history's AppDelegate
@MainActor
final class ClipboardOverlayController {
    private var overlayWindow: OverlayNSWindow?
    private var keyMonitor: Any?
    private var selectedIndex = 0
    private let clipboardManager: ClipboardManager

    init(clipboardManager: ClipboardManager) {
        self.clipboardManager = clipboardManager
    }

    func showOverlay() {
        let cursorLocation = getTextCursorLocation() ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(cursorLocation, $0.frame, false) }) ?? NSScreen.main

        guard let screen = screen else { return }

        if overlayWindow == nil {
            let savedFrame = UserDefaults.standard.string(forKey: "overlayWindowFrame")
            let defaultRect = NSRect(x: 0, y: 0, width: 360, height: 280)
            let initialRect: NSRect

            if let savedFrame = savedFrame {
                initialRect = NSRectFromString(savedFrame)
            } else {
                initialRect = defaultRect
            }

            let window = OverlayNSWindow(
                contentRect: initialRect,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )

            window.onEscapeKey = { [weak self] in
                self?.hideOverlay()
            }
            window.onArrowUp = { [weak self] in
                guard let self else { return }
                if self.selectedIndex > 0 {
                    self.selectedIndex -= 1
                    self.updateOverlaySelection()
                }
            }
            window.onArrowDown = { [weak self] in
                guard let self else { return }
                if self.selectedIndex < self.clipboardManager.items.count - 1 {
                    self.selectedIndex += 1
                    self.updateOverlaySelection()
                }
            }
            window.onEnterKey = { [weak self] in
                guard let self else { return }
                if !self.clipboardManager.items.isEmpty && self.selectedIndex < self.clipboardManager.items.count {
                    self.pasteItem(self.clipboardManager.items[self.selectedIndex])
                }
            }
            window.onNumberKey = { [weak self] num in
                guard let self else { return }
                if num >= 1 && num <= self.clipboardManager.items.count {
                    self.pasteItem(self.clipboardManager.items[num - 1])
                }
            }

            window.level = .modalPanel
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isMovableByWindowBackground = true
            window.appearance = nil

            let swiftUIView = OverlayView(
                clipboardManager: clipboardManager,
                selectedIndex: selectedIndex,
                onClose: { [weak self] in self?.hideOverlay() },
                onSelect: { [weak self] item in self?.pasteItem(item) }
            )

            let hostingView = NSHostingView(rootView: swiftUIView)
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = .clear
            window.contentView = hostingView

            overlayWindow = window
        }

        // Position window next to the cursor
        if let window = overlayWindow {
            let windowFrame = window.frame
            let screenFrame = screen.visibleFrame
            let margin: CGFloat = 4

            var x = cursorLocation.x + 4

            if x + windowFrame.width > screenFrame.maxX - margin {
                x = cursorLocation.x - windowFrame.width - 4
            }
            x = max(screenFrame.minX + margin, min(x, screenFrame.maxX - windowFrame.width - margin))

            let yBelow = cursorLocation.y - windowFrame.height - 4

            if yBelow >= screenFrame.minY + margin {
                window.setFrameOrigin(NSPoint(x: x, y: yBelow))
            } else {
                let yAbove = cursorLocation.y + 20
                if yAbove + windowFrame.height <= screenFrame.maxY - margin {
                    window.setFrameOrigin(NSPoint(x: x, y: yAbove))
                } else {
                    let yMax = screenFrame.maxY - windowFrame.height - margin
                    window.setFrameOrigin(NSPoint(x: x, y: max(yMax, screenFrame.minY + margin)))
                }
            }
        }

        selectedIndex = 0
        updateOverlaySelection()

        NSApp.setActivationPolicy(.regular)
        overlayWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Install local key monitor
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.overlayWindow?.isVisible == true else { return event }
                switch Int(event.keyCode) {
                case 53:
                    self.hideOverlay()
                    return nil
                case 126:
                    if self.selectedIndex > 0 {
                        self.selectedIndex -= 1
                        self.updateOverlaySelection()
                    }
                    return nil
                case 125:
                    if self.selectedIndex < self.clipboardManager.items.count - 1 {
                        self.selectedIndex += 1
                        self.updateOverlaySelection()
                    }
                    return nil
                case 36:
                    if !self.clipboardManager.items.isEmpty, self.selectedIndex < self.clipboardManager.items.count {
                        self.pasteItem(self.clipboardManager.items[self.selectedIndex])
                    }
                    return nil
                default:
                    if let chars = event.charactersIgnoringModifiers,
                       let char = chars.first, char.isNumber,
                       let num = Int(String(char)),
                       num >= 1, num <= self.clipboardManager.items.count {
                        self.pasteItem(self.clipboardManager.items[num - 1])
                        return nil
                    }
                    return event
                }
            }
        }
    }

    func hideOverlay() {
        overlayWindow?.orderOut(nil)

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        // Only go back to accessory if the hub window isn't visible
        if !AppState.shared.isHubWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func updateOverlaySelection() {
        let swiftUIView = OverlayView(
            clipboardManager: clipboardManager,
            selectedIndex: selectedIndex,
            onClose: { [weak self] in self?.hideOverlay() },
            onSelect: { [weak self] item in self?.pasteItem(item) }
        )
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear
        overlayWindow?.contentView = hostingView
    }

    private func pasteItem(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if item.type == .image, let imageData = item.imageData {
            pasteboard.setData(imageData, forType: .tiff)
        } else {
            pasteboard.setString(item.content, forType: .string)
        }

        hideOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Text Cursor Helpers

    private func getTextCursorLocation() -> NSPoint? {
        if let tv = activeTextView(), let caret = caretRect(from: tv) {
            guard let primaryScreen = NSScreen.screens.first else { return nil }
            let screenHeight = primaryScreen.frame.height
            let nsY = screenHeight - caret.maxY
            return NSPoint(x: caret.midX, y: nsY)
        }
        return nil
    }

    private func activeTextView() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        if result == .success, let element = focusedElement {
            return (element as! AXUIElement)
        }

        return nil
    }

    private func caretRect(from textView: AXUIElement) -> CGRect? {
        var selectedRange: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(textView, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

        if rangeResult == .success, let range = selectedRange {
            var boundsValue: CFTypeRef?
            let boundsResult = AXUIElementCopyParameterizedAttributeValue(
                textView,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                range,
                &boundsValue
            )

            if boundsResult == .success, let bounds = boundsValue {
                var rect = CGRect.zero
                if AXValueGetValue(bounds as! AXValue, .cgRect, &rect) {
                    return rect
                }
            }
        }

        return nil
    }
}
