import SwiftUI
import Translation

@available(iOS 18.0, *)
struct SettingsView: View {
    @EnvironmentObject var configuration: AppConfiguration
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Language Settings
                Section("Language") {
                    Picker("Source Language", selection: $configuration.sourceLanguage) {
                        Text("Auto-detect").tag(nil as Locale.Language?)
                        ForEach(AppConfiguration.supportedLanguages, id: \.minimalIdentifier) { language in
                            Text(languageDisplayName(language))
                                .tag(language as Locale.Language?)
                        }
                    }

                    Picker("Target Language", selection: $configuration.targetLanguage) {
                        ForEach(AppConfiguration.supportedLanguages, id: \.minimalIdentifier) { language in
                            Text(languageDisplayName(language))
                                .tag(language)
                        }
                    }
                }

                // Subtitle Settings
                Section("Subtitles") {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(configuration.subtitleFontSize))")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $configuration.subtitleFontSize,
                        in: 12...32,
                        step: 1
                    )

                    HStack {
                        Text("Background Opacity")
                        Spacer()
                        Text("\(Int(configuration.subtitleBackgroundOpacity * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $configuration.subtitleBackgroundOpacity,
                        in: 0...1,
                        step: 0.1
                    )

                    Toggle("Show Source Text", isOn: $configuration.showSourceText)
                }

                // Translation Settings
                Section("Translation") {
                    Picker("Translation Mode", selection: $configuration.translationLatencyMode) {
                        ForEach(AppConfiguration.TranslationLatencyMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode == .faster ? "Faster" : "Natural")
                            }
                            .tag(mode)
                        }
                    }

                    Text(configuration.translationLatencyMode == .faster
                         ? "Shorter segments, quicker response"
                         : "Longer segments, more natural translation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Output Settings
                Section("Output") {
                    Picker("Output Mode", selection: $configuration.outputMode) {
                        Text("Subtitles Only").tag(AppConfiguration.OutputMode.subtitlesOnly)
                        Text("TTS Only").tag(AppConfiguration.OutputMode.ttsOnly)
                        Text("Both").tag(AppConfiguration.OutputMode.both)
                    }

                    if configuration.outputMode != .subtitlesOnly {
                        HStack {
                            Text("TTS Volume")
                            Spacer()
                            Text("\(Int(configuration.ttsVolume * 100))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: $configuration.ttsVolume,
                            in: 0...1,
                            step: 0.1
                        )

                        Toggle("Audio Ducking", isOn: $configuration.audioDuckingEnabled)

                        Text("Lowers video volume while speaking")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("iOS Requirement")
                        Spacer()
                        Text("iOS 18+")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        LanguageDownloadView()
                    } label: {
                        Text("Download Languages")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        configuration.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func languageDisplayName(_ language: Locale.Language) -> String {
        let locale = Locale.current
        return locale.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}

// MARK: - Language Download View

@available(iOS 18.0, *)
struct LanguageDownloadView: View {
    @State private var languageStatuses: [Locale.Language: LanguageAvailability.Status] = [:]
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                ProgressView("Checking availability...")
            } else {
                ForEach(AppConfiguration.supportedLanguages, id: \.minimalIdentifier) { language in
                    LanguageRow(
                        language: language,
                        status: languageStatuses[language] ?? .unsupported
                    )
                }
            }
        }
        .navigationTitle("Languages")
        .task {
            await checkLanguageAvailability()
        }
    }

    private func checkLanguageAvailability() async {
        let availability = LanguageAvailability()
        var statuses: [Locale.Language: LanguageAvailability.Status] = [:]

        for language in AppConfiguration.supportedLanguages {
            let status = await availability.status(
                from: Locale.Language(identifier: "en"),
                to: language
            )
            statuses[language] = status
        }

        languageStatuses = statuses
        isLoading = false
    }
}

// MARK: - Language Row

@available(iOS 18.0, *)
struct LanguageRow: View {
    let language: Locale.Language
    let status: LanguageAvailability.Status

    @State private var isDownloading = false

    var body: some View {
        HStack {
            Text(languageDisplayName)

            Spacer()

            statusView
        }
    }

    private var languageDisplayName: String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)

        case .supported:
            if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Download") {
                    downloadLanguage()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

        case .unsupported:
            Text("Not available")
                .foregroundStyle(.secondary)
                .font(.caption)

        @unknown default:
            Text("Unknown")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }

    private func downloadLanguage() {
        isDownloading = true

        Task {
            do {
                let config = TranslationSession.Configuration(
                    source: nil,
                    target: language
                )
                _ = try await TranslationSession(configuration: config)
                isDownloading = false
            } catch {
                print("Failed to download language: \(error)")
                isDownloading = false
            }
        }
    }
}

// MARK: - Preview

@available(iOS 18.0, *)
#Preview {
    SettingsView()
        .environmentObject(AppConfiguration())
}
