import AVFoundation
import CoreImage
import UIKit

/// Configuration for subtitle rendering
struct SubtitleStyle {
    var fontSize: CGFloat = 18
    var fontName: String = "Helvetica-Bold"
    var textColor: UIColor = .white
    var backgroundColor: UIColor = UIColor.black.withAlphaComponent(0.7)
    var padding: CGFloat = 8
    var cornerRadius: CGFloat = 4
    var bottomMargin: CGFloat = 50
    var maxWidth: CGFloat = 0.9 // Percentage of video width
    var showSourceText: Bool = false
    var sourceTextFontSize: CGFloat = 14
    var sourceTextColor: UIColor = UIColor.white.withAlphaComponent(0.7)
}

/// Composits subtitles onto video frames using AVVideoComposition
/// This approach ensures subtitles appear in PiP mode
@MainActor
final class SubtitleCompositor: ObservableObject {
    // MARK: - Properties

    @Published var style = SubtitleStyle()
    @Published private(set) var currentSubtitle: SubtitleSegment?

    private var subtitleTimeline: SubtitleTimeline?
    private var videoComposition: AVMutableVideoComposition?

    // MARK: - Setup

    /// Creates a video composition with subtitle overlay capability
    /// - Parameters:
    ///   - playerItem: The player item to add composition to
    ///   - timeline: The subtitle timeline to read from
    /// - Returns: The configured video composition
    func createVideoComposition(
        for playerItem: AVPlayerItem,
        timeline: SubtitleTimeline
    ) async -> AVVideoComposition? {
        self.subtitleTimeline = timeline

        guard let videoTrack = try? await playerItem.asset.loadTracks(withMediaType: .video).first else {
            print("SubtitleCompositor: No video track found")
            return nil
        }

        // Get video dimensions
        let size = try? await videoTrack.load(.naturalSize)
        let transform = try? await videoTrack.load(.preferredTransform)

        guard let videoSize = size else { return nil }

        // Apply transform to get correct dimensions
        var renderSize = videoSize
        if let t = transform {
            if t.a == 0 && t.d == 0 {
                // Video is rotated 90 or 270 degrees
                renderSize = CGSize(width: videoSize.height, height: videoSize.width)
            }
        }

        // Create video composition
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: 30)

        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: playerItem.asset.duration
        )

        // Create layer instruction
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        if let t = transform {
            layerInstruction.setTransform(t, at: .zero)
        }
        instruction.layerInstructions = [layerInstruction]

        composition.instructions = [instruction]

        // Setup animation layers for subtitles
        setupAnimationLayers(for: composition, videoSize: renderSize)

        videoComposition = composition
        return composition
    }

    /// Alternative approach: Creates a custom compositor for dynamic subtitle rendering
    func createCustomComposition(
        for playerItem: AVPlayerItem,
        timeline: SubtitleTimeline
    ) async -> AVMutableVideoComposition? {
        self.subtitleTimeline = timeline

        guard let videoTrack = try? await playerItem.asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let size = try? await videoTrack.load(.naturalSize)
        guard let videoSize = size else { return nil }

        let composition = AVMutableVideoComposition(propertiesOf: playerItem.asset)
        composition.customVideoCompositorClass = SubtitleVideoCompositor.self
        composition.renderSize = videoSize

        videoComposition = composition
        return composition
    }

    // MARK: - Layer-based Subtitle Rendering

    private func setupAnimationLayers(
        for composition: AVMutableVideoComposition,
        videoSize: CGSize
    ) {
        // Parent layer (same size as video)
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)

        // Video layer
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)

        // Subtitle layer
        let subtitleLayer = createSubtitleLayer(videoSize: videoSize)

        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(subtitleLayer)

        composition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func createSubtitleLayer(videoSize: CGSize) -> CALayer {
        let containerLayer = CALayer()
        containerLayer.frame = CGRect(origin: .zero, size: videoSize)
        containerLayer.name = "subtitleContainer"

        // Text layer for translated text
        let textLayer = CATextLayer()
        textLayer.name = "subtitleText"
        textLayer.fontSize = style.fontSize * (videoSize.height / 400) // Scale for video size
        textLayer.font = UIFont(name: style.fontName, size: style.fontSize)
        textLayer.foregroundColor = style.textColor.cgColor
        textLayer.backgroundColor = style.backgroundColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.isWrapped = true
        textLayer.truncationMode = .end

        // Position at bottom
        let layerWidth = videoSize.width * style.maxWidth
        let layerHeight: CGFloat = 80
        textLayer.frame = CGRect(
            x: (videoSize.width - layerWidth) / 2,
            y: style.bottomMargin,
            width: layerWidth,
            height: layerHeight
        )
        textLayer.cornerRadius = style.cornerRadius

        containerLayer.addSublayer(textLayer)

        return containerLayer
    }

    // MARK: - Dynamic Subtitle Update

    /// Updates the subtitle text dynamically
    /// Note: For real-time updates, consider using overlay views instead of composition
    func updateSubtitle(_ segment: SubtitleSegment?) {
        currentSubtitle = segment

        // For dynamic subtitles, we'll use the overlay approach
        // The composition approach is better for pre-rendered or exported videos
    }
}

// MARK: - Custom Video Compositor

/// Custom video compositor for dynamic subtitle rendering
final class SubtitleVideoCompositor: NSObject, AVVideoCompositing {
    // Required properties
    var sourcePixelBufferAttributes: [String: Any]? {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
    }

    // Context
    private var renderContext: AVVideoCompositionRenderContext?
    private let ciContext = CIContext()

    // Subtitle state (thread-safe access needed)
    private var currentSubtitleText: String?
    private let subtitleLock = NSLock()

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        autoreleasepool {
            guard let outputBuffer = request.renderContext.newPixelBuffer() else {
                request.finish(with: NSError(domain: "SubtitleCompositor", code: -1))
                return
            }

            // Get source frame
            guard let sourceTrackID = request.sourceTrackIDs.first?.int32Value,
                  let sourceBuffer = request.sourceFrame(byTrackID: sourceTrackID) else {
                request.finish(with: outputBuffer)
                return
            }

            // Create CIImage from source
            var sourceImage = CIImage(cvPixelBuffer: sourceBuffer)

            // Add subtitle overlay if present
            subtitleLock.lock()
            let subtitleText = currentSubtitleText
            subtitleLock.unlock()

            if let text = subtitleText, !text.isEmpty {
                sourceImage = addSubtitleToImage(sourceImage, text: text)
            }

            // Render to output
            ciContext.render(sourceImage, to: outputBuffer)

            request.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        // Cancel any pending work
    }

    // MARK: - Subtitle Rendering

    private func addSubtitleToImage(_ image: CIImage, text: String) -> CIImage {
        let imageSize = image.extent.size

        // Create text image
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let textImage = renderer.image { context in
            // Draw original image (transparent background)
            // We just need the text overlay

            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center

            let fontSize: CGFloat = imageSize.height * 0.04 // 4% of height
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: fontSize),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.7),
                .paragraphStyle: paragraphStyle
            ]

            let textSize = text.size(withAttributes: attributes)
            let padding: CGFloat = 16
            let textRect = CGRect(
                x: (imageSize.width - textSize.width - padding * 2) / 2,
                y: imageSize.height - textSize.height - 60,
                width: textSize.width + padding * 2,
                height: textSize.height + padding
            )

            // Draw background
            let bgPath = UIBezierPath(roundedRect: textRect, cornerRadius: 4)
            UIColor.black.withAlphaComponent(0.7).setFill()
            bgPath.fill()

            // Draw text
            let textDrawRect = CGRect(
                x: textRect.origin.x + padding,
                y: textRect.origin.y + padding / 2,
                width: textSize.width,
                height: textSize.height
            )
            text.draw(in: textDrawRect, withAttributes: attributes)
        }

        // Convert to CIImage and composite
        guard let cgImage = textImage.cgImage else { return image }
        let overlayImage = CIImage(cgImage: cgImage)

        // Composite overlay on source
        let composited = overlayImage.composited(over: image)
        return composited
    }

    // MARK: - Public API

    func updateSubtitle(_ text: String?) {
        subtitleLock.lock()
        currentSubtitleText = text
        subtitleLock.unlock()
    }
}
