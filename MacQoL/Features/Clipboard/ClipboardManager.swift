import AppKit
import Combine

/// Monitors NSPasteboard for changes and maintains a searchable clipboard history.
///
/// Polls the system pasteboard every 0.5s. Supports text and image items.
/// History is persisted to UserDefaults as JSON (max 100 items, FIFO eviction).
class ClipboardManager: ObservableObject {
    @Published var items: [ClipboardItem] = []
    @Published var hasBackup: Bool = false

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private let pasteboard = NSPasteboard.general
    private let maxItems = 100
    private let userDefaultsKey = "clipboardHistory"
    private let backupKey = "clipboardHistoryBackup"

    init() {
        loadHistory()
        checkForBackup()
    }

    func startMonitoring() {
        lastChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }

        lastChangeCount = pasteboard.changeCount

        var newItem: ClipboardItem?

        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) {
            if let lastItem = items.first,
               lastItem.type == .image,
               lastItem.imageData == imageData {
                return
            }
            newItem = ClipboardItem(imageData: imageData)
        } else if let content = pasteboard.string(forType: .string), !content.isEmpty {
            if let lastItem = items.first,
               lastItem.type == .text,
               lastItem.content == content {
                return
            }
            newItem = ClipboardItem(content: content)
        }

        if let newItem = newItem {
            items.insert(newItem, at: 0)

            if items.count > maxItems {
                items = Array(items.prefix(maxItems))
            }

            saveHistory()
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        saveHistory()
    }

    func clearHistory() {
        if !items.isEmpty {
            do {
                let encoded = try JSONEncoder().encode(items)
                UserDefaults.standard.set(encoded, forKey: backupKey)
                hasBackup = true
            } catch {
                Log.error("Failed to encode clipboard backup", error)
            }
        }
        items.removeAll()
        saveHistory()
    }

    func restoreHistory() {
        if let data = UserDefaults.standard.data(forKey: backupKey),
           let decoded = try? JSONDecoder().decode([ClipboardItem].self, from: data) {
            items = decoded
            saveHistory()
            UserDefaults.standard.removeObject(forKey: backupKey)
            hasBackup = false
        }
    }

    private func checkForBackup() {
        hasBackup = UserDefaults.standard.data(forKey: backupKey) != nil
    }

    private func saveHistory() {
        do {
            let encoded = try JSONEncoder().encode(items)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            Log.error("Failed to save clipboard history", error)
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else { return }
        do {
            items = try JSONDecoder().decode([ClipboardItem].self, from: data)
        } catch {
            Log.error("Failed to load clipboard history", error)
        }
    }

    deinit {
        stopMonitoring()
    }
}
