# MacQoL

An all-in-one macOS productivity app that combines clipboard history, screen recording, focus mode, todos, and mindmaps into a single native Swift/SwiftUI application.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

### Clipboard History
- Monitors clipboard for text and images
- Overlay popup at cursor position (Cmd+Option+V)
- Arrow keys to navigate, Enter to paste, 1-9 for quick paste
- Stores up to 100 items

### Screen Recording
- Continuous ring buffer recording (30s to 10min)
- Save the last N seconds on demand — never miss a moment
- Hardware-accelerated H.264/HEVC encoding via VideoToolbox
- Display or window capture via ScreenCaptureKit
- Optional system audio and microphone capture

### Focus Mode
- Countdown timer with configurable duration
- Block distracting apps (terminates them on launch)
- Block websites via /etc/hosts modification
- Auto-unblock when session ends

### Todo List
- Create todos with priority, category, due date, and reminders
- macOS notifications for reminders via UNUserNotificationCenter
- Filter by status (all/active/done) and priority
- Persisted with SwiftData

### Mindmap
- Infinite canvas with pan and zoom
- Create, connect, and drag nodes
- Bezier curve connections
- Double-click to edit node text
- Persisted with SwiftData

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (for clipboard paste simulation)
- Screen recording permission (for screen capture)
- Microphone permission (optional, for audio recording)

## Build

```bash
# Clone
git clone https://github.com/wong-max-max/macqol.git
cd macqol

# Build and create .app bundle
./build.sh

# Run
open MacQoL.app

# Install to Applications
cp -R MacQoL.app /Applications/
```

Or run directly in debug mode:
```bash
swift run
```

## Global Hotkeys

| Shortcut | Action |
|----------|--------|
| Cmd+Option+V | Open clipboard overlay |
| Cmd+Shift+S | Save recording clip |
| Cmd+Shift+R | Toggle recording |
| Cmd+Shift+F | Toggle focus mode |

All hotkeys are configurable in Settings.

## Architecture

- **Swift Package Manager** project, no Xcode project file needed
- **SwiftUI** for all views with **AppKit** integration for menu bar and overlay windows
- **SwiftData** for persistent storage (todos, mindmaps)
- **Carbon API** for global hotkey registration
- **ScreenCaptureKit + VideoToolbox** for hardware-accelerated screen recording
- Menu bar icon with hub dashboard window
