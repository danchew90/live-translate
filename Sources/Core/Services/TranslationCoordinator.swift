import AVFoundation
import Combine
import Translation

/// Main coordinator that orchestrates all translation modules
/// Handles the pipeline: Audio → STT → Translation → Subtitles
@available(iOS 18.0, *)
@MainActor
final class TranslationCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isProcessing = false
    @Published private(set) var error: Error?
    @Published private(set) var processingStatus: ProcessingStatus = .idle

    enum ProcessingStatus: String {
        case idle = "Ready"
        case listening = "Listening..."
        case recognizing = "Recognizing speech..."
        case translating = "Translating..."
        case error = "Error"
    }

    // MARK: - Modules

    let videoPlayer = VideoPlayerModule()
    let speechRecognition: SpeechRecognitionModule
    let translation = TranslationModule()
    let subtitleTimeline = SubtitleTimeline()
    let subtitleCompositor = SubtitleCompositor()
    let pipModule = PictureInPictureModule()
    let tts = TextToSpeechModule()
    let configuration = AppConfiguration()

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var currentSegmentId: UUID?
    private var timeUpdateTimer: Timer?

    // MARK: - Initialization

    init() {
        // Initialize speech recognition with default locale
        speechRecognition = SpeechRecognitionModule()

        setupBindings()
        setupDelegates()
        configuration.load()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Sync language settings
        configuration.$sourceLanguage
            .sink { [weak self] language in
                self?.speechRecognition.sourceLanguage = language
            }
            .store(in: &cancellables)

        configuration.$targetLanguage
            .sink { [weak self] language in
                guard let self = self else { return }
                Task {
                    try? await self.translation.configure(
                        source: self.configuration.sourceLanguage,
                        target: language
                    )
                }
                self.tts.language = language
            }
            .store(in: &cancellables)

        configuration.$outputMode
            .sink { [weak self] mode in
                self?.tts.isEnabled = mode == .ttsOnly || mode == .both
            }
            .store(in: &cancellables)

        // Sync subtitle style
        configuration.$subtitleFontSize
            .sink { [weak self] size in
                self?.subtitleCompositor.style.fontSize = size
            }
            .store(in: &cancellables)

        configuration.$subtitleBackgroundOpacity
            .sink { [weak self] opacity in
                self?.subtitleCompositor.style.backgroundColor = .black.withAlphaComponent(opacity)
            }
            .store(in: &cancellables)

        configuration.$showSourceText
            .sink { [weak self] show in
                self?.subtitleCompositor.style.showSourceText = show
            }
            .store(in: &cancellables)

        // Update active subtitles based on video time
        videoPlayer.$currentTime
            .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] time in
                self?.subtitleTimeline.updateActiveSegments(for: time)
            }
            .store(in: &cancellables)
    }

    private func setupDelegates() {
        videoPlayer.audioDelegate = self
        speechRecognition.delegate = self
        translation.delegate = self
        tts.videoPlayer = videoPlayer.player
    }

    // MARK: - Public Methods

    /// Requests necessary permissions
    func requestPermissions() async -> Bool {
        let speechAuthorized = await speechRecognition.requestAuthorization()
        return speechAuthorized
    }

    /// Loads and prepares a video for translation
    func loadVideo(from url: URL) async {
        processingStatus = .idle
        error = nil
        subtitleTimeline.clear()

        await videoPlayer.loadVideo(from: url)

        // Configure translation
        do {
            try await translation.configure(
                source: configuration.sourceLanguage,
                target: configuration.targetLanguage
            )
        } catch {
            self.error = error
            processingStatus = .error
        }

        // Update TTS reference
        tts.videoPlayer = videoPlayer.player
    }

    /// Starts the translation pipeline
    func startTranslation() {
        guard !isProcessing else { return }

        isProcessing = true
        processingStatus = .listening

        // Start speech recognition
        speechRecognition.startRecognition()

        // Start video playback
        videoPlayer.play()
    }

    /// Stops the translation pipeline
    func stopTranslation() {
        isProcessing = false
        processingStatus = .idle

        speechRecognition.stopRecognition()
        videoPlayer.pause()
        tts.stop()
    }

    /// Toggles translation on/off
    func toggleTranslation() {
        if isProcessing {
            stopTranslation()
        } else {
            startTranslation()
        }
    }

    /// Cleans up resources
    func cleanup() {
        stopTranslation()
        translation.invalidateSession()
        pipModule.cleanup()
        timeUpdateTimer?.invalidate()
        configuration.save()
    }
}

// MARK: - AudioExtractionDelegate

@available(iOS 18.0, *)
extension TranslationCoordinator: AudioExtractionDelegate {
    nonisolated func audioExtraction(_ module: AudioExtractionModule, didExtractBuffer buffer: AVAudioPCMBuffer, at time: CMTime) {
        // Forward audio to speech recognition
        Task { @MainActor in
            speechRecognition.appendAudioBuffer(buffer, at: time)
        }
    }

    nonisolated func audioExtraction(_ module: AudioExtractionModule, didEncounterError error: Error) {
        Task { @MainActor in
            self.error = error
            processingStatus = .error
        }
    }
}

// MARK: - SpeechRecognitionDelegate

@available(iOS 18.0, *)
extension TranslationCoordinator: SpeechRecognitionDelegate {
    func speechRecognition(_ module: SpeechRecognitionModule, didRecognize result: SpeechRecognitionResult) {
        processingStatus = .recognizing

        // Create or update subtitle segment
        if result.isFinal || currentSegmentId != result.segmentId {
            // New segment
            let segment = SubtitleSegment(
                id: result.segmentId,
                startTime: result.startTime,
                endTime: result.endTime,
                sourceText: result.text,
                isFinal: result.isFinal
            )

            subtitleTimeline.addSegment(segment)
            currentSegmentId = result.segmentId

            // Translate if final or significant text
            if result.isFinal || result.text.count > 20 {
                Task {
                    processingStatus = .translating
                    await translation.translate(text: result.text, segmentId: result.segmentId)
                }
            }
        } else {
            // Update existing segment
            subtitleTimeline.updateSegment(
                id: result.segmentId,
                translatedText: nil,
                isFinal: result.isFinal
            )
        }
    }

    func speechRecognition(_ module: SpeechRecognitionModule, didChangeAvailability available: Bool) {
        if !available && isProcessing {
            error = NSError(
                domain: "TranslationCoordinator",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognition became unavailable"]
            )
            processingStatus = .error
        }
    }

    func speechRecognition(_ module: SpeechRecognitionModule, didEncounterError error: Error) {
        self.error = error
        processingStatus = .error
    }
}

// MARK: - TranslationDelegate

@available(iOS 18.0, *)
extension TranslationCoordinator: TranslationDelegate {
    func translation(_ module: TranslationModule, didTranslate result: TranslationResult) {
        processingStatus = .listening

        // Update subtitle with translation
        subtitleTimeline.updateSegment(
            id: result.segmentId,
            translatedText: result.translatedText,
            isFinal: true
        )

        // Speak translation if TTS is enabled
        if tts.isEnabled {
            tts.queue(result.translatedText)
        }
    }

    func translation(_ module: TranslationModule, didEncounterError error: Error, for segmentId: UUID) {
        // Keep source text visible on translation error
        print("TranslationCoordinator: Translation failed for segment \(segmentId)")
    }

    func translation(_ module: TranslationModule, didUpdateDownloadProgress progress: Double, for language: Locale.Language) {
        print("TranslationCoordinator: Download progress for \(language.minimalIdentifier): \(progress * 100)%")
    }
}
