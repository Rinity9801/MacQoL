import Foundation
import Carbon
import AppKit
import SwiftUI
import Combine

/// Global hotkey registration via Carbon EventHotKey API.
///
/// Registers system-wide keyboard shortcuts that work even when the app isn't focused.
/// Each hotkey has a unique ID dispatched through a single Carbon event handler.
///
/// ## Hotkey IDs
/// - 1: Clipboard overlay
/// - 2: Save recording clip
/// - 3: Toggle recording
/// - 4: Toggle focus session
///
/// ## Adding a new hotkey
/// 1. Add @AppStorage properties for keycode + modifiers
/// 2. Add an EventHotKeyRef property
/// 3. Add a callback closure property
/// 4. Register in `registerAllHotkeys()` with the next ID
/// 5. Handle in the event handler switch
/// 6. Add display string in `updateDisplayStrings()`
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    // Display strings
    @Published var clipboardHotkeyDisplay: String = ""
    @Published var saveClipHotkeyDisplay: String = ""
    @Published var toggleRecordingHotkeyDisplay: String = ""
    @Published var toggleFocusHotkeyDisplay: String = ""

    // Hotkey refs
    private var clipboardHotkeyRef: EventHotKeyRef?
    private var saveClipHotkeyRef: EventHotKeyRef?
    private var toggleRecordingHotkeyRef: EventHotKeyRef?
    private var toggleFocusHotkeyRef: EventHotKeyRef?

    private var eventHandler: EventHandlerRef?

    // Callbacks
    var onClipboardHotkeyPressed: (() -> Void)?
    var onSaveClipHotkeyPressed: (() -> Void)?
    var onToggleRecordingHotkeyPressed: (() -> Void)?
    var onToggleFocusHotkeyPressed: (() -> Void)?

    // Settings keys (stored as Cocoa modifier flags raw value)
    @AppStorage("clipboardHotkeyCode") private var clipboardHotkeyCode: Int = 9 // V
    @AppStorage("clipboardHotkeyModifiers") private var clipboardHotkeyModifiers: Int = 0x180108 // Cmd+Option

    @AppStorage("saveClipHotkeyCode2") private var saveClipHotkeyCode: Int = 1 // S
    @AppStorage("saveClipHotkeyModifiers2") private var saveClipHotkeyModifiers: Int = 0x1A0108 // Cmd+Option+Shift

    @AppStorage("toggleRecordingHotkeyCode2") private var toggleRecordingHotkeyCode: Int = 15 // R
    @AppStorage("toggleRecordingHotkeyModifiers2") private var toggleRecordingHotkeyModifiers: Int = 0x1A0108 // Cmd+Option+Shift

    @AppStorage("toggleFocusHotkeyCode") private var toggleFocusHotkeyCode: Int = 3 // F
    @AppStorage("toggleFocusHotkeyModifiers") private var toggleFocusHotkeyModifiers: Int = 0x180108 // Cmd+Option

    private static let signature = OSType(0x4D514F4C) // 'MQOL'

    private init() {
        setupEventHandler()
        updateDisplayStrings()
        registerAllHotkeys()
    }

    deinit {
        unregisterAllHotkeys()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Setup

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            switch hotKeyID.id {
            case 1:
                manager.onClipboardHotkeyPressed?()
            case 2:
                manager.onSaveClipHotkeyPressed?()
            case 3:
                manager.onToggleRecordingHotkeyPressed?()
            case 4:
                manager.onToggleFocusHotkeyPressed?()
            default:
                break
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    // MARK: - Register/Unregister

    func registerAllHotkeys() {
        unregisterAllHotkeys()

        clipboardHotkeyRef = registerHotkey(
            id: 1,
            keyCode: UInt32(clipboardHotkeyCode),
            cocoaModifiers: UInt32(clipboardHotkeyModifiers)
        )

        saveClipHotkeyRef = registerHotkey(
            id: 2,
            keyCode: UInt32(saveClipHotkeyCode),
            cocoaModifiers: UInt32(saveClipHotkeyModifiers)
        )

        toggleRecordingHotkeyRef = registerHotkey(
            id: 3,
            keyCode: UInt32(toggleRecordingHotkeyCode),
            cocoaModifiers: UInt32(toggleRecordingHotkeyModifiers)
        )

        toggleFocusHotkeyRef = registerHotkey(
            id: 4,
            keyCode: UInt32(toggleFocusHotkeyCode),
            cocoaModifiers: UInt32(toggleFocusHotkeyModifiers)
        )

        updateDisplayStrings()
    }

    private func registerHotkey(id: UInt32, keyCode: UInt32, cocoaModifiers: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let carbonMods = carbonModifiers(from: cocoaModifiers)
        let hotKeyID = EventHotKeyID(signature: HotkeyManager.signature, id: id)

        RegisterEventHotKey(
            keyCode,
            carbonMods,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        return ref
    }

    func unregisterAllHotkeys() {
        for ref in [clipboardHotkeyRef, saveClipHotkeyRef, toggleRecordingHotkeyRef, toggleFocusHotkeyRef] {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        clipboardHotkeyRef = nil
        saveClipHotkeyRef = nil
        toggleRecordingHotkeyRef = nil
        toggleFocusHotkeyRef = nil
    }

    // MARK: - Update Individual Hotkeys

    func setClipboardHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        clipboardHotkeyCode = Int(keyCode)
        clipboardHotkeyModifiers = Int(modifiers.rawValue)
        registerAllHotkeys()
    }

    func setSaveClipHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        saveClipHotkeyCode = Int(keyCode)
        saveClipHotkeyModifiers = Int(modifiers.rawValue)
        registerAllHotkeys()
    }

    func setToggleRecordingHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        toggleRecordingHotkeyCode = Int(keyCode)
        toggleRecordingHotkeyModifiers = Int(modifiers.rawValue)
        registerAllHotkeys()
    }

    func setToggleFocusHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        toggleFocusHotkeyCode = Int(keyCode)
        toggleFocusHotkeyModifiers = Int(modifiers.rawValue)
        registerAllHotkeys()
    }

    // MARK: - Display Strings

    private func updateDisplayStrings() {
        clipboardHotkeyDisplay = hotkeyDisplayString(
            keyCode: UInt16(clipboardHotkeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(clipboardHotkeyModifiers))
        )
        saveClipHotkeyDisplay = hotkeyDisplayString(
            keyCode: UInt16(saveClipHotkeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(saveClipHotkeyModifiers))
        )
        toggleRecordingHotkeyDisplay = hotkeyDisplayString(
            keyCode: UInt16(toggleRecordingHotkeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(toggleRecordingHotkeyModifiers))
        )
        toggleFocusHotkeyDisplay = hotkeyDisplayString(
            keyCode: UInt16(toggleFocusHotkeyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(toggleFocusHotkeyModifiers))
        )
    }

    private func hotkeyDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("\u{2303}") }
        if modifiers.contains(.option) { parts.append("\u{2325}") }
        if modifiers.contains(.shift) { parts.append("\u{21E7}") }
        if modifiers.contains(.command) { parts.append("\u{2318}") }
        if modifiers.contains(.function) { parts.append("fn") }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    // MARK: - Helpers

    private func carbonModifiers(from cocoaModifiers: UInt32) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(cocoaModifiers))
        var result: UInt32 = 0

        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }

        return result
    }

    func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyCodeMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'",
            41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`",
            36: "\u{21A9}", 48: "\u{21E5}", 49: "Space", 51: "\u{232B}", 53: "\u{238B}",
            71: "Clear", 76: "\u{2305}", 115: "Home", 116: "\u{21DE}",
            117: "\u{2326}", 119: "End", 121: "\u{21DF}",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16",
            64: "F17", 79: "F18", 80: "F19", 90: "F20",
            65: "Num.", 67: "Num*", 69: "Num+", 75: "Num/",
            78: "Num-", 81: "Num=", 82: "Num0", 83: "Num1",
            84: "Num2", 85: "Num3", 86: "Num4", 87: "Num5",
            88: "Num6", 89: "Num7", 91: "Num8", 92: "Num9",
        ]

        return keyCodeMap[keyCode] ?? "Key\(keyCode)"
    }
}
