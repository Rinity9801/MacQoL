import Foundation
import AVFoundation
import CoreMedia

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didOutputSampleBuffer sampleBuffer: CMSampleBuffer)
    func audioEngine(_ engine: AudioEngine, didFailWithError error: Error)
}

final class AudioEngine {
    weak var delegate: AudioEngineDelegate?

    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let processingQueue = DispatchQueue(label: "com.macqol.audio.processing", qos: .userInteractive)

    private(set) var isRunning = false
    private(set) var selectedDeviceID: String?

    private var audioFormat: AVAudioFormat?
    private var sampleRate: Double = 48000
    private var channelCount: AVAudioChannelCount = 2

    private var formatDescription: CMAudioFormatDescription?
    private var currentPresentationTime: CMTime = .zero

    func getAvailableMicrophones() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        return discoverySession.devices
    }

    func getDefaultMicrophone() -> AVCaptureDevice? {
        AVCaptureDevice.default(for: .audio)
    }

    func startCapture(deviceID: String? = nil) throws {
        guard !isRunning else { return }

        let engine = AVAudioEngine()

        if let deviceID = deviceID {
            selectedDeviceID = deviceID
        }

        inputNode = engine.inputNode
        guard let inputNode = inputNode else {
            throw AudioEngineError.noInputAvailable
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        ) else {
            throw AudioEngineError.formatCreationFailed
        }

        audioFormat = outputFormat

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: UInt32(channelCount),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        isRunning = true
        currentPresentationTime = CMClockGetTime(CMClockGetHostTimeClock())
    }

    func stopCapture() {
        guard isRunning else { return }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isRunning = false
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        processingQueue.async { [weak self] in
            guard let self = self,
                  let formatDescription = self.formatDescription else { return }

            do {
                let sampleBuffer = try self.createSampleBuffer(from: buffer, formatDescription: formatDescription)
                self.delegate?.audioEngine(self, didOutputSampleBuffer: sampleBuffer)
            } catch {
                self.delegate?.audioEngine(self, didFailWithError: error)
            }
        }
    }

    private func createSampleBuffer(
        from audioBuffer: AVAudioPCMBuffer,
        formatDescription: CMAudioFormatDescription
    ) throws -> CMSampleBuffer {
        let frameCount = audioBuffer.frameLength
        let duration = CMTimeMake(value: Int64(frameCount), timescale: Int32(sampleRate))

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: currentPresentationTime,
            decodeTimeStamp: .invalid
        )

        currentPresentationTime = CMTimeAdd(currentPresentationTime, duration)

        guard let channelData = audioBuffer.floatChannelData else {
            throw AudioEngineError.noAudioData
        }

        let dataSize = Int(frameCount) * MemoryLayout<Float>.size * Int(channelCount)
        var blockBuffer: CMBlockBuffer?

        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard let blockBuffer = blockBuffer else {
            throw AudioEngineError.blockBufferCreationFailed
        }

        var offset = 0
        for frame in 0..<Int(frameCount) {
            for channel in 0..<Int(channelCount) {
                let sample = channelData[channel][frame]
                CMBlockBufferReplaceDataBytes(
                    with: [sample],
                    blockBuffer: blockBuffer,
                    offsetIntoDestination: offset,
                    dataLength: MemoryLayout<Float>.size
                )
                offset += MemoryLayout<Float>.size
            }
        }

        CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frameCount),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let result = sampleBuffer else {
            throw AudioEngineError.sampleBufferCreationFailed
        }

        return result
    }
}

enum AudioEngineError: Error, LocalizedError {
    case noInputAvailable
    case formatCreationFailed
    case noAudioData
    case blockBufferCreationFailed
    case sampleBufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .noInputAvailable:
            return "No audio input device available"
        case .formatCreationFailed:
            return "Failed to create audio format"
        case .noAudioData:
            return "No audio data in buffer"
        case .blockBufferCreationFailed:
            return "Failed to create audio block buffer"
        case .sampleBufferCreationFailed:
            return "Failed to create audio sample buffer"
        }
    }
}
