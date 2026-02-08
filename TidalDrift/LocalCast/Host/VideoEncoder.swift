import Foundation
import VideoToolbox
import OSLog

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didOutput packet: Data, isKeyFrame: Bool, timestamp: CMTime)
}

class VideoEncoder {
    private let logger = Logger(subsystem: "com.tidaldrift", category: "VideoEncoder")
    
    weak var delegate: VideoEncoderDelegate?
    
    private var session: VTCompressionSession?
    private let callbackQueue = DispatchQueue(label: "com.tidaldrift.localcast.encoder.callback", qos: .userInteractive)
    
    // Flag to force next frame as keyframe
    private var forceNextKeyFrame = false
    private let keyframeLock = NSLock()
    
    func setup(width: Int, height: Int, codec: LocalCastConfiguration.Codec, bitrateMbps: Int, fps: Int) {
        let vtCodec: CMVideoCodecType = codec == .hevc ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: vtCodec,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: compressionCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            logger.error("Failed to create compression session: \(status)")
            return
        }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: (bitrateMbps * 1000 * 1000) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: codec == .hevc ? kVTProfileLevel_HEVC_Main_AutoLevel : kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: 1.0 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.8 as CFNumber) // 0.8 is very high quality but safer than 1.0
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        logger.info("Video encoder setup complete: \(width)x\(height), \(bitrateMbps)Mbps, \(fps)fps")
    }
    
    func encode(_ sampleBuffer: CMSampleBuffer) {
        guard let session = session, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        
        // Check if we need to force a keyframe
        keyframeLock.lock()
        let shouldForceKeyFrame = forceNextKeyFrame
        if forceNextKeyFrame {
            forceNextKeyFrame = false
        }
        keyframeLock.unlock()
        
        var frameProperties: CFDictionary? = nil
        if shouldForceKeyFrame {
            frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            logger.info("🔑 Encoding forced keyframe NOW")
        }
        
        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: imageBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: duration,
            frameProperties: frameProperties,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }
    
    func invalidate() {
        if let session = session {
            VTCompressionSessionInvalidate(session)
            self.session = nil
        }
    }
    
    func forceKeyFrame() {
        keyframeLock.lock()
        forceNextKeyFrame = true
        keyframeLock.unlock()
        logger.info("🔑 Keyframe requested - will encode next frame as keyframe")
    }
    
    private let compressionCallback: VTCompressionOutputCallback = { (outputCallbackRefCon, sourceFrameRefCon, status, infoFlags, sampleBuffer) in
        guard status == noErr, let sampleBuffer = sampleBuffer else { return }
        
        let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
        
        // 1. Check for keyframe
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let isKeyFrame = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool == false || attachments?.first?[kCMSampleAttachmentKey_NotSync] == nil
        
        // 2. Extract elementary stream data (AVCC format - length prefixed)
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
        
        guard let pointer = pointer else { return }
        
        let avccData = Data(bytes: pointer, count: length)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        var packetData = Data()
        
        // 3. For keyframes, prepend parameter sets (SPS/PPS) with Annex B start codes
        if isKeyFrame {
            encoder.logger.info("🔑 Encoding KEYFRAME")
            if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if let parameterSets = encoder.extractParameterSets(from: formatDescription) {
                    packetData.append(parameterSets)
                    encoder.logger.info("🔑 Prepending SPS/PPS (\(parameterSets.count) bytes) to keyframe")
                }
            }
        }
        
        // 4. Convert AVCC data to Annex B format (replace length prefixes with start codes)
        let annexBData = encoder.convertAVCCToAnnexB(avccData)
        packetData.append(annexBData)
        
        if isKeyFrame {
            encoder.logger.info("🔑 Sending keyframe packet: \(packetData.count) bytes (SPS/PPS + frame)")
        }
        
        encoder.delegate?.videoEncoder(encoder, didOutput: packetData, isKeyFrame: isKeyFrame, timestamp: timestamp)
    }
    
    /// Convert AVCC format (4-byte length prefix) to Annex B format (start codes)
    private func convertAVCCToAnnexB(_ avccData: Data) -> Data {
        var annexBData = Data()
        let bytes = [UInt8](avccData)
        var offset = 0
        
        while offset + 4 <= bytes.count {
            // Read 4-byte length (big endian)
            let nalLength = Int(bytes[offset]) << 24 | Int(bytes[offset+1]) << 16 | Int(bytes[offset+2]) << 8 | Int(bytes[offset+3])
            offset += 4
            
            if nalLength <= 0 || offset + nalLength > bytes.count {
                // Invalid length, just append remaining data with start code
                if offset < bytes.count {
                    annexBData.append(Data([0, 0, 0, 1]))
                    annexBData.append(contentsOf: bytes[offset...])
                }
                break
            }
            
            // Append start code + NAL unit
            annexBData.append(Data([0, 0, 0, 1]))
            annexBData.append(contentsOf: bytes[offset..<(offset + nalLength)])
            offset += nalLength
        }
        
        return annexBData
    }
    
    private func extractParameterSets(from formatDescription: CMFormatDescription) -> Data? {
        var parameterSets = Data()
        
        if CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_H264 {
            var parameterSetCount = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
            
            for i in 0..<parameterSetCount {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointer = pointer {
                    parameterSets.append(Data([0, 0, 0, 1])) // Start code
                    parameterSets.append(pointer, count: size)
                }
            }
        } else if CMFormatDescriptionGetMediaSubType(formatDescription) == kCMVideoCodecType_HEVC {
            // HEVC VPS/SPS/PPS handling
            var parameterSetCount = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
            
            for i in 0..<parameterSetCount {
                var pointer: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &pointer, parameterSetSizeOut: &size, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                if let pointer = pointer {
                    parameterSets.append(Data([0, 0, 0, 1])) // Start code
                    parameterSets.append(pointer, count: size)
                }
            }
        }
        
        return parameterSets.isEmpty ? nil : parameterSets
    }
}

