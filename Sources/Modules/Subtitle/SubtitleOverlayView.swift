import SwiftUI

/// SwiftUI view for displaying subtitles as an overlay
/// This is the recommended approach for real-time subtitle display during normal playback
struct SubtitleOverlayView: View {
    let segments: [SubtitleSegment]
    let style: SubtitleStyle
    let showSourceText: Bool

    init(
        segments: [SubtitleSegment],
        style: SubtitleStyle = SubtitleStyle(),
        showSourceText: Bool = false
    ) {
        self.segments = segments
        self.style = style
        self.showSourceText = showSourceText
    }

    var body: some View {
        VStack(spacing: 4) {
            Spacer()

            ForEach(segments.suffix(2)) { segment in
                SubtitleTextView(
                    segment: segment,
                    style: style,
                    showSourceText: showSourceText
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, style.bottomMargin)
    }
}

/// Individual subtitle text view
struct SubtitleTextView: View {
    let segment: SubtitleSegment
    let style: SubtitleStyle
    let showSourceText: Bool

    var body: some View {
        VStack(spacing: 2) {
            // Source text (smaller, dimmer)
            if showSourceText, !segment.sourceText.isEmpty {
                Text(segment.sourceText)
                    .font(.system(size: style.sourceTextFontSize))
                    .foregroundColor(Color(style.sourceTextColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            // Translated text (main)
            if let translated = segment.translatedText, !translated.isEmpty {
                Text(translated)
                    .font(.system(size: style.fontSize, weight: .semibold))
                    .foregroundColor(Color(style.textColor))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            } else {
                // Show source text while translation is pending
                Text(segment.sourceText)
                    .font(.system(size: style.fontSize, weight: .semibold))
                    .foregroundColor(Color(style.textColor).opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .italic()
            }
        }
        .padding(.horizontal, style.padding * 2)
        .padding(.vertical, style.padding)
        .background(
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(Color(style.backgroundColor))
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.2), value: segment.translatedText)
    }
}

// MARK: - Animated Subtitle Container

/// Container that manages subtitle animations and transitions
struct AnimatedSubtitleContainer: View {
    @ObservedObject var timeline: SubtitleTimeline
    let style: SubtitleStyle
    let showSourceText: Bool

    var body: some View {
        SubtitleOverlayView(
            segments: timeline.activeSegments,
            style: style,
            showSourceText: showSourceText
        )
        .animation(.easeInOut(duration: 0.3), value: timeline.activeSegments.map { $0.id })
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.gray

        SubtitleOverlayView(
            segments: [
                SubtitleSegment(
                    startTime: 0,
                    endTime: 3,
                    sourceText: "Hello, how are you today?",
                    translatedText: "안녕하세요, 오늘 어떻게 지내세요?",
                    isFinal: true
                ),
                SubtitleSegment(
                    startTime: 3,
                    endTime: 6,
                    sourceText: "I'm doing great, thank you!",
                    translatedText: "잘 지내고 있어요, 감사합니다!",
                    isFinal: true
                )
            ],
            style: SubtitleStyle(),
            showSourceText: true
        )
    }
    .ignoresSafeArea()
}
