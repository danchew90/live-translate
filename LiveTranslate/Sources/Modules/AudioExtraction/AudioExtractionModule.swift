import AVFoundation
import Accelerate

/// Protocol for receiving extracted audio buffers
protocol AudioExtractionDelegate: AnyObject {
    func audioExtraction(_ module: AudioExtractionModule, didExtractBuffer buffer: AVAudioPCMBuffer, at time: CMTime)
    func audioExtraction(_ module: AudioExtractionModule, didEncounterError error: Error)
}

/// Extracts audio from AVPlayer video using MTAudioProcessingTap
/// Converts audio to mono 16kHz PCM format suitable for Speech framework
final class AudioExtractionModule {
    // MARK: - Properties

    weak var delegate: AudioExtractionDelegate?

    private var audioMix: AVMutableAudioMix?
    private var processingTap: Unmanaged<MTAudioProcessingTap>?

    // Target format for Speech recognition
    private let targetSampleRate: Double = 16000
    private let targetChannelCount: AVAudioChannelCount = 1

    private var audioConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    // Context for the processing tap callbacks
    private class TapContext {
        weak var module: AudioExtractionModule?
        var inputFormat: AVAudioFormat?

        init(module: AudioExtractionModule) {
            self.module = module
        }
    }

    private var tapContext: TapContext?

    // MARK: - Initialization

    init() {
        // Create output format (mono, 16kHz)
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        )
    }

    // MARK: - Public Methods

    /// Creates an audio mix with processing tap for the given player item
    /// - Parameter playerItem: The AVPlayerItem to extract audio from
    /// - Returns: The configured AVAudioMix to be set on the player item
    func createAudioMix(for playerItem: AVPlayerItem) -> AVAudioMix? {
        guard let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first else {
            print("AudioExtractionModule: No audio track found")
            return nil
        }

        // Create tap context
        tapContext = TapContext(module: self)

        // Setup MTAudioProcessingTap callbacks
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(tapContext!).toOpaque()),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )

        // Create the processing tap
        var tap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )

        guard status == noErr, let unwrappedTap = tap else {
            print("AudioExtractionModule: Failed to create processing tap, status: \(status)")
            return nil
        }

        processingTap = unwrappedTap

        // Create audio mix input parameters
        let inputParams = AVMutableAudioMixInputParameters(track: audioTrack)
        inputParams.audioTapProcessor = unwrappedTap.takeUnretainedValue()

        // Create audio mix
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [inputParams]
        self.audioMix = audioMix

        return audioMix
    }

    /// Cleans up resources
    func cleanup() {
        processingTap?.release()
        processingTap = nil
        audioMix = nil
        audioConverter = nil
        tapContext = nil
    }

    // MARK: - Audio Conversion

    fileprivate func convertToTargetFormat(
        buffer: UnsafeMutableAudioBufferListPointer,
        frameCount: CMItemCount,
        inputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard let outputFormat = outputFormat else { return nil }

        // Create or update converter if format changed
        if self.inputFormat != inputFormat {
            self.inputFormat = inputFormat
            audioConverter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        guard let converter = audioConverter else { return nil }

        // Create input buffer from the raw buffer list
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        // Copy data to input buffer
        inputBuffer.frameLength = AVAudioFrameCount(frameCount)
        for i in 0..<min(Int(inputFormat.channelCount), buffer.count) {
            if let src = buffer[i].mData, let dst = inputBuffer.floatChannelData?[i] {
                memcpy(dst, src, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        // Calculate output frame count based on sample rate ratio
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(frameCount) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error {
            print("AudioExtractionModule: Conversion error: \(error?.localizedDescription ?? "unknown")")
            return nil
        }

        return outputBuffer
    }
}

// MARK: - MTAudioProcessingTap Callbacks

private func tapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    // Store context in tap storage
    tapStorageOut.pointee = clientInfo
}

private func tapFinalize(tap: MTAudioProcessingTap) {
    // Cleanup if needed
}

private func tapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    // Get context and store the processing format
    guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
    let context = Unmanaged<AudioExtractionModule.TapContext>.fromOpaque(storage).takeUnretainedValue()

    // Create AVAudioFormat from ASBD
    let asbd = processingFormat.pointee
    context.inputFormat = AVAudioFormat(streamDescription: processingFormat)

    print("AudioExtractionModule: Prepared with format - SR: \(asbd.mSampleRate), CH: \(asbd.mChannelsPerFrame)")
}

private func tapUnprepare(tap: MTAudioProcessingTap) {
    // Cleanup format info
}

private func tapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    // Get the source audio
    var timeRange = CMTimeRange.zero
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        flagsOut,
        &timeRange,
        numberFramesOut
    )

    guard status == noErr else {
        print("AudioExtractionModule: Failed to get source audio, status: \(status)")
        return
    }

    // Get context
    guard let storage = MTAudioProcessingTapGetStorage(tap) else { return }
    let context = Unmanaged<AudioExtractionModule.TapContext>.fromOpaque(storage).takeUnretainedValue()

    guard let module = context.module,
          let inputFormat = context.inputFormat else { return }

    // Convert buffer list to pointer
    let bufferPtr = UnsafeMutableAudioBufferListPointer(bufferListInOut)

    // Convert to target format
    if let convertedBuffer = module.convertToTargetFormat(
        buffer: bufferPtr,
        frameCount: numberFramesOut.pointee,
        inputFormat: inputFormat
    ) {
        // Notify delegate on main thread
        let currentTime = timeRange.start
        DispatchQueue.main.async {
            module.delegate?.audioExtraction(module, didExtractBuffer: convertedBuffer, at: currentTime)
        }
    }
}
