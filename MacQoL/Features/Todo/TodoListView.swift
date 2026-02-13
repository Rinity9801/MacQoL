import SwiftUI
import SwiftData

enum TodoFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case done = "Done"
}

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allItems: [TodoItem]

    @State private var filter: TodoFilter = .all
    @State private var showingAddSheet = false
    @State private var newTitle = ""
    @State private var newPriority: TodoPriority = .medium
    @State private var newCategory = ""
    @State private var newDueDate: Date?
    @State private var newReminderDate: Date?
    @State private var hasDueDate = false
    @State private var hasReminder = false

    private let todoManager = TodoManager.shared

    private var filteredItems: [TodoItem] {
        switch filter {
        case .all: return allItems
        case .active: return allItems.filter { !$0.isDone }
        case .done: return allItems.filter { $0.isDone }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .font(.title2)
                    .foregroundColor(.green)
                Text("Todo")
                    .font(.title2)
                Spacer()

                Picker("Filter", selection: $filter) {
                    ForEach(TodoFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(16)

            Divider()

            // Stats
            HStack(spacing: 16) {
                Text("\(allItems.filter { !$0.isDone }.count) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(allItems.filter { $0.isDone }.count) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // List
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(filter == .all ? "No todos yet" : "No \(filter.rawValue.lowercased()) todos")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        TodoRowView(item: item, onToggle: {
                            todoManager.toggleDone(item)
                        }, onDelete: {
                            todoManager.delete(item, context: modelContext)
                        })
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addTodoSheet
        }
    }

    private var addTodoSheet: some View {
        VStack(spacing: 16) {
            Text("New Todo")
                .font(.headline)

            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            Picker("Priority", selection: $newPriority) {
                ForEach(TodoPriority.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)

            TextField("Category (optional)", text: $newCategory)
                .textFieldStyle(.roundedBorder)

            Toggle("Due Date", isOn: $hasDueDate)
            if hasDueDate {
                DatePicker("Due", selection: Binding(
                    get: { newDueDate ?? Date() },
                    set: { newDueDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }

            Toggle("Reminder", isOn: $hasReminder)
            if hasReminder {
                DatePicker("Remind at", selection: Binding(
                    get: { newReminderDate ?? Date() },
                    set: { newReminderDate = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }

            HStack {
                Button("Cancel") {
                    showingAddSheet = false
                    resetForm()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let item = TodoItem(
                        title: newTitle,
                        priority: newPriority,
                        category: newCategory,
                        dueDate: hasDueDate ? (newDueDate ?? Date()) : nil,
                        reminderDate: hasReminder ? (newReminderDate ?? Date()) : nil
                    )
                    todoManager.addTodo(item, context: modelContext)
                    showingAddSheet = false
                    resetForm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func resetForm() {
        newTitle = ""
        newPriority = .medium
        newCategory = ""
        newDueDate = nil
        newReminderDate = nil
        hasDueDate = false
        hasReminder = false
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let onToggle: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isDone ? .green : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundColor(item.isDone ? .secondary : .primary)

                HStack(spacing: 8) {
                    Image(systemName: item.priority.icon)
                        .font(.caption2)
                        .foregroundColor(priorityColor(item.priority))

                    if !item.category.isEmpty {
                        Text(item.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let dueDate = item.dueDate {
                        Text(dueDate, style: .date)
                            .font(.caption)
                            .foregroundColor(dueDate < Date() && !item.isDone ? .red : .secondary)
                    }

                    if item.reminderDate != nil {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
}
