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

        // Content view with hover overlay buttons
        let contentView = PiPContentView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        contentView.onClose = { [weak self] in
            Task { @MainActor in await self?.stopPiP() }
        }
        contentView.onReturnToSource = { [weak self] in
            Task { @MainActor in self?.focusSourceWindow() }
        }

        panel.contentView = contentView
        self.displayLayer = contentView.renderLayer
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

    private func focusSourceWindow() {
        guard let window = selectedWindow,
              let bundleID = window.owningApplication?.bundleIdentifier else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
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

// MARK: - PiP Content View (hover overlay with close + return buttons)

private class PiPContentView: NSView {
    let renderLayer = CALayer()
    var onClose: (() -> Void)?
    var onReturnToSource: (() -> Void)?

    private let overlayView = NSView()
    private let closeButton = PiPOverlayButton(symbolName: "xmark", toolTip: "Close PiP")
    private let returnButton = PiPOverlayButton(symbolName: "arrow.uturn.backward", toolTip: "Return to source app")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        // Video render layer
        renderLayer.contentsGravity = .resizeAspect
        renderLayer.frame = bounds
        renderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(renderLayer)

        // Overlay container (hidden by default)
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = nil
        overlayView.alphaValue = 0
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.topAnchor.constraint(equalTo: topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Buttons
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(closeButton)

        returnButton.target = self
        returnButton.action = #selector(returnClicked)
        returnButton.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(returnButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            returnButton.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 8),
            returnButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            returnButton.widthAnchor.constraint(equalToConstant: 28),
            returnButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Tracking area for hover
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func returnClicked() {
        onReturnToSource?()
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            overlayView.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            overlayView.animator().alphaValue = 0
        }
    }
}

// MARK: - PiP Overlay Button

private class PiPOverlayButton: NSButton {
    init(symbolName: String, toolTip: String) {
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        self.toolTip = toolTip
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(config)
        contentTintColor = .white
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
    }
}

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
