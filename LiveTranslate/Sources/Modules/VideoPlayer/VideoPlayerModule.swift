import AVFoundation
import AVKit
import Combine

/// Manages video playback with AVPlayer
@MainActor
final class VideoPlayerModule: ObservableObject {
    // MARK: - Properties

    @Published private(set) var player: AVPlayer?
    @Published private(set) var playerItem: AVPlayerItem?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    // Audio extraction
    private let audioExtraction = AudioExtractionModule()
    weak var audioDelegate: AudioExtractionDelegate? {
        didSet {
            audioExtraction.delegate = audioDelegate
        }
    }

    // MARK: - Initialization

    init() {
        setupNotifications()
    }

    deinit {
        cleanup()
    }

    // MARK: - Video Loading

    /// Loads a video from URL
    func loadVideo(from url: URL) async {
        isLoading = true
        error = nil

        // Clean up previous player
        cleanup()

        // Create asset and player item
        let asset = AVURLAsset(url: url)

        do {
            // Load asset properties
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else {
                throw VideoPlayerError.notPlayable
            }

            // Create player item
            let item = AVPlayerItem(asset: asset)
            playerItem = item

            // Setup audio extraction
            if let audioMix = audioExtraction.createAudioMix(for: item) {
                item.audioMix = audioMix
            }

            // Create player
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer

            // Get duration
            let durationValue = try await asset.load(.duration)
            duration = durationValue.seconds

            // Setup observers
            setupTimeObserver()
            setupStatusObserver()
            setupRateObserver()

            isLoading = false

        } catch {
            self.error = error
            isLoading = false
            print("VideoPlayerModule: Failed to load video - \(error.localizedDescription)")
        }
    }

    /// Loads a video from the app bundle
    func loadBundleVideo(named name: String, extension ext: String) async {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            error = VideoPlayerError.fileNotFound
            return
        }
        await loadVideo(from: url)
    }

    // MARK: - Playback Control

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func seekRelative(by seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    // MARK: - Volume Control

    var volume: Float {
        get { player?.volume ?? 1.0 }
        set { player?.volume = newValue }
    }

    var isMuted: Bool {
        get { player?.isMuted ?? false }
        set { player?.isMuted = newValue }
    }

    // MARK: - Private Methods

    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] notification in
                guard let item = notification.object as? AVPlayerItem,
                      item == self?.playerItem else { return }
                Task { @MainActor in
                    self?.isPlaying = false
                }
            }
            .store(in: &cancellables)
    }

    private func setupTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = time.seconds
            }
        }
    }

    private func setupStatusObserver() {
        statusObserver = playerItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .failed:
                    self?.error = item.error
                    self?.isLoading = false
                case .readyToPlay:
                    self?.isLoading = false
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func setupRateObserver() {
        rateObserver = player?.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.rate > 0
            }
        }
    }

    private func cleanup() {
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        statusObserver?.invalidate()
        statusObserver = nil
        rateObserver?.invalidate()
        rateObserver = nil

        player?.pause()
        player = nil
        playerItem = nil

        audioExtraction.cleanup()
    }
}

// MARK: - Errors

enum VideoPlayerError: LocalizedError {
    case notPlayable
    case fileNotFound
    case loadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notPlayable:
            return "The video cannot be played"
        case .fileNotFound:
            return "Video file not found"
        case .loadFailed(let error):
            return "Failed to load video: \(error.localizedDescription)"
        }
    }
}
