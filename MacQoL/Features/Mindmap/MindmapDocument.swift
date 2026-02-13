import Foundation
import SwiftData

@Model
final class MindmapDocument {
    var title: String
    var createdAt: Date
    var modifiedAt: Date

    @Relationship(deleteRule: .cascade)
    var nodes: [MindmapNode]

    init(title: String = "Untitled Mindmap") {
        self.title = title
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.nodes = []
    }
}
