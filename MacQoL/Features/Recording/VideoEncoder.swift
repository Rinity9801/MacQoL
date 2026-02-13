import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didOutputEncodedFrame frame: EncodedFrame)
    func videoEncoder(_ encoder: VideoEncoder, didOutputFormatDescription formatDescription: CMFormatDescription)
    func videoEncoder(_ encoder: VideoEncoder, didFailWithError error: Error)
}

final class VideoEncoder {
    weak var delegate: VideoEncoderDelegate?

    private var compressionSession: VTCompressionSession?
    private let encodingQueue = DispatchQueue(label: "com.macqol.encoding", qos: .userInteractive)

    private(set) var isEncoding = false
    private var width: Int32 = 1920
    private var height: Int32 = 1080
    private var frameRate: Int32 = 60
    private var useHEVC: Bool = false

    private var hasOutputFormatDescription = false

    func setup(width: Int, height: Int, frameRate: Int, useHEVC: Bool) throws {
        self.width = Int32(width)
        self.height = Int32(height)
        self.frameRate = Int32(frameRate)
        self.useHEVC = useHEVC
        self.hasOutputFormatDescription = false

        try createCompressionSession()
    }

    private func createCompressionSession() throws {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }

        let codecType: CMVideoCodecType = useHEVC ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264

        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: codecType,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
            ] as CFDictionary,
            imageBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height
            ] as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw VideoEncoderError.sessionCreationFailed(status)
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                            value: useHEVC ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)

        let bitrate = calculateBitrate()
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)

        let keyframeInterval = frameRate * 2
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: keyframeInterval as CFNumber)

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: frameRate as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(session)

        compressionSession = session
        isEncoding = true
    }

    private func calculateBitrate() -> Int {
        let pixels = Int(width) * Int(height)
        let baseRate: Double

        if pixels >= 1920 * 1080 {
            baseRate = 8_000_000
        } else if pixels >= 1280 * 720 {
            baseRate = 5_000_000
        } else {
            baseRate = 3_000_000
        }

        let frameRateMultiplier = Double(frameRate) / 30.0
        return Int(baseRate * frameRateMultiplier)
    }

    func encode(sampleBuffer: CMSampleBuffer) {
        guard isEncoding, let session = compressionSession else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        encodingQueue.async { [weak self] in
            self?.encodeFrame(session: session, pixelBuffer: pixelBuffer, presentationTime: presentationTime, duration: duration)
        }
    }

    private func encodeFrame(session: VTCompressionSession, pixelBuffer: CVPixelBuffer, presentationTime: CMTime, duration: CMTime) {
        var infoFlags = VTEncodeInfoFlags()

        let frameDuration = CMTIME_IS_VALID(duration) ? duration : CMTime(value: 1, timescale: CMTimeScale(frameRate))

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: frameDuration,
            frameProperties: nil,
            infoFlagsOut: &infoFlags
        ) { [weak self] status, _, sampleBuffer in
            guard let self = self else { return }

            if status != noErr {
                self.delegate?.videoEncoder(self, didFailWithError: VideoEncoderError.encodingFailed(status))
                return
            }

            guard let sampleBuffer = sampleBuffer else { return }

            self.processSampleBuffer(sampleBuffer)
        }

        if status != noErr {
            delegate?.videoEncoder(self, didFailWithError: VideoEncoderError.encodingFailed(status))
        }
    }

    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        if !hasOutputFormatDescription {
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                delegate?.videoEncoder(self, didOutputFormatDescription: formatDescription)
                hasOutputFormatDescription = true
            }
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard status == noErr, let dataPointer = dataPointer else { return }

        let data = Data(bytes: dataPointer, count: length)
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        let isKeyframe = isKeyFrame(sampleBuffer)

        let frame = EncodedFrame(
            data: data,
            presentationTime: presentationTime,
            duration: duration,
            isKeyframe: isKeyframe,
            isVideo: true
        )

        delegate?.videoEncoder(self, didOutputEncodedFrame: frame)
    }

    private func isKeyFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
              let attachment = attachments.first else {
            return true
        }

        let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        return !notSync
    }

    func stop() {
        guard isEncoding else { return }

        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
        }

        compressionSession = nil
        isEncoding = false
        hasOutputFormatDescription = false
    }
}

enum VideoEncoderError: Error, LocalizedError {
    case sessionCreationFailed(OSStatus)
    case encodingFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let status):
            return "Failed to create compression session: \(status)"
        case .encodingFailed(let status):
            return "Encoding failed: \(status)"
        }
    }
}
