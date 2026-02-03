import Speech
import AVFoundation

/// Result from speech recognition
struct SpeechRecognitionResult {
    let text: String
    let isFinal: Bool
    let startTime: TimeInterval
    let endTime: TimeInterval
    let segmentId: UUID
}

/// Protocol for receiving speech recognition results
protocol SpeechRecognitionDelegate: AnyObject {
    func speechRecognition(_ module: SpeechRecognitionModule, didRecognize result: SpeechRecognitionResult)
    func speechRecognition(_ module: SpeechRecognitionModule, didChangeAvailability available: Bool)
    func speechRecognition(_ module: SpeechRecognitionModule, didEncounterError error: Error)
}

/// Handles streaming speech recognition using Apple's Speech framework
@MainActor
final class SpeechRecognitionModule: NSObject, ObservableObject {
    // MARK: - Properties

    weak var delegate: SpeechRecognitionDelegate?

    @Published private(set) var isRecognizing = false
    @Published private(set) var isAvailable = false
    @Published var sourceLanguage: Locale.Language?

    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Segment tracking
    private var currentSegmentId: UUID?
    private var currentSegmentStartTime: TimeInterval = 0
    private var lastResultTime: TimeInterval = 0
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5

    // Audio format expected by the module
    private let expectedFormat: AVAudioFormat

    // MARK: - Initialization

    init(locale: Locale = .current) {
        // Initialize speech recognizer with locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()!

        // Expected format: mono, 16kHz, float32
        self.expectedFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        super.init()

        speechRecognizer.delegate = self
        isAvailable = speechRecognizer.isAvailable
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let authorized = status == .authorized
                Task { @MainActor in
                    self.isAvailable = authorized && self.speechRecognizer.isAvailable
                }
                continuation.resume(returning: authorized)
            }
        }
    }

    // MARK: - Recognition Control

    /// Updates the recognition language
    func updateLanguage(_ language: Locale.Language?) {
        sourceLanguage = language

        // If currently recognizing, restart with new language
        if isRecognizing {
            stopRecognition()
            startRecognition()
        }
    }

    /// Starts streaming speech recognition
    func startRecognition() {
        guard !isRecognizing else { return }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let request = recognitionRequest else {
            print("SpeechRecognitionModule: Failed to create request")
            return
        }

        // Configure for streaming
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // Use on-device recognition if available (iOS 13+)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }

        // Determine which recognizer to use
        let recognizer: SFSpeechRecognizer
        if let language = sourceLanguage {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.minimalIdentifier)) ?? speechRecognizer
        } else {
            recognizer = speechRecognizer
        }

        // Start new segment
        currentSegmentId = UUID()
        currentSegmentStartTime = CACurrentMediaTime()

        // Start recognition task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }

        isRecognizing = true
        startSilenceDetection()

        print("SpeechRecognitionModule: Started recognition")
    }

    /// Stops speech recognition
    func stopRecognition() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        isRecognizing = false

        print("SpeechRecognitionModule: Stopped recognition")
    }

    /// Appends audio buffer for recognition
    /// - Parameters:
    ///   - buffer: The audio buffer to process
    ///   - time: The timestamp of the audio in the video
    nonisolated func appendAudioBuffer(_ buffer: AVAudioPCMBuffer, at time: CMTime) {
        Task { @MainActor in
            guard let request = recognitionRequest else { return }

            // Append buffer to recognition request
            request.append(buffer)

            // Update last result time for silence detection
            lastResultTime = CACurrentMediaTime()
        }
    }

    // MARK: - Private Methods

    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check if it's just a cancellation
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // Recognition was cancelled, not an error
                return
            }

            print("SpeechRecognitionModule: Error - \(error.localizedDescription)")
            delegate?.speechRecognition(self, didEncounterError: error)
            return
        }

        guard let result = result else { return }

        let transcription = result.bestTranscription.formattedString

        // Skip empty results
        guard !transcription.isEmpty else { return }

        // Create result with timing
        let speechResult = SpeechRecognitionResult(
            text: transcription,
            isFinal: result.isFinal,
            startTime: currentSegmentStartTime,
            endTime: CACurrentMediaTime(),
            segmentId: currentSegmentId ?? UUID()
        )

        delegate?.speechRecognition(self, didRecognize: speechResult)

        // If final, start new segment
        if result.isFinal {
            startNewSegment()
        }

        // Reset silence timer
        resetSilenceTimer()
    }

    private func startNewSegment() {
        currentSegmentId = UUID()
        currentSegmentStartTime = CACurrentMediaTime()
    }

    private func startSilenceDetection() {
        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleSilenceDetected()
            }
        }
    }

    private func handleSilenceDetected() {
        // Finalize current segment on silence
        if isRecognizing {
            // End current request and start new one
            recognitionRequest?.endAudio()

            // Small delay then restart
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if self.isRecognizing {
                    self.restartRecognition()
                }
            }
        }
    }

    private func restartRecognition() {
        // Save state
        let wasRecognizing = isRecognizing

        // Stop current
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Restart if was running
        if wasRecognizing {
            startRecognition()
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechRecognitionModule: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            isAvailable = available
            delegate?.speechRecognition(self, didChangeAvailability: available)
        }
    }
}
