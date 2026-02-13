import Foundation
import SwiftUI

enum Feature: String, CaseIterable, Identifiable {
    case hub = "Hub"
    case clipboard = "Clipboard"
    case recording = "Recording"
    case focus = "Focus"
    case todo = "Todo"
    case mindmap = "Mindmap"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hub: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .recording: return "record.circle"
        case .focus: return "moon.fill"
        case .todo: return "checklist"
        case .mindmap: return "point.3.connected.trianglepath.dotted"
        case .settings: return "gear"
        }
    }
}

@Observable
final class AppState {
    static let shared = AppState()

    var activeFeature: Feature = .hub
    var isHubWindowVisible = false

    private init() {}
}
