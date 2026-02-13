import AppKit

class OverlayNSWindow: NSWindow {
    var onEscapeKey: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnterKey: (() -> Void)?
    var onNumberKey: ((Int) -> Void)?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            onEscapeKey?()
        case 126:
            onArrowUp?()
        case 125:
            onArrowDown?()
        case 36:
            onEnterKey?()
        default:
            if let chars = event.charactersIgnoringModifiers,
               let char = chars.first,
               char.isNumber,
               let num = Int(String(char)),
               num >= 1 && num <= 9 {
                onNumberKey?(num)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
