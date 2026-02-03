import Foundation
import Translation

/// Result from translation
struct TranslationResult {
    let sourceText: String
    let translatedText: String
    let segmentId: UUID
    let sourceLanguage: Locale.Language
    let targetLanguage: Locale.Language
}

/// Protocol for receiving translation results
@MainActor
protocol TranslationDelegate: AnyObject {
    func translation(_ module: TranslationModule, didTranslate result: TranslationResult)
    func translation(_ module: TranslationModule, didEncounterError error: Error, for segmentId: UUID)
    func translation(_ module: TranslationModule, didUpdateDownloadProgress progress: Double, for language: Locale.Language)
}

/// Handles text translation using Apple's Translation framework (iOS 18+)
@available(iOS 18.0, *)
@MainActor
final class TranslationModule: ObservableObject {
    // MARK: - Properties

    weak var delegate: TranslationDelegate?

    @Published private(set) var isTranslating = false
    @Published private(set) var availableLanguages: [LanguageAvailability.Status: [Locale.Language]] = [:]
    @Published var sourceLanguage: Locale.Language?
    @Published var targetLanguage: Locale.Language = Locale.Language(identifier: "ko")

    private var translationSession: TranslationSession?
    private var pendingTranslations: [UUID: String] = [:]
    private var translationQueue = OperationQueue()

    // Throttling
    private var lastTranslationTime: Date = .distantPast
    private let minTranslationInterval: TimeInterval = 0.2 // 200ms minimum between translations
    private var backlogCount = 0
    private let maxBacklog = 10

    // MARK: - Initialization

    init() {
        translationQueue.maxConcurrentOperationCount = 2
        translationQueue.qualityOfService = .userInteractive
    }

    // MARK: - Language Availability

    /// Checks which languages are available for translation
    func checkLanguageAvailability() async {
        do {
            let availability = LanguageAvailability()
            var statusMap: [LanguageAvailability.Status: [Locale.Language]] = [:]

            for language in AppConfiguration.supportedLanguages {
                let status = await availability.status(from: sourceLanguage ?? .init(identifier: "en"), to: language)
                if statusMap[status] == nil {
                    statusMap[status] = []
                }
                statusMap[status]?.append(language)
            }

            availableLanguages = statusMap
        }
    }

    /// Downloads a language model for offline use
    func downloadLanguage(_ language: Locale.Language) async throws {
        let configuration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: language
        )

        // Prepare session (this triggers download if needed)
        let session = try await TranslationSession(configuration: configuration)

        // The session preparation should trigger any needed downloads
        print("TranslationModule: Language \(language.minimalIdentifier) is ready")
    }

    // MARK: - Translation

    /// Configures the translation session with the specified language pair
    func configure(source: Locale.Language?, target: Locale.Language) async throws {
        sourceLanguage = source
        targetLanguage = target

        let configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )

        translationSession = try await TranslationSession(configuration: configuration)
        print("TranslationModule: Configured for \(source?.minimalIdentifier ?? "auto") -> \(target.minimalIdentifier)")
    }

    /// Translates text and returns the result
    /// - Parameters:
    ///   - text: The text to translate
    ///   - segmentId: The ID of the subtitle segment
    func translate(text: String, segmentId: UUID) async {
        // Throttling check
        let now = Date()
        if now.timeIntervalSince(lastTranslationTime) < minTranslationInterval {
            // Add to pending and process later
            pendingTranslations[segmentId] = text
            backlogCount += 1

            // If backlog too large, skip older entries
            if backlogCount > maxBacklog {
                // Keep only recent entries
                let entriesToRemove = backlogCount - maxBacklog
                let keysToRemove = Array(pendingTranslations.keys.prefix(entriesToRemove))
                keysToRemove.forEach { pendingTranslations.removeValue(forKey: $0) }
                backlogCount = pendingTranslations.count
            }

            return
        }

        lastTranslationTime = now
        await performTranslation(text: text, segmentId: segmentId)
    }

    private func performTranslation(text: String, segmentId: UUID) async {
        guard let session = translationSession else {
            print("TranslationModule: No session configured")
            return
        }

        // Skip empty text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        isTranslating = true

        do {
            let response = try await session.translate(text)

            let result = TranslationResult(
                sourceText: text,
                translatedText: response.targetText,
                segmentId: segmentId,
                sourceLanguage: response.sourceLanguage,
                targetLanguage: response.targetLanguage
            )

            delegate?.translation(self, didTranslate: result)

        } catch {
            print("TranslationModule: Translation error - \(error.localizedDescription)")
            delegate?.translation(self, didEncounterError: error, for: segmentId)
        }

        isTranslating = false

        // Process any pending translations
        await processPendingTranslations()
    }

    private func processPendingTranslations() async {
        guard !pendingTranslations.isEmpty else { return }

        // Get the most recent pending translation
        if let (segmentId, text) = pendingTranslations.popFirst() {
            backlogCount = pendingTranslations.count
            await performTranslation(text: text, segmentId: segmentId)
        }
    }

    /// Batch translate multiple texts (more efficient for longer texts)
    func translateBatch(items: [(text: String, segmentId: UUID)]) async {
        guard let session = translationSession else { return }
        guard !items.isEmpty else { return }

        isTranslating = true

        do {
            let requests = items.map { TranslationSession.Request(sourceText: $0.text) }
            let responses = try await session.translations(from: requests)

            for (index, response) in responses.enumerated() {
                guard index < items.count else { break }

                let item = items[index]
                let result = TranslationResult(
                    sourceText: item.text,
                    translatedText: response.targetText,
                    segmentId: item.segmentId,
                    sourceLanguage: response.sourceLanguage,
                    targetLanguage: response.targetLanguage
                )

                delegate?.translation(self, didTranslate: result)
            }

        } catch {
            print("TranslationModule: Batch translation error - \(error.localizedDescription)")
            for item in items {
                delegate?.translation(self, didEncounterError: error, for: item.segmentId)
            }
        }

        isTranslating = false
    }

    // MARK: - Cleanup

    func invalidateSession() {
        translationSession?.invalidate()
        translationSession = nil
        pendingTranslations.removeAll()
        backlogCount = 0
    }
}

// MARK: - Language Availability Extension

@available(iOS 18.0, *)
extension LanguageAvailability.Status: Hashable {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .installed:
            hasher.combine(0)
        case .supported:
            hasher.combine(1)
        case .unsupported:
            hasher.combine(2)
        @unknown default:
            hasher.combine(-1)
        }
    }

    public static func == (lhs: LanguageAvailability.Status, rhs: LanguageAvailability.Status) -> Bool {
        switch (lhs, rhs) {
        case (.installed, .installed): return true
        case (.supported, .supported): return true
        case (.unsupported, .unsupported): return true
        default: return false
        }
    }
}
