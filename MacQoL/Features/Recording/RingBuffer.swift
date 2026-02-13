import Foundation
import CoreMedia
import AVFoundation

struct EncodedFrame {
    let data: Data
    let presentationTime: CMTime
    let duration: CMTime
    let isKeyframe: Bool
    let isVideo: Bool
}

final class RingBuffer {
    private var videoFrames: [EncodedFrame] = []
    private var audioFrames: [EncodedFrame] = []
    private let lock = NSLock()
    private let maxDuration: TimeInterval

    private(set) var videoFormatDescription: CMFormatDescription?

    init(maxDurationSeconds: Int) {
        self.maxDuration = TimeInterval(maxDurationSeconds)
    }

    func setVideoFormatDescription(_ formatDescription: CMFormatDescription) {
        lock.lock()
        defer { lock.unlock() }
        videoFormatDescription = formatDescription
    }

    func appendVideo(_ frame: EncodedFrame) {
        lock.lock()
        defer { lock.unlock() }

        videoFrames.append(frame)
        pruneOldFrames()
    }

    func appendAudio(_ frame: EncodedFrame) {
        lock.lock()
        defer { lock.unlock() }

        audioFrames.append(frame)
    }

    func getFrames() -> (video: [EncodedFrame], audio: [EncodedFrame], formatDescription: CMFormatDescription?) {
        lock.lock()
        defer { lock.unlock() }

        guard let keyframeIndex = videoFrames.firstIndex(where: { $0.isKeyframe }) else {
            return ([], [], videoFormatDescription)
        }

        let videoResult = Array(videoFrames[keyframeIndex...])

        guard let firstVideoTime = videoResult.first?.presentationTime,
              let lastVideoTime = videoResult.last?.presentationTime else {
            return (videoResult, [], videoFormatDescription)
        }

        let audioResult = audioFrames.filter { frame in
            CMTimeCompare(frame.presentationTime, firstVideoTime) >= 0 &&
            CMTimeCompare(frame.presentationTime, lastVideoTime) <= 0
        }

        return (videoResult, audioResult, videoFormatDescription)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        videoFrames.removeAll()
        audioFrames.removeAll()
    }

    var currentDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard let first = videoFrames.first?.presentationTime,
              let last = videoFrames.last?.presentationTime else {
            return 0
        }

        return CMTimeGetSeconds(CMTimeSubtract(last, first))
    }

    var frameCount: (video: Int, audio: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (videoFrames.count, audioFrames.count)
    }

    private func pruneOldFrames() {
        guard let lastVideoTime = videoFrames.last?.presentationTime else { return }

        let cutoffTime = CMTimeSubtract(lastVideoTime, CMTimeMakeWithSeconds(maxDuration, preferredTimescale: 600))

        var keepFromIndex = 0
        for (index, frame) in videoFrames.enumerated() {
            if CMTimeCompare(frame.presentationTime, cutoffTime) < 0 {
                if frame.isKeyframe {
                    keepFromIndex = index
                }
            } else {
                break
            }
        }

        if keepFromIndex > 0 {
            videoFrames.removeFirst(keepFromIndex)
        }

        audioFrames.removeAll { frame in
            CMTimeCompare(frame.presentationTime, cutoffTime) < 0
        }
    }
}
