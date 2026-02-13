import SwiftUI

struct MindmapNodeView: View {
    @Bindable var node: MindmapNode
    let isSelected: Bool
    let onSelect: () -> Void
    let onDrag: (CGSize) -> Void

    @State private var isEditing = false

    var body: some View {
        VStack(spacing: 4) {
            if isEditing {
                TextField("Node", text: $node.text, onCommit: {
                    isEditing = false
                })
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .frame(minWidth: 80)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            } else {
                Text(node.text)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: node.colorHex).opacity(0.2))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color(hex: node.colorHex), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            isEditing = true
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    onDrag(value.translation)
                }
        )
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 74, 144, 217)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
