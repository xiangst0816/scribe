import Foundation
import WhisperKit

/// User-facing voice quality tier. The internal model name is hidden from the UI.
enum VoiceQuality: String, CaseIterable {
    case fast        // openai_whisper-base       ~140 MB
    case balanced    // openai_whisper-small_216MB ~210 MB
    case high        // openai_whisper-large-v3-v20240930_626MB ~600 MB

    var displayName: String {
        switch self {
        case .fast: return L10n.t("quality.fast")
        case .balanced: return L10n.t("quality.balanced")
        case .high: return L10n.t("quality.high")
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
        let folder = modelFolderURL(for: quality)
        let fm = FileManager.default
        // A complete WhisperKit model has three CoreML bundles, each containing
        // both a compiled program (model.mlmodel / model.mil) and its weights.
        // Any of these missing usually means the download was interrupted.
        for sub in ["AudioEncoder.mlmodelc", "MelSpectrogram.mlmodelc", "TextDecoder.mlmodelc"] {
            let bundle = folder.appendingPathComponent(sub, isDirectory: true)
            let mlmodel = bundle.appendingPathComponent("model.mlmodel")
            let weights = bundle.appendingPathComponent("weights", isDirectory: true)
            guard fm.fileExists(atPath: mlmodel.path),
                  let weightFiles = try? fm.contentsOfDirectory(atPath: weights.path),
                  !weightFiles.isEmpty else {
                return false
            }
        }
        return true
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
                update(quality, .failed(L10n.t("error.downloadFailed")))
                await fallbackToWorking(skipping: quality)
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
            // Cached model files exist but WhisperKit can't load them. Almost
            // always means a previous download was interrupted and left a
            // partial bundle. Wipe the cache so the next click re-downloads
            // cleanly instead of re-failing on the same corrupt files.
            try? FileManager.default.removeItem(at: modelFolderURL(for: quality))
            update(quality, .failed("Load failed"))
            await fallbackToWorking(skipping: quality)
        }
    }

    /// After a failed quality, switch the active selection to something that works
    /// so the user can keep dictating instead of being stuck on the broken model.
    /// The failed quality stays visible in the menu and can be retried by clicking it.
    private func fallbackToWorking(skipping failed: VoiceQuality) async {
        // Already have a kit loaded — just promote it to the active selection.
        if let active = loadedQuality, loadedKit != nil, active != failed {
            selectedQuality = active
            update(active, .ready)
            return
        }
        // Otherwise try the first already-downloaded quality.
        for q in VoiceQuality.allCases where q != failed && isDownloaded(q) {
            selectedQuality = q
            await ensureLoadedAsync(q)
            return
        }
        // Nothing else available — leave the failed state visible and let the
        // Apple Speech fallback handle dictation until the user picks something.
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
