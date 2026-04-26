import Foundation
import WhisperKit

/// User-facing voice quality tier. The internal model name is hidden from the UI.
enum VoiceQuality: String, CaseIterable {
    case fast        // openai_whisper-base       ~140 MB
    case balanced    // openai_whisper-small_216MB ~210 MB
    case high        // openai_whisper-large-v3-v20240930_626MB ~600 MB

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .high: return "High Quality"
        }
    }

    /// Approximate download size, shown in the menu.
    var sizeLabel: String {
        switch self {
        case .fast: return "140 MB"
        case .balanced: return "210 MB"
        case .high: return "600 MB"
        }
    }

    /// WhisperKit model variant name on HuggingFace.
    var modelVariant: String {
        switch self {
        case .fast: return "openai_whisper-base"
        case .balanced: return "openai_whisper-small_216MB"
        case .high: return "openai_whisper-large-v3-v20240930_626MB"
        }
    }
}

enum ModelState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case loading
    case ready
    case failed(String)
}

/// Manages download, caching and loading of Whisper models.
final class ModelManager {
    static let shared = ModelManager()

    /// Called on the main thread whenever any model state changes.
    var onStateChange: ((VoiceQuality, ModelState) -> Void)?

    private(set) var states: [VoiceQuality: ModelState] = [:]
    private(set) var loadedKit: WhisperKit?
    private(set) var loadedQuality: VoiceQuality?

    private let repoName = "argmaxinc/whisperkit-coreml"

    var selectedQuality: VoiceQuality {
        get {
            let raw = UserDefaults.standard.string(forKey: "voiceQuality") ?? VoiceQuality.balanced.rawValue
            return VoiceQuality(rawValue: raw) ?? .balanced
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "voiceQuality") }
    }

    private init() {
        for q in VoiceQuality.allCases {
            states[q] = isDownloaded(q) ? .downloaded : .notDownloaded
        }
    }

    // MARK: - Filesystem

    /// `~/Library/Application Support/Scribe/Models/<variant>`
    func modelFolderURL(for quality: VoiceQuality) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Scribe", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(quality.modelVariant, isDirectory: true)
    }

    func isDownloaded(_ quality: VoiceQuality) -> Bool {
        let url = modelFolderURL(for: quality)
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        return !contents.isEmpty
    }

    // MARK: - Public actions

    /// Ensure the given quality is downloaded and loaded as the active recognizer.
    /// Calls `onStateChange` repeatedly with download/load progress.
    func ensureLoaded(_ quality: VoiceQuality) {
        Task { await ensureLoadedAsync(quality) }
    }

    func ensureLoadedAsync(_ quality: VoiceQuality) async {
        if loadedQuality == quality, loadedKit != nil {
            update(quality, .ready)
            return
        }

        // Download if missing.
        if !isDownloaded(quality) {
            do {
                try await download(quality)
            } catch {
                update(quality, .failed("Download failed: \(error.localizedDescription)"))
                return
            }
        }

        // Load CoreML models.
        update(quality, .loading)
        do {
            let folder = modelFolderURL(for: quality)
            let config = WhisperKitConfig(
                model: quality.modelVariant,
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: true,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            loadedKit = kit
            loadedQuality = quality
            update(quality, .ready)
        } catch {
            update(quality, .failed("Load failed: \(error.localizedDescription)"))
        }
    }

    func deleteCached(_ quality: VoiceQuality) {
        let url = modelFolderURL(for: quality)
        try? FileManager.default.removeItem(at: url)
        if loadedQuality == quality {
            loadedKit = nil
            loadedQuality = nil
        }
        update(quality, .notDownloaded)
    }

    // MARK: - Private

    private func download(_ quality: VoiceQuality) async throws {
        update(quality, .downloading(progress: 0))

        let parent = modelFolderURL(for: quality).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        let downloadedFolder = try await WhisperKit.download(
            variant: quality.modelVariant,
            from: repoName,
            progressCallback: { [weak self] progress in
                self?.update(quality, .downloading(progress: progress.fractionCompleted))
            }
        )

        // WhisperKit downloads to its own cache; relocate to our app support folder.
        let target = modelFolderURL(for: quality)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: downloadedFolder, to: target)

        update(quality, .downloaded)
    }

    private func update(_ quality: VoiceQuality, _ state: ModelState) {
        DispatchQueue.main.async {
            self.states[quality] = state
            self.onStateChange?(quality, state)
        }
    }
}
