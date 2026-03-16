import SwiftUI
import SwiftData

struct TodoListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allItems: [TodoItem]

    @State private var selectedCategory: String?
    @State private var showingAddCategory = false
    @State private var newCategoryName = ""
    @State private var showingAddTask = false
    @State private var newTitle = ""
    @State private var newNotes = ""
    @State private var newPriority: TodoPriority = .medium
    @State private var newDueDate: Date?
    @State private var newReminderDate: Date?
    @State private var hasDueDate = false
    @State private var hasReminder = false
    @State private var selectedItem: TodoItem?
    @State private var renamingCategory: String?
    @State private var renameText = ""

    @AppStorage("todoCategories") private var categoriesData: Data = Data()

    private let todoManager = TodoManager.shared

    private var categories: [String] {
        (try? JSONDecoder().decode([String].self, from: categoriesData)) ?? []
    }

    private func saveCategories(_ cats: [String]) {
        categoriesData = (try? JSONEncoder().encode(cats)) ?? Data()
    }

    private var itemsForSelectedCategory: [TodoItem] {
        guard let cat = selectedCategory else { return [] }
        return allItems.filter { $0.category == cat }
    }

    private var activeCount: Int {
        itemsForSelectedCategory.filter { !$0.isDone }.count
    }

    private var doneCount: Int {
        itemsForSelectedCategory.filter { $0.isDone }.count
    }

    var body: some View {
        HSplitView {
            // Categories sidebar
            categoryList
                .frame(minWidth: 160, maxWidth: 220)

            // Tasks for selected category
            if let cat = selectedCategory {
                taskList(for: cat)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select or create a category")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Category List

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Categories")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddCategory = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(12)

            Divider()

            if categories.isEmpty {
                VStack(spacing: 8) {
                    Text("No categories yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(categories, id: \.self, selection: $selectedCategory) { cat in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                            .font(.caption)
                        Text(cat)
                        Spacer()
                        let count = allItems.filter { $0.category == cat && !$0.isDone }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    .tag(cat)
                    .contextMenu {
                        Button("Rename") {
                            renameText = cat
                            renamingCategory = cat
                        }
                        Button("Delete", role: .destructive) {
                            deleteCategory(cat)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            VStack(spacing: 16) {
                Text("New Category")
                    .font(.headline)
                TextField("Category name", text: $newCategoryName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingAddCategory = false
                        newCategoryName = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create") {
                        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty && !categories.contains(name) {
                            var cats = categories
                            cats.append(name)
                            saveCategories(cats)
                            selectedCategory = name
                        }
                        showingAddCategory = false
                        newCategoryName = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
        .sheet(item: $renamingCategory) { oldName in
            VStack(spacing: 16) {
                Text("Rename Category")
                    .font(.headline)
                TextField("Category name", text: $renameText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        renamingCategory = nil
                        renameText = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Rename") {
                        let newName = renameText.trimmingCharacters(in: .whitespaces)
                        if !newName.isEmpty {
                            renameCategory(oldName, to: newName)
                        }
                        renamingCategory = nil
                        renameText = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    // MARK: - Task List

    private func taskList(for category: String) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(category)
                    .font(.title2)
                Spacer()

                Text("\(activeCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(doneCount) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: { showingAddTask = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(16)

            Divider()

            if itemsForSelectedCategory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No tasks in this category")
                        .foregroundStyle(.secondary)
                    Button("Add Task") { showingAddTask = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(itemsForSelectedCategory) { item in
                        TodoRowView(item: item, onToggle: {
                            todoManager.toggleDone(item)
                        }, onDelete: {
                            todoManager.delete(item, context: modelContext)
                        })
                        .onTapGesture {
                            selectedItem = item
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddTask) {
            addTaskSheet(category: category)
        }
        .sheet(item: $selectedItem) { item in
            TodoDetailView(item: item)
        }
    }

    // MARK: - Add Task Sheet

    private func addTaskSheet(category: String) -> some View {
        VStack(spacing: 16) {
            Text("New Task")
                .font(.headline)

            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $newNotes)
                .font(.body)
                .frame(height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if newNotes.isEmpty {
                        Text("Description (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Picker("Priority", selection: $newPriority) {
                ForEach(TodoPriority.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)

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
                    showingAddTask = false
                    resetForm()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    let item = TodoItem(
                        title: newTitle,
                        notes: newNotes,
                        priority: newPriority,
                        category: category,
                        dueDate: hasDueDate ? (newDueDate ?? Date()) : nil,
                        reminderDate: hasReminder ? (newReminderDate ?? Date()) : nil
                    )
                    todoManager.addTodo(item, context: modelContext)
                    showingAddTask = false
                    resetForm()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - Actions

    private func deleteCategory(_ cat: String) {
        // Delete all tasks in this category
        let items = allItems.filter { $0.category == cat }
        for item in items {
            todoManager.delete(item, context: modelContext)
        }
        // Remove category
        var cats = categories
        cats.removeAll { $0 == cat }
        saveCategories(cats)
        if selectedCategory == cat {
            selectedCategory = nil
        }
    }

    private func renameCategory(_ oldName: String, to newName: String) {
        // Update all tasks
        let items = allItems.filter { $0.category == oldName }
        for item in items {
            item.category = newName
        }
        // Update category list
        var cats = categories
        if let idx = cats.firstIndex(of: oldName) {
            cats[idx] = newName
        }
        saveCategories(cats)
        if selectedCategory == oldName {
            selectedCategory = newName
        }
    }

    private func resetForm() {
        newTitle = ""
        newNotes = ""
        newPriority = .medium
        newDueDate = nil
        newReminderDate = nil
        hasDueDate = false
        hasReminder = false
    }
}

// MARK: - Make String work with sheet(item:)

extension String: @retroactive Identifiable {
    public var id: String { self }
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

                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Image(systemName: item.priority.icon)
                        .font(.caption2)
                        .foregroundColor(priorityColor(item.priority))

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

struct TodoDetailView: View {
    @Bindable var item: TodoItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Edit Task")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            TextField("Title", text: $item.title)
                .textFieldStyle(.roundedBorder)
                .font(.title3)

            Text("Description")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $item.notes)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if item.notes.isEmpty {
                        Text("Add a description...")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }

            Picker("Priority", selection: $item.priority) {
                ForEach(TodoPriority.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(20)
        .frame(width: 450)
        .frame(minHeight: 300)
    }
}
