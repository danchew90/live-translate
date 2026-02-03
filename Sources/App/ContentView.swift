import SwiftUI
import AVKit
import PhotosUI

@available(iOS 18.0, *)
struct ContentView: View {
    @EnvironmentObject var coordinator: TranslationCoordinator
    @EnvironmentObject var configuration: AppConfiguration

    @State private var showSettings = false
    @State private var showVideoPicker = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var permissionsGranted = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if coordinator.videoPlayer.player != nil {
                    // Video player with subtitles
                    VideoPlayerView()
                } else {
                    // Video selection prompt
                    VideoSelectionView(showVideoPicker: $showVideoPicker)
                }
            }
            .navigationTitle("Live Translate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showVideoPicker = true
                    } label: {
                        Image(systemName: "video.badge.plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .photosPicker(
                isPresented: $showVideoPicker,
                selection: $selectedVideoItem,
                matching: .videos
            )
            .onChange(of: selectedVideoItem) { _, newValue in
                Task {
                    await loadSelectedVideo(newValue)
                }
            }
            .task {
                permissionsGranted = await coordinator.requestPermissions()
            }
            .alert("Permissions Required", isPresented: .constant(!permissionsGranted && coordinator.videoPlayer.player != nil)) {
                Button("OK") {}
            } message: {
                Text("Speech recognition permission is required for translation.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadSelectedVideo(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        do {
            if let url = try await item.loadTransferable(type: VideoTransferable.self)?.url {
                await coordinator.loadVideo(from: url)
            }
        } catch {
            print("Failed to load video: \(error)")
        }
    }
}

// MARK: - Video Selection View

struct VideoSelectionView: View {
    @Binding var showVideoPicker: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Select a Video")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a video to translate in real-time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showVideoPicker = true
            } label: {
                Label("Choose Video", systemImage: "photo.on.rectangle")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Video Player View

@available(iOS 18.0, *)
struct VideoPlayerView: View {
    @EnvironmentObject var coordinator: TranslationCoordinator
    @EnvironmentObject var timeline: SubtitleTimeline
    @EnvironmentObject var configuration: AppConfiguration

    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Video layer
            if let player = coordinator.videoPlayer.player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showControls.toggle()
                        }
                        scheduleHideControls()
                    }
            }

            // Subtitle overlay
            AnimatedSubtitleContainer(
                timeline: timeline,
                style: coordinator.subtitleCompositor.style,
                showSourceText: configuration.showSourceText
            )

            // Controls overlay
            if showControls {
                VideoControlsOverlay()
                    .transition(.opacity)
            }

            // Status indicator
            VStack {
                HStack {
                    StatusBadge(status: coordinator.processingStatus)
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Video Controls Overlay

@available(iOS 18.0, *)
struct VideoControlsOverlay: View {
    @EnvironmentObject var coordinator: TranslationCoordinator

    var body: some View {
        VStack {
            Spacer()

            // Playback controls
            HStack(spacing: 40) {
                // Seek backward
                Button {
                    coordinator.videoPlayer.seekRelative(by: -10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                }

                // Play/Pause
                Button {
                    coordinator.videoPlayer.togglePlayPause()
                } label: {
                    Image(systemName: coordinator.videoPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                }

                // Seek forward
                Button {
                    coordinator.videoPlayer.seekRelative(by: 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                }
            }
            .foregroundColor(.white)

            Spacer().frame(height: 40)

            // Progress bar
            ProgressBar(
                currentTime: coordinator.videoPlayer.currentTime,
                duration: coordinator.videoPlayer.duration
            ) { time in
                coordinator.videoPlayer.seek(to: time)
            }
            .padding(.horizontal)

            Spacer().frame(height: 20)

            // Bottom controls
            HStack {
                // Translation toggle
                Button {
                    coordinator.toggleTranslation()
                } label: {
                    Label(
                        coordinator.isProcessing ? "Stop" : "Translate",
                        systemImage: coordinator.isProcessing ? "stop.fill" : "text.bubble"
                    )
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        coordinator.isProcessing ? Color.red : Color.blue,
                        in: Capsule()
                    )
                }

                Spacer()

                // PiP button
                if coordinator.pipModule.isPiPSupported {
                    Button {
                        coordinator.pipModule.togglePiP()
                    } label: {
                        Image(systemName: "pip.enter")
                            .font(.title2)
                    }
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(Color.white)
                        .frame(width: progressWidth(in: geometry.size.width), height: 4)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let progress = value.location.x / geometry.size.width
                            let time = duration * max(0, min(1, progress))
                            onSeek(time)
                        }
                )
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(formatTime(currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.7))
        }
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return totalWidth * CGFloat(currentTime / duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Status Badge

@available(iOS 18.0, *)
struct StatusBadge: View {
    let status: TranslationCoordinator.ProcessingStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(status.rawValue)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var statusColor: Color {
        switch status {
        case .idle: return .gray
        case .listening: return .green
        case .recognizing: return .yellow
        case .translating: return .blue
        case .error: return .red
        }
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

// MARK: - Preview

@available(iOS 18.0, *)
#Preview {
    ContentView()
        .environmentObject(TranslationCoordinator())
        .environmentObject(AppConfiguration())
        .environmentObject(SubtitleTimeline())
}
