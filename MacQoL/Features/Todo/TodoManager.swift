import Foundation
import SwiftData

@MainActor
final class TodoManager: ObservableObject {
    static let shared = TodoManager()

    private init() {
        NotificationManager.shared.requestAuthorization()
    }

    func addTodo(_ item: TodoItem, context: ModelContext) {
        context.insert(item)
        try? context.save()
        scheduleReminder(for: item)
    }

    func toggleDone(_ item: TodoItem) {
        item.isDone.toggle()
        if item.isDone {
            cancelReminder(for: item)
        } else {
            scheduleReminder(for: item)
        }
    }

    func delete(_ item: TodoItem, context: ModelContext) {
        cancelReminder(for: item)
        context.delete(item)
    }

    func updateReminder(for item: TodoItem) {
        cancelReminder(for: item)
        scheduleReminder(for: item)
    }

    private func scheduleReminder(for item: TodoItem) {
        guard let reminderDate = item.reminderDate, !item.isDone else { return }
        guard reminderDate > Date() else { return }

        NotificationManager.shared.scheduleNotification(
            identifier: item.persistentModelID.hashValue.description,
            title: "Todo Reminder",
            body: item.title,
            at: reminderDate
        )
    }

    private func cancelReminder(for item: TodoItem) {
        NotificationManager.shared.cancelNotification(
            identifier: item.persistentModelID.hashValue.description
        )
    }
}
