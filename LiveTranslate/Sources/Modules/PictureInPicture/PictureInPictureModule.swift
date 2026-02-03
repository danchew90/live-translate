import AVKit
import Combine

/// Protocol for PiP events
@MainActor
protocol PictureInPictureDelegate: AnyObject {
    func pipDidStart(_ module: PictureInPictureModule)
    func pipDidStop(_ module: PictureInPictureModule)
    func pipWillStart(_ module: PictureInPictureModule)
    func pipWillStop(_ module: PictureInPictureModule)
    func pip(_ module: PictureInPictureModule, restoreUserInterfaceWithCompletion: @escaping (Bool) -> Void)
}

/// Manages Picture-in-Picture functionality
/// For subtitles to appear in PiP, they must be rendered into the video composition
@MainActor
final class PictureInPictureModule: NSObject, ObservableObject {
    // MARK: - Properties

    weak var delegate: PictureInPictureDelegate?

    @Published private(set) var isPiPSupported = false
    @Published private(set) var isPiPActive = false
    @Published private(set) var isPiPPossible = false

    private var pipController: AVPictureInPictureController?
    private var playerLayer: AVPlayerLayer?
    private var observations: [NSKeyValueObservation] = []

    // MARK: - Setup

    /// Checks if PiP is supported on this device
    static var isSupported: Bool {
        return AVPictureInPictureController.isPictureInPictureSupported()
    }

    /// Sets up PiP controller with the given player layer
    /// - Parameter playerLayer: The AVPlayerLayer to use for PiP
    func setup(with playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer

        guard Self.isSupported else {
            print("PictureInPictureModule: PiP not supported on this device")
            isPiPSupported = false
            return
        }

        isPiPSupported = true

        // Create PiP controller
        pipController = AVPictureInPictureController(playerLayer: playerLayer)
        pipController?.delegate = self

        // Observe isPictureInPicturePossible
        let possibleObservation = pipController?.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] controller, _ in
            Task { @MainActor in
                self?.isPiPPossible = controller.isPictureInPicturePossible
            }
        }

        if let obs = possibleObservation {
            observations.append(obs)
        }

        print("PictureInPictureModule: Setup complete")
    }

    /// Sets up PiP using AVPlayerViewController (alternative approach)
    /// This method gives you the standard Apple video controls with PiP button
    func setup(with playerViewController: AVPlayerViewController) {
        guard Self.isSupported else {
            isPiPSupported = false
            return
        }

        isPiPSupported = true

        // AVPlayerViewController handles its own PiP controller
        playerViewController.allowsPictureInPicturePlayback = true

        // For custom control, you can still get the controller
        // But it's created internally by AVPlayerViewController

        print("PictureInPictureModule: Setup with AVPlayerViewController complete")
    }

    // MARK: - PiP Control

    /// Starts Picture-in-Picture if possible
    func startPiP() {
        guard isPiPSupported, isPiPPossible else {
            print("PictureInPictureModule: Cannot start PiP - supported: \(isPiPSupported), possible: \(isPiPPossible)")
            return
        }

        pipController?.startPictureInPicture()
    }

    /// Stops Picture-in-Picture
    func stopPiP() {
        pipController?.stopPictureInPicture()
    }

    /// Toggles PiP state
    func togglePiP() {
        if isPiPActive {
            stopPiP()
        } else {
            startPiP()
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        pipController = nil
        playerLayer = nil
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension PictureInPictureModule: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            delegate?.pipWillStart(self)
            print("PictureInPictureModule: Will start PiP")
        }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = true
            delegate?.pipDidStart(self)
            print("PictureInPictureModule: Did start PiP")
        }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            delegate?.pipWillStop(self)
            print("PictureInPictureModule: Will stop PiP")
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            isPiPActive = false
            delegate?.pipDidStop(self)
            print("PictureInPictureModule: Did stop PiP")
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            delegate?.pip(self, restoreUserInterfaceWithCompletion: completionHandler)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            print("PictureInPictureModule: Failed to start PiP - \(error.localizedDescription)")
        }
    }
}

// MARK: - PiP-Compatible Video Player View

/// A UIViewRepresentable that provides PiP-compatible video playback
/// Use this when you need custom PiP behavior with subtitles
struct PiPVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer?
    let pipModule: PictureInPictureModule

    func makeUIView(context: Context) -> PiPVideoView {
        let view = PiPVideoView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: PiPVideoView, context: Context) {
        uiView.player = player

        // Setup PiP when player layer is available
        if let playerLayer = uiView.playerLayer {
            Task { @MainActor in
                pipModule.setup(with: playerLayer)
            }
        }
    }
}

/// UIView subclass that provides direct access to AVPlayerLayer
final class PiPVideoView: UIView {
    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer? {
        return layer as? AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer?.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        playerLayer?.videoGravity = .resizeAspect
    }
}
