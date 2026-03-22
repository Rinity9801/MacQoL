import Foundation
import CoreGraphics

/// Base class for features that intercept keyboard events via CGEventTap.
///
/// Subclasses override `handleEvent(_:type:)` to process intercepted events.
/// The event tap runs on a system thread — `handleEvent` must be thread-safe.
/// Use `lock` to protect any shared mutable state accessed from `handleEvent`.
///
/// Used by: SnapTapManager, KeyRemapManager
@MainActor
class EventTapBase {
    nonisolated(unsafe) var eventTapRef: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    let lock = NSLock()

    /// Override in subclass. Called on the event tap thread (NOT main).
    /// Return the event to pass it through (possibly modified),
    /// or nil to suppress it.
    nonisolated func handleEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        return event
    }

    // MARK: - Lifecycle

    /// Start intercepting keyboard events. Requires Accessibility permission.
    /// Returns true if the tap was created successfully.
    @discardableResult
    func startTap(eventsOfInterest mask: CGEventMask? = nil) -> Bool {
        guard eventTapRef == nil else { return true }

        let defaultMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask ?? defaultMask,
            callback: eventTapBaseCallback,
            userInfo: selfPtr
        ) else {
            Log.error("Failed to create CGEventTap — check Accessibility permission")
            return false
        }

        eventTapRef = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        Log.info("\(type(of: self)) event tap started")
        return true
    }

    /// Stop intercepting events and tear down the tap.
    func stopTap() {
        if let tap = eventTapRef {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTapRef = nil
        runLoopSource = nil

        Log.info("\(type(of: self)) event tap stopped")
    }
}

// MARK: - C Callback

/// Global C callback that dispatches to the appropriate EventTapBase subclass.
private func eventTapBaseCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable tap if macOS disabled it due to timeout
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let base = Unmanaged<EventTapBase>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = base.eventTapRef {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp || type == .flagsChanged,
          let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let base = Unmanaged<EventTapBase>.fromOpaque(userInfo).takeUnretainedValue()

    if let result = base.handleEvent(event, type: type) {
        return Unmanaged.passUnretained(result)
    } else {
        return nil // suppress event
    }
}
