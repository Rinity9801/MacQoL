import AppKit

class OverlayNSWindow: NSPanel {
    var onEscapeKey: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnterKey: (() -> Void)?
    var onNumberKey: ((Int) -> Void)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: backingStoreType, defer: flag)
        self.acceptsMouseMovedEvents = true
        self.isFloatingPanel = true
        self.worksWhenModal = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        let hasCommand = event.modifierFlags.contains(.command)
        let chars = event.charactersIgnoringModifiers

        // Cmd+W to close
        if hasCommand && chars == "w" {
            onEscapeKey?()
            return
        }

        switch Int(event.keyCode) {
        case 53: // Escape
            onEscapeKey?()
        case 126: // Up arrow
            onArrowUp?()
        case 125: // Down arrow
            onArrowDown?()
        case 36: // Enter
            onEnterKey?()
        default:
            if let chars, let char = chars.first {
                if char == "w" {
                    onArrowUp?()
                } else if char == "s" {
                    onArrowDown?()
                } else if char.isNumber, let num = Int(String(char)), num >= 1 && num <= 9 {
                    onNumberKey?(num)
                } else {
                    super.keyDown(with: event)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
