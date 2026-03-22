import AppKit
import ScreenCaptureKit
import CoreMedia

/// Captures a window via ScreenCaptureKit and renders it in a borderless floating panel.
///
/// Inherits NSObject for SCStreamDelegate and NSWindowDelegate conformance.
/// Frames arrive on `captureQueue`, get converted to CGImage, and are displayed
/// on main thread via a CALayer. Runs at 60fps with aspect-ratio-locked resizing.
@MainActor
final class PiPManager: NSObject, ObservableObject {
    static let shared = PiPManager()

    @Published var isActive = false
    @Published var availableWindows: [SCWindow] = []
    @Published var selectedWindow: SCWindow?
    @Published var error: String?

    private var stream: SCStream?
    private var streamOutput: PiPStreamOutput?
    private var pipWindow: NSPanel?
    private var displayLayer: CALayer?
    private let captureQueue = DispatchQueue(label: "com.macqol.pip.capture", qos: .userInteractive)

    private override init() {
        super.init()
    }

    private static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
    ]

    func refreshWindows() async {
        do {
            // onScreenWindowsOnly: false to pick up fullscreen apps on other Spaces
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            let ownBundleID = Bundle.main.bundleIdentifier
            availableWindows = content.windows.filter { window in
                let bundleID = window.owningApplication?.bundleIdentifier ?? ""
                guard bundleID != ownBundleID,
                      !Self.excludedBundleIDs.contains(bundleID) else { return false }
                // Include if: has a title, OR is reasonably sized (catches Java/game windows with empty titles)
                let hasTitle = window.title != nil && !window.title!.isEmpty
                let isLargeEnough = window.frame.width >= 200 && window.frame.height >= 200
                return hasTitle || isLargeEnough
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startPiP(window: SCWindow) async {
        guard !isActive else { return }

        selectedWindow = window
        error = nil

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()

            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 8
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.capturesAudio = false

            // Scale down to reasonable size
            let aspectRatio = filter.contentRect.width / filter.contentRect.height
            let height = min(Int(filter.contentRect.height), 720)
            config.height = height
            config.width = Int(Double(height) * aspectRatio)

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            let output = PiPStreamOutput { [weak self] sampleBuffer in
                self?.handleFrame(sampleBuffer)
            }
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)

            self.stream = stream
            self.streamOutput = output

            showPiPWindow(
                title: window.title ?? "PiP",
                aspectRatio: aspectRatio,
                captureWidth: config.width,
                captureHeight: config.height
            )

            try await stream.startCapture()
            isActive = true
        } catch {
            self.error = error.localizedDescription
            closePiPWindow()
        }
    }

    func stopPiP() async {
        guard isActive else { return }

        if let stream {
            do {
                try await stream.stopCapture()
            } catch {
                print("PiP stop error: \(error)")
            }
        }

        stream = nil
        streamOutput = nil
        isActive = false
        selectedWindow = nil
        closePiPWindow()
    }

    // MARK: - PiP Window

    private func showPiPWindow(title: String, aspectRatio: CGFloat, captureWidth: Int, captureHeight: Int) {
        let windowHeight: CGFloat = 300
        let windowWidth = windowHeight * aspectRatio

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.contentAspectRatio = NSSize(width: aspectRatio, height: 1.0)
        panel.minSize = NSSize(width: 200 * aspectRatio, height: 200)
        panel.delegate = self

        // Content view with a layer for rendering frames
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor
        contentView.layer?.cornerRadius = 8
        contentView.layer?.masksToBounds = true

        let renderLayer = CALayer()
        renderLayer.contentsGravity = .resizeAspect
        renderLayer.frame = contentView.bounds
        renderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer?.addSublayer(renderLayer)

        panel.contentView = contentView
        self.displayLayer = renderLayer
        self.pipWindow = panel

        // Position in bottom-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - windowWidth - 20
            let y = screenFrame.minY + 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
    }

    private func closePiPWindow() {
        pipWindow?.close()
        pipWindow = nil
        displayLayer = nil
    }

    // MARK: - Frame Handling

    private nonisolated func handleFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.displayLayer?.contents = cgImage
        }
    }
}

// MARK: - SCStreamDelegate

extension PiPManager: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.error = error.localizedDescription
            self?.isActive = false
            self?.closePiPWindow()
        }
    }
}

// MARK: - NSWindowDelegate

extension PiPManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSPanel === pipWindow else { return }
        Task { @MainActor in
            await stopPiP()
        }
    }
}

// MARK: - Stream Output

private class PiPStreamOutput: NSObject, SCStreamOutput {
    let onFrame: (CMSampleBuffer) -> Void

    init(onFrame: @escaping (CMSampleBuffer) -> Void) {
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid, type == .screen else { return }
        onFrame(sampleBuffer)
    }
}
