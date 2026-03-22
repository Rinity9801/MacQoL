import Foundation
import AVFoundation
import AppKit

enum ExportState: Equatable {
    case idle
    case exporting(progress: Double)
    case done(URL)
    case error(String)
}

/// Simple clip-based video editor using AVFoundation.
///
/// Workflow: import videos → split/trim clips → reorder → export.
/// Export composes all clips into a single MP4 via AVMutableComposition + AVAssetExportSession.
/// Projects (clip lists with source URLs and time ranges) are saved as JSON files.
@MainActor
final class VideoEditorManager: ObservableObject {
    static let shared = VideoEditorManager()

    @Published var clips: [VideoClip] = []
    @Published var selectedClipID: UUID?
    @Published var exportState: ExportState = .idle
    @Published var playheadPosition: Double = 0
    @Published var projects: [VideoProject] = []
    @Published var currentProjectID: UUID?

    private var exportSession: AVAssetExportSession?

    var selectedClip: VideoClip? {
        guard let id = selectedClipID else { return nil }
        return clips.first { $0.id == id }
    }

    var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return clips.firstIndex { $0.id == id }
    }

    var totalDuration: Double {
        clips.reduce(0) { $0 + $1.durationSeconds }
    }

    var currentProjectName: String? {
        guard let id = currentProjectID else { return nil }
        return projects.first { $0.id == id }?.name
    }

    private init() {
        loadProjects()
    }

    // MARK: - Import

    func importVideos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select video files to import"

        guard panel.runModal() == .OK else { return }

        Task {
            for url in panel.urls {
                await addVideo(from: url)
            }
        }
    }

    func addVideo(from url: URL) async {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let clip = VideoClip(sourceURL: url, duration: duration)
            clips.append(clip)
            if selectedClipID == nil {
                selectedClipID = clip.id
            }
        } catch {
            exportState = .error("Failed to load: \(url.lastPathComponent)")
        }
    }

    // MARK: - Split

    func splitSelectedClip() {
        guard let index = selectedClipIndex,
              let clip = selectedClip else { return }

        var accumulated: Double = 0
        for i in 0..<index {
            accumulated += clips[i].durationSeconds
        }
        let localTime = playheadPosition - accumulated
        let splitTime = CMTimeMakeWithSeconds(localTime, preferredTimescale: 600)

        guard let (first, second) = clip.split(at: splitTime) else { return }

        clips.replaceSubrange(index...index, with: [first, second])
        selectedClipID = second.id
    }

    // MARK: - Trim

    func trimSelectedClip(newStart: Double, newEnd: Double) {
        guard let index = selectedClipIndex else { return }
        var clip = clips[index]
        let absStart = CMTimeMakeWithSeconds(newStart, preferredTimescale: 600)
        let absEnd = CMTimeMakeWithSeconds(newEnd, preferredTimescale: 600)

        guard CMTimeCompare(absStart, absEnd) < 0,
              CMTimeCompare(absStart, clip.startTime) >= 0 || CMTimeCompare(absStart, .zero) >= 0,
              CMTimeCompare(absEnd, clip.originalDuration) <= 0 else { return }

        clip.startTime = absStart
        clip.endTime = absEnd
        clips[index] = clip
    }

    // MARK: - Remove

    func removeSelectedClip() {
        guard let index = selectedClipIndex else { return }
        clips.remove(at: index)
        if clips.isEmpty {
            selectedClipID = nil
        } else {
            selectedClipID = clips[min(index, clips.count - 1)].id
        }
    }

    func moveClip(from source: IndexSet, to destination: Int) {
        clips.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Export

    func exportTimeline() {
        guard !clips.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Edited Video.mp4"
        panel.message = "Choose where to save the exported video"

        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        Task {
            await performExport(to: outputURL)
        }
    }

    private func performExport(to outputURL: URL) async {
        exportState = .exporting(progress: 0)

        let composition = AVMutableComposition()
        var hasVideo = false
        var hasAudio = false
        var videoTrack: AVMutableCompositionTrack?
        var audioTrack: AVMutableCompositionTrack?
        var insertTime = CMTime.zero

        // First pass: probe which media types exist
        for clip in clips {
            let asset = AVURLAsset(url: clip.sourceURL)
            do {
                let vTracks = try await asset.loadTracks(withMediaType: .video)
                if !vTracks.isEmpty { hasVideo = true }
                let aTracks = try await asset.loadTracks(withMediaType: .audio)
                if !aTracks.isEmpty { hasAudio = true }
            } catch {
                // skip probe errors
            }
        }

        if hasVideo {
            videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }
        if hasAudio {
            audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        guard videoTrack != nil else {
            exportState = .error("No video tracks found in clips")
            return
        }

        // Second pass: insert time ranges
        for (i, clip) in clips.enumerated() {
            let asset = AVURLAsset(url: clip.sourceURL)
            let timeRange = CMTimeRange(start: clip.startTime, end: clip.endTime)

            do {
                if let vTrack = videoTrack {
                    let sourceTracks = try await asset.loadTracks(withMediaType: .video)
                    if let sourceVideo = sourceTracks.first {
                        try vTrack.insertTimeRange(timeRange, of: sourceVideo, at: insertTime)

                        // Apply video transform (rotation) from first clip
                        if i == 0 {
                            let transform = try await sourceVideo.load(.preferredTransform)
                            vTrack.preferredTransform = transform
                        }
                    }
                }

                if let aTrack = audioTrack {
                    let sourceTracks = try await asset.loadTracks(withMediaType: .audio)
                    if let sourceAudio = sourceTracks.first {
                        try aTrack.insertTimeRange(timeRange, of: sourceAudio, at: insertTime)
                    }
                }
            } catch {
                exportState = .error("Failed to process clip \(i + 1): \(error.localizedDescription)")
                return
            }

            insertTime = CMTimeAdd(insertTime, clip.duration)
            exportState = .exporting(progress: Double(i + 1) / Double(clips.count) * 0.3)
        }

        // Remove existing file
        try? FileManager.default.removeItem(at: outputURL)

        // Find a compatible preset
        let presets = [
            AVAssetExportPresetHighestQuality,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetMediumQuality,
        ]

        var chosenPreset: String?
        for preset in presets {
            let compatible = await AVAssetExportSession.compatibility(
                ofExportPreset: preset,
                with: composition,
                outputFileType: .mp4
            )
            if compatible {
                chosenPreset = preset
                break
            }
        }

        guard let preset = chosenPreset else {
            exportState = .error("No compatible export preset found for these clips")
            return
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            exportState = .error("Failed to create export session")
            return
        }

        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        self.exportSession = session

        // Poll progress
        let progressTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                let p = Double(session.progress)
                await MainActor.run {
                    self.exportState = .exporting(progress: 0.3 + p * 0.7)
                }
            }
        }

        await session.export()
        progressTask.cancel()

        switch session.status {
        case .completed:
            exportState = .done(outputURL)
        case .failed:
            let desc = session.error?.localizedDescription ?? "Unknown error"
            exportState = .error("Export failed: \(desc)")
        case .cancelled:
            exportState = .error("Export cancelled")
        default:
            exportState = .error("Export ended with unexpected status")
        }

        self.exportSession = nil
    }

    // MARK: - Projects

    private var projectsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacQoL/VideoProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func saveProject(name: String? = nil) {
        let projectName: String
        if let name = name, !name.isEmpty {
            projectName = name
        } else if let id = currentProjectID, let existing = projects.first(where: { $0.id == id }) {
            projectName = existing.name
        } else {
            projectName = "Untitled Project"
        }

        if let id = currentProjectID, let idx = projects.firstIndex(where: { $0.id == id }) {
            // Update existing
            projects[idx].clips = clips
            projects[idx].name = projectName
            projects[idx].modifiedAt = Date()
            writeProject(projects[idx])
        } else {
            // New project
            let project = VideoProject(name: projectName, clips: clips)
            projects.append(project)
            currentProjectID = project.id
            writeProject(project)
        }
    }

    func saveProjectAs() {
        let alert = NSAlert()
        alert.messageText = "Save Project As"
        alert.informativeText = "Enter a name for this project:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.stringValue = currentProjectName ?? "Untitled Project"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = textField.stringValue.isEmpty ? "Untitled Project" : textField.stringValue

        // Always create new
        let project = VideoProject(name: name, clips: clips)
        projects.append(project)
        currentProjectID = project.id
        writeProject(project)
    }

    func loadProject(_ project: VideoProject) {
        // Validate that source files still exist
        let valid = project.clips.filter { FileManager.default.fileExists(atPath: $0.sourceURL.path) }
        let missing = project.clips.count - valid.count

        clips = valid
        selectedClipID = clips.first?.id
        currentProjectID = project.id
        playheadPosition = 0
        exportState = .idle

        if missing > 0 {
            exportState = .error("\(missing) clip(s) have missing source files and were skipped")
        }
    }

    func deleteProject(_ project: VideoProject) {
        projects.removeAll { $0.id == project.id }
        let file = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        if currentProjectID == project.id {
            currentProjectID = nil
        }
    }

    func newProject() {
        clips.removeAll()
        selectedClipID = nil
        currentProjectID = nil
        playheadPosition = 0
        exportState = .idle
    }

    private func writeProject(_ project: VideoProject) {
        let file = projectsDirectory.appendingPathComponent("\(project.id.uuidString).json")
        do {
            let data = try JSONEncoder().encode(project)
            try data.write(to: file, options: .atomic)
        } catch {
            exportState = .error("Failed to save project: \(error.localizedDescription)")
        }
    }

    private func loadProjects() {
        let dir = projectsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        var loaded: [VideoProject] = []
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let project = try? JSONDecoder().decode(VideoProject.self, from: data) {
                loaded.append(project)
            }
        }
        projects = loaded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func clearAll() {
        clips.removeAll()
        selectedClipID = nil
        exportState = .idle
        playheadPosition = 0
    }
}
