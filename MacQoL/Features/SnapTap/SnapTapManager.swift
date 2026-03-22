import Foundation
import AppKit
import CoreGraphics

/// A pair of opposing keys for SOCD (Simultaneous Opposing Cardinal Directions) resolution.
///
/// When both keys in a pair are physically held, the most recently pressed key wins.
/// Releasing the winner reactivates the other if it's still held — giving zero-deadzone
/// direction changes for gaming (similar to Razer Snap Tap).
struct SnapTapPair: Identifiable, Codable, Equatable {
    let id: UUID
    var keyA: UInt16
    var keyB: UInt16
    var labelA: String
    var labelB: String
    var enabled: Bool

    init(keyA: UInt16, labelA: String, keyB: UInt16, labelB: String, enabled: Bool = true) {
        self.id = UUID()
        self.keyA = keyA
        self.labelA = labelA
        self.keyB = keyB
        self.labelB = labelB
        self.enabled = enabled
    }
}

/// Manages SOCD resolution for configurable key pairs via CGEventTap.
///
/// ## Threading
/// `handleEvent` is called on the event tap thread.
/// `pairStates` and `activePairs` are protected by `lock` (inherited from EventTapBase).
/// Published properties are only mutated on @MainActor.
@MainActor
final class SnapTapManager: EventTapBase, ObservableObject {
    static let shared = SnapTapManager()

    @Published var pairs: [SnapTapPair] = []
    @Published var isActive = false

    /// Snapshot of enabled pairs for the event tap callback (lock-protected).
    nonisolated(unsafe) private var activePairs: [SnapTapPair] = []

    /// Per-pair physical key state (lock-protected).
    nonisolated(unsafe) private var pairStates: [UUID: PairState] = [:]

    private struct PairState {
        var aHeld = false
        var bHeld = false
        var lastPressed: UInt16? = nil
    }

    private override init() {
        super.init()
        loadPairs()
        if pairs.isEmpty {
            pairs = Self.defaultPairs
            savePairs()
        }
    }

    /// Default SOCD pairs: WASD + arrow keys.
    static let defaultPairs: [SnapTapPair] = [
        SnapTapPair(keyA: 0, labelA: "A", keyB: 2, labelB: "D"),
        SnapTapPair(keyA: 13, labelA: "W", keyB: 1, labelB: "S"),
        SnapTapPair(keyA: 123, labelA: "←", keyB: 124, labelB: "→"),
        SnapTapPair(keyA: 126, labelA: "↑", keyB: 125, labelB: "↓"),
    ]

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }
        syncActivePairs()
        if startTap() {
            isActive = true
        }
    }

    func stop() {
        guard isActive else { return }
        stopTap()
        isActive = false
    }

    func toggle() {
        if isActive { stop() } else { start() }
    }

    // MARK: - Event Processing (called on event tap thread)

    override nonisolated func handleEvent(_ event: CGEvent, type: CGEventType) -> CGEvent? {
        guard type == .keyDown || type == .keyUp else { return event }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = (type == .keyDown)

        // Ignore OS auto-repeat
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return event }

        lock.lock()
        defer { lock.unlock() }

        guard let pair = activePairs.first(where: { $0.keyA == keyCode || $0.keyB == keyCode }),
              var state = pairStates[pair.id] else {
            return event // not in any pair
        }

        let isKeyA = (keyCode == pair.keyA)

        if isDown {
            if isKeyA { state.aHeld = true } else { state.bHeld = true }
            state.lastPressed = keyCode

            if state.aHeld && state.bHeld {
                // Both held — loser gets key-up, winner's key-down passes through
                let losingKey: UInt16 = isKeyA ? pair.keyB : pair.keyA
                pairStates[pair.id] = state
                synthesizeKey(losingKey, down: false, flags: event.flags)
                return event
            } else {
                pairStates[pair.id] = state
                return event
            }
        } else {
            if isKeyA { state.aHeld = false } else { state.bHeld = false }

            let otherHeld = isKeyA ? state.bHeld : state.aHeld
            let otherKey = isKeyA ? pair.keyB : pair.keyA

            if otherHeld {
                // Other key still held — reactivate it
                state.lastPressed = otherKey
                pairStates[pair.id] = state
                synthesizeKey(otherKey, down: true, flags: event.flags)
                return event
            } else {
                pairStates[pair.id] = state
                return event
            }
        }
    }

    private nonisolated func synthesizeKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Pair Management

    func addPair(_ pair: SnapTapPair) {
        pairs.append(pair)
        syncActivePairs()
        savePairs()
    }

    func removePair(_ pair: SnapTapPair) {
        pairs.removeAll { $0.id == pair.id }
        syncActivePairs()
        savePairs()
    }

    func togglePair(_ pair: SnapTapPair) {
        guard let idx = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[idx].enabled.toggle()
        syncActivePairs()
        savePairs()
    }

    /// Rebuild the lock-protected pair snapshot used by the event tap callback.
    private func syncActivePairs() {
        lock.lock()
        activePairs = pairs.filter(\.enabled)
        pairStates = [:]
        for pair in activePairs {
            pairStates[pair.id] = PairState()
        }
        lock.unlock()
    }

    // MARK: - Persistence

    private var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacQoL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snap_tap_pairs.json")
    }

    private func savePairs() {
        do {
            let data = try JSONEncoder().encode(pairs)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.error("Failed to save snap tap pairs", error)
        }
    }

    private func loadPairs() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            pairs = try JSONDecoder().decode([SnapTapPair].self, from: data)
        } catch {
            Log.error("Failed to load snap tap pairs", error)
        }
    }
}
