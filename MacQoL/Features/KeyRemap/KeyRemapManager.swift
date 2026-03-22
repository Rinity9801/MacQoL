import Foundation
import AppKit
import CoreGraphics

/// A single key-to-key remapping rule.
struct KeyMapping: Identifiable, Codable, Equatable {
    let id: UUID
    var fromKeyCode: UInt16
    var toKeyCode: UInt16
    var fromLabel: String
    var toLabel: String
    var enabled: Bool

    init(from: UInt16, fromLabel: String, to: UInt16, toLabel: String, enabled: Bool = true) {
        self.id = UUID()
        self.fromKeyCode = from
        self.toKeyCode = to
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.enabled = enabled
    }
}

/// Globally remaps keyboard keys via CGEventTap.
///
/// ## Threading
/// `handleEvent` is called on the event tap thread.
/// `remapTable` is protected by `lock` (inherited from EventTapBase).
/// Published properties are only mutated on @MainActor.
@MainActor
final class KeyRemapManager: EventTapBase, ObservableObject {
    static let shared = KeyRemapManager()

    @Published var mappings: [KeyMapping] = []
    @Published var isActive = false

    /// Fast lookup table for the event tap callback (lock-protected).
    nonisolated(unsafe) private var remapTable: [UInt16: UInt16] = [:]

    private override init() {
        super.init()
        loadMappings()
        if mappings.isEmpty {
            mappings = [
                KeyMapping(from: 57, fromLabel: "Caps Lock", to: 53, toLabel: "⎋", enabled: false),
            ]
            saveMappings()
        }
        rebuildRemapTable()
    }

    // MARK: - Start / Stop

    func start() {
        guard !isActive else { return }
        rebuildRemapTable()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        if startTap(eventsOfInterest: mask) {
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
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        lock.lock()
        let mapped = remapTable[keyCode]
        lock.unlock()

        if let newCode = mapped {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(newCode))
        }

        return event
    }

    // MARK: - Mapping Management

    func addMapping(_ mapping: KeyMapping) {
        mappings.append(mapping)
        rebuildRemapTable()
        saveMappings()
    }

    func removeMapping(_ mapping: KeyMapping) {
        mappings.removeAll { $0.id == mapping.id }
        rebuildRemapTable()
        saveMappings()
    }

    func toggleMapping(_ mapping: KeyMapping) {
        guard let idx = mappings.firstIndex(where: { $0.id == mapping.id }) else { return }
        mappings[idx].enabled.toggle()
        rebuildRemapTable()
        saveMappings()
    }

    /// Rebuild the lock-protected lookup table used by the event tap callback.
    private func rebuildRemapTable() {
        lock.lock()
        remapTable = [:]
        for m in mappings where m.enabled {
            remapTable[m.fromKeyCode] = m.toKeyCode
        }
        lock.unlock()
    }

    // MARK: - Presets

    static let presets: [(name: String, from: UInt16, fromLabel: String, to: UInt16, toLabel: String)] = [
        ("Caps Lock → Escape", 57, "Caps Lock", 53, "⎋"),
        ("Caps Lock → Control", 57, "Caps Lock", 59, "⌃"),
        ("Right ⌘ → Right ⌥", 54, "Right ⌘", 61, "Right ⌥"),
        ("§ → `", 10, "§", 50, "`"),
    ]

    // MARK: - Persistence

    private var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacQoL", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("key_remap_mappings.json")
    }

    private func saveMappings() {
        do {
            let data = try JSONEncoder().encode(mappings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.error("Failed to save key remap mappings", error)
        }
    }

    private func loadMappings() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            mappings = try JSONDecoder().decode([KeyMapping].self, from: data)
        } catch {
            Log.error("Failed to load key remap mappings", error)
        }
    }
}
