import Foundation

/// Represents a single subtitle segment with timing and text information
struct SubtitleSegment: Identifiable, Equatable {
    let id: UUID
    let startTime: TimeInterval
    var endTime: TimeInterval
    let sourceText: String
    var translatedText: String?
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval = 0,
        sourceText: String,
        translatedText: String? = nil,
        isFinal: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.isFinal = isFinal
    }

    /// Check if this segment should be displayed at the given time
    func isActive(at time: TimeInterval, displayDuration: TimeInterval = 3.0) -> Bool {
        let effectiveEndTime = endTime > 0 ? endTime : startTime + displayDuration
        return time >= startTime && time <= effectiveEndTime
    }
}

/// Timeline manager for subtitle segments
@MainActor
final class SubtitleTimeline: ObservableObject {
    @Published private(set) var segments: [SubtitleSegment] = []
    @Published private(set) var activeSegments: [SubtitleSegment] = []

    private let maxActiveSegments = 2
    private let maxStoredSegments = 100

    func addSegment(_ segment: SubtitleSegment) {
        segments.append(segment)

        // Limit stored segments to prevent memory growth
        if segments.count > maxStoredSegments {
            segments.removeFirst(segments.count - maxStoredSegments)
        }
    }

    func updateSegment(id: UUID, translatedText: String?, isFinal: Bool) {
        guard let index = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[index].translatedText = translatedText
        segments[index].isFinal = isFinal
    }

    func updateActiveSegments(for currentTime: TimeInterval) {
        activeSegments = segments
            .filter { $0.isActive(at: currentTime) }
            .suffix(maxActiveSegments)
            .map { $0 }
    }

    func clear() {
        segments.removeAll()
        activeSegments.removeAll()
    }
}
