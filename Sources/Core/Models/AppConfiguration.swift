import Foundation
import Translation

/// App-wide configuration for translation settings
@MainActor
final class AppConfiguration: ObservableObject {
    // MARK: - Language Settings

    @Published var sourceLanguage: Locale.Language?  // nil = auto-detect
    @Published var targetLanguage: Locale.Language = Locale.Language(identifier: "ko")

    // MARK: - Subtitle Settings

    @Published var subtitleFontSize: CGFloat = 18
    @Published var subtitleBackgroundOpacity: Double = 0.7
    @Published var showSourceText: Bool = false

    // MARK: - Translation Settings

    enum TranslationLatencyMode: String, CaseIterable {
        case faster = "faster"       // Short segments, quicker response
        case natural = "natural"     // Longer segments, more natural

        var segmentThreshold: TimeInterval {
            switch self {
            case .faster: return 1.5
            case .natural: return 3.0
            }
        }
    }

    @Published var translationLatencyMode: TranslationLatencyMode = .natural

    // MARK: - TTS Settings

    enum OutputMode: String, CaseIterable {
        case subtitlesOnly = "subtitles"
        case ttsOnly = "tts"
        case both = "both"
    }

    @Published var outputMode: OutputMode = .subtitlesOnly
    @Published var ttsVolume: Float = 0.8
    @Published var audioDuckingEnabled: Bool = true

    // MARK: - Supported Languages

    static let supportedLanguages: [Locale.Language] = [
        Locale.Language(identifier: "en"),
        Locale.Language(identifier: "ko"),
        Locale.Language(identifier: "ja"),
        Locale.Language(identifier: "zh-Hans"),
        Locale.Language(identifier: "zh-Hant"),
        Locale.Language(identifier: "es"),
        Locale.Language(identifier: "fr"),
        Locale.Language(identifier: "de"),
        Locale.Language(identifier: "it"),
        Locale.Language(identifier: "pt"),
        Locale.Language(identifier: "ru"),
        Locale.Language(identifier: "ar"),
        Locale.Language(identifier: "hi"),
        Locale.Language(identifier: "th"),
        Locale.Language(identifier: "vi")
    ]

    // MARK: - Persistence

    private let defaults = UserDefaults.standard

    func save() {
        defaults.set(sourceLanguage?.minimalIdentifier, forKey: "sourceLanguage")
        defaults.set(targetLanguage.minimalIdentifier, forKey: "targetLanguage")
        defaults.set(subtitleFontSize, forKey: "subtitleFontSize")
        defaults.set(subtitleBackgroundOpacity, forKey: "subtitleBackgroundOpacity")
        defaults.set(showSourceText, forKey: "showSourceText")
        defaults.set(translationLatencyMode.rawValue, forKey: "translationLatencyMode")
        defaults.set(outputMode.rawValue, forKey: "outputMode")
        defaults.set(ttsVolume, forKey: "ttsVolume")
        defaults.set(audioDuckingEnabled, forKey: "audioDuckingEnabled")
    }

    func load() {
        if let sourceId = defaults.string(forKey: "sourceLanguage") {
            sourceLanguage = Locale.Language(identifier: sourceId)
        }
        if let targetId = defaults.string(forKey: "targetLanguage") {
            targetLanguage = Locale.Language(identifier: targetId)
        }
        if defaults.object(forKey: "subtitleFontSize") != nil {
            subtitleFontSize = defaults.double(forKey: "subtitleFontSize")
        }
        if defaults.object(forKey: "subtitleBackgroundOpacity") != nil {
            subtitleBackgroundOpacity = defaults.double(forKey: "subtitleBackgroundOpacity")
        }
        showSourceText = defaults.bool(forKey: "showSourceText")
        if let mode = defaults.string(forKey: "translationLatencyMode"),
           let latencyMode = TranslationLatencyMode(rawValue: mode) {
            translationLatencyMode = latencyMode
        }
        if let mode = defaults.string(forKey: "outputMode"),
           let outMode = OutputMode(rawValue: mode) {
            outputMode = outMode
        }
        if defaults.object(forKey: "ttsVolume") != nil {
            ttsVolume = defaults.float(forKey: "ttsVolume")
        }
        if defaults.object(forKey: "audioDuckingEnabled") != nil {
            audioDuckingEnabled = defaults.bool(forKey: "audioDuckingEnabled")
        }
    }
}
