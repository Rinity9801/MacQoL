import SwiftUI
import AVFoundation
import AVKit

// MARK: - AVPlayerView wrapper (avoids _AVKit_SwiftUI metadata crash in SPM builds)

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

struct VideoEditorView: View {
    @ObservedObject private var manager = VideoEditorManager.shared
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var timeObserver: Any?
    @State private var timelineZoom: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            if manager.clips.isEmpty {
                emptyState
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        videoPreview
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        transportControls
                            .padding(12)
                    }
                    .frame(minWidth: 400)

                    VStack(spacing: 0) {
                        clipList
                        if manager.selectedClip != nil {
                            Divider()
                            trimControls
                        }
                    }
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                }

                Divider()
                timelineZoomBar
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                timeline
                    .frame(height: 80)
                Divider()
                toolbar
                    .padding(8)
            }
        }
        .overlay(alignment: .top) {
            exportOverlay
        }
        .focusable()
        .onKeyPress(.space) { togglePlayPause(); return .handled }
        .onKeyPress(.leftArrow) { nudgePlayhead(-1.0 / 30.0); return .handled }
        .onKeyPress(.rightArrow) { nudgePlayhead(1.0 / 30.0); return .handled }
        .onKeyPress(",") { nudgePlayhead(-1.0); return .handled }
        .onKeyPress(".") { nudgePlayhead(1.0); return .handled }
        .onKeyPress("j") { nudgePlayhead(-5.0); return .handled }
        .onKeyPress("l") { nudgePlayhead(5.0); return .handled }
        .onKeyPress("s") { manager.splitSelectedClip(); return .handled }
        .onKeyPress("i") { manager.importVideos(); return .handled }
        .onKeyPress(.delete) { manager.removeSelectedClip(); return .handled }
        .onKeyPress(.deleteForward) { manager.removeSelectedClip(); return .handled }
        .onKeyPress("[") { selectPreviousClip(); return .handled }
        .onKeyPress("]") { selectNextClip(); return .handled }
        .onKeyPress(.home) { jumpToStart(); return .handled }
        .onKeyPress(.end) { jumpToEnd(); return .handled }
        .onKeyPress("=") { timelineZoom = Swift.min(timelineZoom + 1, 20); return .handled }
        .onKeyPress("-") { timelineZoom = Swift.max(timelineZoom - 1, 1); return .handled }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Video Editor")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Import videos to start editing")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Import Videos") {
                    manager.importVideos()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if !manager.projects.isEmpty {
                Divider()
                    .frame(width: 300)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Projects")
                        .font(.headline)

                    ForEach(manager.projects.prefix(5)) { project in
                        projectRow(project)
                    }
                }
                .frame(width: 300)
            }

            keybindHints
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectRow(_ project: VideoProject) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)
                HStack(spacing: 8) {
                    Text("\(project.clips.count) clip\(project.clips.count == 1 ? "" : "s")")
                    Text(project.modifiedAt, style: .relative)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                manager.loadProject(project)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(action: { manager.deleteProject(project) }) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var keybindHints: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Keyboard Shortcuts")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
            Group {
                Text("Space  Play/Pause")
                Text("← →    Scrub frame  |  , .  Scrub 1s")
                Text("J / L  Seek -5s / +5s")
                Text("S      Split at playhead")
                Text("[ / ]  Previous / Next clip")
                Text("⌫      Delete clip")
                Text("+ / -  Zoom timeline")
                Text("I      Import")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Video Preview

    private var videoPreview: some View {
        Group {
            if let player = player {
                PlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            } else {
                Rectangle()
                    .fill(.black)
                    .overlay {
                        Text("Select a clip to preview")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(8)
            }
        }
        .onAppear { loadPreview() }
        .onChange(of: manager.selectedClipID) { _, _ in
            loadPreview()
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 16) {
            Button(action: { nudgePlayhead(-5.0) }) {
                Image(systemName: "gobackward.5")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Button(action: togglePlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Button(action: { nudgePlayhead(5.0) }) {
                Image(systemName: "goforward.5")
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(formatTimePrecise(manager.playheadPosition))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)

            Text("/ \(formatTime(manager.totalDuration))")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Clip List

    private var clipList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Clips")
                    .font(.headline)
                Spacer()
                Text("\(manager.clips.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            List(selection: $manager.selectedClipID) {
                ForEach(manager.clips) { clip in
                    clipRow(clip)
                        .tag(clip.id)
                }
                .onMove { source, destination in
                    manager.moveClip(from: source, to: destination)
                }
            }
            .listStyle(.inset)
        }
    }

    private func clipRow(_ clip: VideoClip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(clip.sourceURL.lastPathComponent)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Text(formatTime(clip.startSeconds))
                Image(systemName: "arrow.right")
                    .font(.caption2)
                Text(formatTime(clip.endSeconds))
                Spacer()
                Text(formatTime(clip.durationSeconds))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Trim Controls

    private var trimControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trim")
                .font(.headline)

            if let clip = manager.selectedClip, manager.selectedClipIndex != nil {
                VStack(spacing: 8) {
                    trimSliderRow(
                        label: "Start",
                        value: clip.startSeconds,
                        range: 0...Swift.max(clip.endSeconds - 0.1, 0.1),
                        onChanged: { manager.trimSelectedClip(newStart: $0, newEnd: clip.endSeconds) }
                    )
                    trimSliderRow(
                        label: "End",
                        value: clip.endSeconds,
                        range: Swift.max(clip.startSeconds + 0.1, 0.1)...clip.originalDurationSeconds,
                        onChanged: { manager.trimSelectedClip(newStart: clip.startSeconds, newEnd: $0) }
                    )
                }

                HStack {
                    Text("Duration: \(formatTime(clip.durationSeconds))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") {
                        manager.trimSelectedClip(newStart: 0, newEnd: clip.originalDurationSeconds)
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            }
        }
        .padding(12)
    }

    private func trimSliderRow(label: String, value: Double, range: ClosedRange<Double>, onChanged: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
            Slider(
                value: Binding(get: { value }, set: onChanged),
                in: range
            )
            Text(formatTime(value))
                .font(.system(.caption, design: .monospaced))
                .frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: - Timeline Zoom

    private var timelineZoomBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $timelineZoom, in: 1...20)
                .frame(width: 120)
            Image(systemName: "plus.magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(timelineZoom))x")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .leading)
            Spacer()
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        GeometryReader { geo in
            let totalDur = Swift.max(manager.totalDuration, 0.001)
            let zoomedWidth = geo.size.width * timelineZoom

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .leading) {
                        Color(nsColor: .controlBackgroundColor)
                            .frame(width: zoomedWidth)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        scrubTimeline(at: value.location.x, width: zoomedWidth, totalDuration: totalDur)
                                    }
                            )

                        timelineClipBlocks(width: zoomedWidth, totalDuration: totalDur)
                            .allowsHitTesting(false)

                        timelinePlayhead(width: zoomedWidth, totalDuration: totalDur)
                            .allowsHitTesting(false)
                    }
                    .frame(width: zoomedWidth, height: 80)
                }
            }
        }
    }

    private func scrubTimeline(at x: CGFloat, width: CGFloat, totalDuration: Double) {
        let frac = Swift.max(0, Swift.min(Double(x) / Double(width), 1.0))
        let newPosition = frac * totalDuration
        manager.playheadPosition = newPosition

        // Auto-select the clip under the playhead
        let clipAtPlayhead = clipAt(position: newPosition)
        if let clip = clipAtPlayhead, clip.id != manager.selectedClipID {
            manager.selectedClipID = clip.id
            loadPreview()
        } else if player == nil {
            loadPreview()
        }

        seekPlayerToPlayhead()
    }

    private func timelineClipBlocks(width: CGFloat, totalDuration: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(manager.clips) { clip in
                timelineClipBlock(clip: clip, width: width, totalDuration: totalDuration)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private func timelineClipBlock(clip: VideoClip, width: CGFloat, totalDuration: Double) -> some View {
        let fraction = clip.durationSeconds / totalDuration
        let gapSpace = CGFloat(Swift.max(manager.clips.count - 1, 0)) * 2
        let blockWidth = Swift.max(fraction * (width - gapSpace), 20)
        let isSelected = clip.id == manager.selectedClipID

        return RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.25))
            .frame(width: blockWidth)
            .overlay {
                Text(clip.sourceURL.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
    }

    private func timelinePlayhead(width: CGFloat, totalDuration: Double) -> some View {
        let playheadX = (manager.playheadPosition / totalDuration) * Double(width)
        return VStack(spacing: 0) {
            // Triangle handle
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.red)
                .offset(y: 2)
            // Vertical line
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
        }
        .offset(x: playheadX)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            // Project controls
            Menu {
                Button("New Project") { manager.newProject() }
                Divider()
                Button("Save") { manager.saveProject() }
                    .disabled(manager.clips.isEmpty)
                Button("Save As...") { manager.saveProjectAs() }
                    .disabled(manager.clips.isEmpty)
                if !manager.projects.isEmpty {
                    Divider()
                    ForEach(manager.projects.prefix(10)) { project in
                        Button(project.name) { manager.loadProject(project) }
                    }
                }
            } label: {
                Label(manager.currentProjectName ?? "Project", systemImage: "folder")
            }

            Divider().frame(height: 20)

            Button(action: { manager.importVideos() }) {
                Label("Import", systemImage: "plus.circle")
            }

            Divider().frame(height: 20)

            Button(action: { manager.splitSelectedClip() }) {
                Label("Split", systemImage: "scissors")
            }
            .disabled(manager.selectedClip == nil)

            Button(action: { manager.removeSelectedClip() }) {
                Label("Delete", systemImage: "trash")
            }
            .disabled(manager.selectedClip == nil)

            Spacer()

            keybindHintsCompact

            Spacer()

            Button(action: { manager.exportTimeline() }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.clips.isEmpty)
        }
    }

    private var keybindHintsCompact: some View {
        HStack(spacing: 12) {
            keybindPill("Space", "Play")
            keybindPill("← →", "Frame")
            keybindPill("S", "Split")
            keybindPill("⌫", "Delete")
            keybindPill("[ ]", "Prev/Next")
            keybindPill("+ −", "Zoom")
        }
    }

    private func keybindPill(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 3))
            Text(action)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Export Overlay

    @ViewBuilder
    private var exportOverlay: some View {
        switch manager.exportState {
        case .idle:
            EmptyView()
        case .exporting(let progress):
            exportBanner {
                ProgressView(value: progress)
                    .frame(width: 200)
                Text("\(Int(progress * 100))%")
                    .font(.system(.body, design: .monospaced))
            }
        case .done(let url):
            exportBanner {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Exported successfully")
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                    manager.exportState = .idle
                }
                .buttonStyle(.bordered)
                dismissButton
            }
        case .error(let msg):
            exportBanner {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(msg).lineLimit(2)
                dismissButton
            }
        }
    }

    private func exportBanner<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(16)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .padding(.top, 16)
    }

    private var dismissButton: some View {
        Button(action: { manager.exportState = .idle }) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback & Seeking

    private func loadPreview() {
        if let observer = timeObserver, let oldPlayer = player {
            oldPlayer.removeTimeObserver(observer)
            timeObserver = nil
        }

        guard let clip = manager.selectedClip else {
            player = nil
            isPlaying = false
            return
        }

        let p = AVPlayer(url: clip.sourceURL)
        p.seek(to: clip.startTime, toleranceBefore: .zero, toleranceAfter: .zero)

        let clipStartOffset = clipStartInTimeline(clip)
        let interval = CMTimeMakeWithSeconds(1.0 / 60.0, preferredTimescale: 600)
        let mgr = manager
        let observer = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [clip] time in
            let localSeconds = CMTimeGetSeconds(time) - CMTimeGetSeconds(clip.startTime)
            let clampedLocal = Swift.min(Swift.max(localSeconds, 0), clip.durationSeconds)
            Task { @MainActor in
                mgr.playheadPosition = clipStartOffset + clampedLocal
            }
        }
        timeObserver = observer
        player = p
        isPlaying = false
    }

    private func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func nudgePlayhead(_ delta: Double) {
        let totalDur = manager.totalDuration
        guard totalDur > 0 else { return }

        let newPos = Swift.max(0, Swift.min(manager.playheadPosition + delta, totalDur))
        manager.playheadPosition = newPos

        // Auto-select clip under new position
        if let clip = clipAt(position: newPos), clip.id != manager.selectedClipID {
            manager.selectedClipID = clip.id
            loadPreview()
        }

        seekPlayerToPlayhead()
    }

    private func selectPreviousClip() {
        guard let index = manager.selectedClipIndex, index > 0 else { return }
        let prev = manager.clips[index - 1]
        manager.selectedClipID = prev.id
        manager.playheadPosition = clipStartInTimeline(prev)
        loadPreview()
    }

    private func selectNextClip() {
        guard let index = manager.selectedClipIndex, index < manager.clips.count - 1 else { return }
        let next = manager.clips[index + 1]
        manager.selectedClipID = next.id
        manager.playheadPosition = clipStartInTimeline(next)
        loadPreview()
    }

    private func jumpToStart() {
        manager.playheadPosition = 0
        if let first = manager.clips.first, first.id != manager.selectedClipID {
            manager.selectedClipID = first.id
            loadPreview()
        }
        seekPlayerToPlayhead()
    }

    private func jumpToEnd() {
        manager.playheadPosition = manager.totalDuration
        if let last = manager.clips.last, last.id != manager.selectedClipID {
            manager.selectedClipID = last.id
            loadPreview()
        }
        seekPlayerToPlayhead()
    }

    private func seekPlayerToPlayhead() {
        guard let clip = manager.selectedClip, let player = player else { return }
        let accumulated = clipStartInTimeline(clip)
        let localOffset = manager.playheadPosition - accumulated
        if localOffset >= 0 && localOffset <= clip.durationSeconds {
            let seekTime = CMTimeAdd(clip.startTime, CMTimeMakeWithSeconds(localOffset, preferredTimescale: 600))
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    // MARK: - Helpers

    private func clipStartInTimeline(_ targetClip: VideoClip) -> Double {
        var pos: Double = 0
        for c in manager.clips {
            if c.id == targetClip.id { break }
            pos += c.durationSeconds
        }
        return pos
    }

    private func clipAt(position: Double) -> VideoClip? {
        var accumulated: Double = 0
        for clip in manager.clips {
            accumulated += clip.durationSeconds
            if position < accumulated {
                return clip
            }
        }
        return manager.clips.last
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatTimePrecise(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00.00" }
        let total = Int(seconds)
        let mins = total / 60
        let secs = total % 60
        let frac = Int((seconds - Double(total)) * 100)
        return String(format: "%d:%02d.%02d", mins, secs, frac)
    }

    private func cmMax(_ a: CMTime, _ b: CMTime) -> CMTime {
        CMTimeCompare(a, b) >= 0 ? a : b
    }
}
