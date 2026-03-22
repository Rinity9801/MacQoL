import Foundation
import AVFoundation

struct VideoClip: Identifiable, Equatable, Codable {
    let id: UUID
    let sourceURL: URL
    var startTime: CMTime
    var endTime: CMTime
    let originalDuration: CMTime

    var duration: CMTime {
        CMTimeSubtract(endTime, startTime)
    }

    var durationSeconds: Double {
        CMTimeGetSeconds(duration)
    }

    var startSeconds: Double {
        get { CMTimeGetSeconds(startTime) }
        set { startTime = CMTimeMakeWithSeconds(newValue, preferredTimescale: 600) }
    }

    var endSeconds: Double {
        get { CMTimeGetSeconds(endTime) }
        set { endTime = CMTimeMakeWithSeconds(newValue, preferredTimescale: 600) }
    }

    var originalDurationSeconds: Double {
        CMTimeGetSeconds(originalDuration)
    }

    init(sourceURL: URL, duration: CMTime) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.startTime = .zero
        self.endTime = duration
        self.originalDuration = duration
    }

    init(id: UUID, sourceURL: URL, startTime: CMTime, endTime: CMTime, originalDuration: CMTime) {
        self.id = id
        self.sourceURL = sourceURL
        self.startTime = startTime
        self.endTime = endTime
        self.originalDuration = originalDuration
    }

    func split(at time: CMTime) -> (VideoClip, VideoClip)? {
        let absoluteTime = CMTimeAdd(startTime, time)
        guard CMTimeCompare(absoluteTime, startTime) > 0,
              CMTimeCompare(absoluteTime, endTime) < 0 else {
            return nil
        }

        let first = VideoClip(
            id: UUID(),
            sourceURL: sourceURL,
            startTime: startTime,
            endTime: absoluteTime,
            originalDuration: originalDuration
        )
        let second = VideoClip(
            id: UUID(),
            sourceURL: sourceURL,
            startTime: absoluteTime,
            endTime: endTime,
            originalDuration: originalDuration
        )
        return (first, second)
    }

    static func == (lhs: VideoClip, rhs: VideoClip) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, sourceURL, startValue, startTimescale, endValue, endTimescale, origValue, origTimescale
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sourceURL, forKey: .sourceURL)
        try c.encode(startTime.value, forKey: .startValue)
        try c.encode(startTime.timescale, forKey: .startTimescale)
        try c.encode(endTime.value, forKey: .endValue)
        try c.encode(endTime.timescale, forKey: .endTimescale)
        try c.encode(originalDuration.value, forKey: .origValue)
        try c.encode(originalDuration.timescale, forKey: .origTimescale)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sourceURL = try c.decode(URL.self, forKey: .sourceURL)
        let sv = try c.decode(Int64.self, forKey: .startValue)
        let st = try c.decode(Int32.self, forKey: .startTimescale)
        startTime = CMTime(value: sv, timescale: st)
        let ev = try c.decode(Int64.self, forKey: .endValue)
        let et = try c.decode(Int32.self, forKey: .endTimescale)
        endTime = CMTime(value: ev, timescale: et)
        let ov = try c.decode(Int64.self, forKey: .origValue)
        let ot = try c.decode(Int32.self, forKey: .origTimescale)
        originalDuration = CMTime(value: ov, timescale: ot)
    }
}

// MARK: - Project

struct VideoProject: Codable, Identifiable {
    let id: UUID
    var name: String
    var clips: [VideoClip]
    var createdAt: Date
    var modifiedAt: Date

    init(name: String, clips: [VideoClip]) {
        self.id = UUID()
        self.name = name
        self.clips = clips
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}
