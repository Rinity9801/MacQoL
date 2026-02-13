import Foundation
import AppKit

enum ClipboardItemType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let type: ClipboardItemType
    let content: String
    let imageData: Data?
    let timestamp: Date
    let preview: String

    init(content: String) {
        self.id = UUID()
        self.type = .text
        self.content = content
        self.imageData = nil
        self.timestamp = Date()
        self.preview = String(content.prefix(100))
    }

    init(imageData: Data) {
        self.id = UUID()
        self.type = .image
        self.content = ""
        self.imageData = imageData
        self.timestamp = Date()
        self.preview = "Image"
    }

    init(id: UUID, type: ClipboardItemType, content: String, imageData: Data?, timestamp: Date, preview: String) {
        self.id = id
        self.type = type
        self.content = content
        self.imageData = imageData
        self.timestamp = timestamp
        self.preview = preview
    }

    var image: NSImage? {
        guard let imageData = imageData else { return nil }
        return NSImage(data: imageData)
    }
}
