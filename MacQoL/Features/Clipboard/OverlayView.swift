import SwiftUI

struct OverlayView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    var selectedIndex: Int
    let onClose: () -> Void
    let onSelect: (ClipboardItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)

            if clipboardManager.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clipboard")
                        .font(.system(size: 24))
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    Text("Nothing copied yet")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(clipboardManager.items.enumerated()), id: \.element.id) { index, item in
                                ClipboardItemRow(
                                    item: item,
                                    index: index,
                                    isSelected: index == selectedIndex,
                                    onSelect: {
                                        onSelect(item)
                                    },
                                    onDelete: {
                                        clipboardManager.deleteItem(item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        if !clipboardManager.items.isEmpty && newValue < clipboardManager.items.count {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(clipboardManager.items[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
                    .frame(width: 14)
            }

            if item.type == .image, let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .cornerRadius(4)
                    .clipped()

                VStack(alignment: .leading, spacing: 1) {
                    Text("Image")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    if let size = image.size as CGSize? {
                        Text("\(Int(size.width))\u{00D7}\(Int(size.height))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text(item.preview)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .foregroundColor(.primary)
                    .truncationMode(.tail)
            }

            Spacer()

            if isHovering {
                Text(relativeTime(from: item.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovering ? Color.primary.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
