import AVFoundation
import Combine

/// Text-to-Speech module using AVSpeechSynthesizer
@MainActor
final class TextToSpeechModule: NSObject, ObservableObject {
    // MARK: - Properties

    @Published private(set) var isSpeaking = false
    @Published var isEnabled = false
    @Published var volume: Float = 0.8
    @Published var rate: Float = AVSpeechUtteranceDefaultSpeechRate
    @Published var language: Locale.Language = Locale.Language(identifier: "ko")

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingUtterances: [String] = []
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

    // Audio ducking
    var audioDuckingEnabled = true
    weak var videoPlayer: AVPlayer?

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public Methods

    /// Speaks the given text
    /// - Parameter text: The text to speak
    func speak(_ text: String) {
        guard isEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.minimalIdentifier)
        utterance.volume = volume
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0

        // Apply audio ducking
        if audioDuckingEnabled {
            applyAudioDucking()
        }

        synthesizer.speak(utterance)
    }

    /// Queues text for speaking after current utterance finishes
    /// - Parameter text: The text to queue
    func queue(_ text: String) {
        guard isEnabled else { return }

        if isSpeaking {
            pendingUtterances.append(text)
        } else {
            speak(text)
        }
    }

    /// Stops all speech immediately
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingUtterances.removeAll()
        restoreAudioDucking()
    }

    /// Pauses speech
    func pause() {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Continues paused speech
    func continueSpeaking() {
        synthesizer.continueSpeaking()
    }

    // MARK: - Audio Ducking

    private func applyAudioDucking() {
        guard audioDuckingEnabled else { return }

        // Lower video volume
        videoPlayer?.volume = 0.2

        // Configure audio session for ducking
        do {
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("TextToSpeechModule: Failed to configure audio session - \(error)")
        }
    }

    private func restoreAudioDucking() {
        guard audioDuckingEnabled else { return }

        // Restore video volume
        videoPlayer?.volume = 1.0

        // Remove ducking
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("TextToSpeechModule: Failed to deactivate audio session - \(error)")
        }
    }

    // MARK: - Available Voices

    /// Returns available voices for the specified language
    static func availableVoices(for language: Locale.Language) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.starts(with: language.minimalIdentifier)
        }
    }

    /// Returns all available languages
    static var availableLanguages: [String] {
        return Array(Set(AVSpeechSynthesisVoice.speechVoices().map { $0.language })).sorted()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TextToSpeechModule: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            restoreAudioDucking()

            // Process pending utterances
            if let next = pendingUtterances.first {
                pendingUtterances.removeFirst()
                speak(next)
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            restoreAudioDucking()
        }
    }
}
