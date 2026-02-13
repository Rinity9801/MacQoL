import Foundation
import SwiftData

enum TodoPriority: Int, Codable, CaseIterable, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var icon: String {
        switch self {
        case .low: return "arrow.down"
        case .medium: return "minus"
        case .high: return "arrow.up"
        }
    }

    static func < (lhs: TodoPriority, rhs: TodoPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

@Model
final class TodoItem {
    var title: String
    var notes: String
    var priority: TodoPriority
    var category: String
    var isDone: Bool
    var createdAt: Date
    var dueDate: Date?
    var reminderDate: Date?

    init(
        title: String,
        notes: String = "",
        priority: TodoPriority = .medium,
        category: String = "",
        isDone: Bool = false,
        dueDate: Date? = nil,
        reminderDate: Date? = nil
    ) {
        self.title = title
        self.notes = notes
        self.priority = priority
        self.category = category
        self.isDone = isDone
        self.createdAt = Date()
        self.dueDate = dueDate
        self.reminderDate = reminderDate
    }
}
