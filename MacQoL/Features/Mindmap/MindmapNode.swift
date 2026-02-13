import Foundation
import SwiftData

@Model
final class MindmapNode {
    var text: String
    var positionX: Double
    var positionY: Double
    var colorHex: String

    @Relationship(inverse: \MindmapNode.children)
    var parent: MindmapNode?

    @Relationship
    var children: [MindmapNode]

    var document: MindmapDocument?

    init(
        text: String = "New Node",
        positionX: Double = 0,
        positionY: Double = 0,
        colorHex: String = "#4A90D9"
    ) {
        self.text = text
        self.positionX = positionX
        self.positionY = positionY
        self.colorHex = colorHex
        self.children = []
    }
}
