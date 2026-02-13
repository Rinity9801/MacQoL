import SwiftUI
import SwiftData

struct MindmapCanvasView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MindmapDocument.modifiedAt, order: .reverse) private var documents: [MindmapDocument]

    @State private var selectedDocument: MindmapDocument?
    @State private var selectedNode: MindmapNode?
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var dragStartPositions: [String: CGPoint] = [:]
    @State private var showingNewDocSheet = false
    @State private var newDocTitle = ""

    var body: some View {
        HSplitView {
            // Document list
            documentList
                .frame(minWidth: 180, maxWidth: 220)

            // Canvas
            if let doc = selectedDocument {
                canvasView(for: doc)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select or create a mindmap")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Document List

    private var documentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mindmaps")
                    .font(.headline)
                Spacer()
                Button(action: { showingNewDocSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding(12)

            Divider()

            List(documents, selection: Binding(
                get: { selectedDocument },
                set: { selectedDocument = $0 }
            )) { doc in
                VStack(alignment: .leading) {
                    Text(doc.title)
                        .font(.body)
                    Text("\(doc.nodes.count) nodes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(doc)
                .contextMenu {
                    Button("Delete", role: .destructive) {
                        if selectedDocument === doc {
                            selectedDocument = nil
                        }
                        modelContext.delete(doc)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewDocSheet) {
            VStack(spacing: 16) {
                Text("New Mindmap")
                    .font(.headline)
                TextField("Title", text: $newDocTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingNewDocSheet = false
                        newDocTitle = ""
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create") {
                        let doc = MindmapDocument(title: newDocTitle.isEmpty ? "Untitled" : newDocTitle)
                        // Add a root node
                        let root = MindmapNode(text: doc.title, positionX: 400, positionY: 300)
                        root.document = doc
                        doc.nodes.append(root)
                        modelContext.insert(doc)
                        selectedDocument = doc
                        showingNewDocSheet = false
                        newDocTitle = ""
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    // MARK: - Canvas

    private func canvasView(for doc: MindmapDocument) -> some View {
        ZStack {
            // Background
            Color(nsColor: .controlBackgroundColor)

            // Canvas content with pan + zoom
            ZStack {
                // Connection lines
                Canvas { context, size in
                    for node in doc.nodes {
                        for child in node.children {
                            let from = CGPoint(x: node.positionX, y: node.positionY)
                            let to = CGPoint(x: child.positionX, y: child.positionY)

                            var path = Path()
                            path.move(to: from)

                            // Bezier curve
                            let midX = (from.x + to.x) / 2
                            path.addCurve(
                                to: to,
                                control1: CGPoint(x: midX, y: from.y),
                                control2: CGPoint(x: midX, y: to.y)
                            )

                            context.stroke(path, with: .color(.secondary.opacity(0.5)), lineWidth: 1.5)
                        }
                    }
                }

                // Nodes
                ForEach(doc.nodes) { node in
                    MindmapNodeView(
                        node: node,
                        isSelected: selectedNode === node,
                        onSelect: { selectedNode = node },
                        onDrag: { translation in
                            let key = node.persistentModelID.hashValue.description
                            if dragStartPositions[key] == nil {
                                dragStartPositions[key] = CGPoint(x: node.positionX, y: node.positionY)
                            }
                            if let start = dragStartPositions[key] {
                                node.positionX = start.x + translation.width / canvasScale
                                node.positionY = start.y + translation.height / canvasScale
                            }
                        }
                    )
                    .position(x: node.positionX, y: node.positionY)
                }
            }
            .scaleEffect(canvasScale)
            .offset(canvasOffset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        canvasScale = max(0.3, min(3.0, value))
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if selectedNode == nil {
                            canvasOffset = value.translation
                        }
                    }
                    .onEnded { _ in
                        dragStartPositions.removeAll()
                    }
            )
            .onTapGesture {
                selectedNode = nil
            }

            // Toolbar overlay
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    toolbarButtons(for: doc)
                }
            }
            .padding(16)
        }
    }

    private func toolbarButtons(for doc: MindmapDocument) -> some View {
        HStack(spacing: 8) {
            // Add child node
            Button(action: {
                addNode(to: doc)
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .help("Add node")

            // Connect nodes
            if selectedNode != nil {
                Button(action: {
                    addChildToSelected(in: doc)
                }) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("Add child to selected")
            }

            // Delete selected
            if let selected = selectedNode {
                Button(action: {
                    deleteNode(selected, from: doc)
                }) {
                    Image(systemName: "trash.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete selected node")
            }

            // Zoom controls
            Button(action: { canvasScale = min(3.0, canvasScale + 0.2) }) {
                Image(systemName: "plus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button(action: { canvasScale = max(0.3, canvasScale - 0.2) }) {
                Image(systemName: "minus.magnifyingglass")
            }
            .buttonStyle(.plain)

            Button(action: {
                canvasScale = 1.0
                canvasOffset = .zero
            }) {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.plain)
            .help("Reset zoom")
        }
        .padding(8)
        .background(.regularMaterial)
        .cornerRadius(8)
    }

    // MARK: - Actions

    private func addNode(to doc: MindmapDocument) {
        let colors = ["#4A90D9", "#50C878", "#FF6B6B", "#FFB347", "#DDA0DD", "#87CEEB"]
        let node = MindmapNode(
            text: "New Node",
            positionX: Double.random(in: 200...600),
            positionY: Double.random(in: 200...500),
            colorHex: colors.randomElement() ?? "#4A90D9"
        )
        node.document = doc
        doc.nodes.append(node)
        doc.modifiedAt = Date()
        selectedNode = node
    }

    private func addChildToSelected(in doc: MindmapDocument) {
        guard let parent = selectedNode else { return }
        let colors = ["#4A90D9", "#50C878", "#FF6B6B", "#FFB347", "#DDA0DD", "#87CEEB"]
        let child = MindmapNode(
            text: "Child",
            positionX: parent.positionX + Double.random(in: 80...150),
            positionY: parent.positionY + Double.random(in: -80...80),
            colorHex: colors.randomElement() ?? "#50C878"
        )
        child.document = doc
        child.parent = parent
        parent.children.append(child)
        doc.nodes.append(child)
        doc.modifiedAt = Date()
        selectedNode = child
    }

    private func deleteNode(_ node: MindmapNode, from doc: MindmapDocument) {
        // Remove from parent's children
        if let parent = node.parent {
            parent.children.removeAll { $0 === node }
        }
        // Reparent children to deleted node's parent
        for child in node.children {
            child.parent = node.parent
        }
        doc.nodes.removeAll { $0 === node }
        doc.modifiedAt = Date()
        modelContext.delete(node)
        selectedNode = nil
    }
}
