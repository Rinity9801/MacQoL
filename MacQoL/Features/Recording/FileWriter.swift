import Foundation
import AVFoundation
import CoreMedia

protocol FileWriterDelegate: AnyObject {
    func fileWriter(_ writer: FileWriter, didFinishWritingTo url: URL)
    func fileWriter(_ writer: FileWriter, didFailWithError error: Error)
}

final class FileWriter {
    weak var delegate: FileWriterDelegate?

    private let writingQueue = DispatchQueue(label: "com.macqol.filewriter", qos: .userInitiated)

    private(set) var isWriting = false

    func writeFrames(
        videoFrames: [EncodedFrame],
        audioFrames: [EncodedFrame],
        videoFormatDescription: CMFormatDescription?,
        to url: URL
    ) {
        writingQueue.async { [weak self] in
            self?.performWrite(
                videoFrames: videoFrames,
                audioFrames: audioFrames,
                videoFormatDescription: videoFormatDescription,
                to: url
            )
        }
    }

    private func performWrite(
        videoFrames: [EncodedFrame],
        audioFrames: [EncodedFrame],
        videoFormatDescription: CMFormatDescription?,
        to url: URL
    ) {
        guard !videoFrames.isEmpty else {
            delegate?.fileWriter(self, didFailWithError: FileWriterError.noFramesToWrite)
            return
        }

        guard let formatDescription = videoFormatDescription else {
            delegate?.fileWriter(self, didFailWithError: FileWriterError.noFormatDescription)
            return
        }

        isWriting = true

        try? FileManager.default.removeItem(at: url)

        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formatDescription)
            videoInput.expectsMediaDataInRealTime = false

            if writer.canAdd(videoInput) {
                writer.add(videoInput)
            } else {
                throw FileWriterError.cannotAddInput
            }

            writer.startWriting()

            guard let firstVideoTime = videoFrames.first?.presentationTime else {
                throw FileWriterError.invalidTimeRange
            }

            writer.startSession(atSourceTime: .zero)

            for frame in videoFrames {
                let adjustedTime = CMTimeSubtract(frame.presentationTime, firstVideoTime)
                let finalTime = CMTimeCompare(adjustedTime, .zero) < 0 ? .zero : adjustedTime

                guard let sampleBuffer = createSampleBuffer(
                    from: frame,
                    at: finalTime,
                    formatDescription: formatDescription
                ) else {
                    continue
                }

                while !videoInput.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.001)
                }

                if !videoInput.append(sampleBuffer) {
                    print("Failed to append sample buffer at \(CMTimeGetSeconds(finalTime))")
                }
            }

            videoInput.markAsFinished()

            let semaphore = DispatchSemaphore(value: 0)
            var writeError: Error?

            writer.finishWriting {
                writeError = writer.error
                semaphore.signal()
            }

            semaphore.wait()

            isWriting = false

            if let error = writeError {
                delegate?.fileWriter(self, didFailWithError: error)
            } else {
                delegate?.fileWriter(self, didFinishWritingTo: url)
            }

        } catch {
            isWriting = false
            delegate?.fileWriter(self, didFailWithError: error)
        }
    }

    private func createSampleBuffer(
        from frame: EncodedFrame,
        at time: CMTime,
        formatDescription: CMFormatDescription
    ) -> CMSampleBuffer? {
        var blockBuffer: CMBlockBuffer?

        let dataCount = frame.data.count
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == kCMBlockBufferNoErr, let blockBuffer = blockBuffer else {
            return nil
        }

        status = frame.data.withUnsafeBytes { rawBufferPointer in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                return kCMBlockBufferUnallocatedBlockErr
            }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: dataCount
            )
        }

        guard status == kCMBlockBufferNoErr else {
            return nil
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: frame.duration,
            presentationTimeStamp: time,
            decodeTimeStamp: time
        )

        var sampleSize = dataCount

        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )

        guard status == noErr, let buffer = sampleBuffer else {
            return nil
        }

        if frame.isKeyframe {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: true)
            if let attachments = attachments as? [NSMutableDictionary], let attachment = attachments.first {
                attachment[kCMSampleAttachmentKey_DependsOnOthers] = false
            }
        }

        return buffer
    }
}

enum FileWriterError: Error, LocalizedError {
    case noFramesToWrite
    case noFormatDescription
    case invalidTimeRange
    case cannotAddInput

    var errorDescription: String? {
        switch self {
        case .noFramesToWrite:
            return "No frames available to write"
        case .noFormatDescription:
            return "No video format description available"
        case .invalidTimeRange:
            return "Invalid time range for frames"
        case .cannotAddInput:
            return "Cannot add input to asset writer"
        }
    }
}
