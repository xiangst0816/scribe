import Foundation

/// On-disk location for the downloaded local-polish model. Centralises the
/// path so `LocalPolishService`, `ModelDownloader`, and tests all agree.
///
/// `Application Support`, not `Caches`: a multi-GB download the user explicitly
/// opted into shouldn't be silently evicted by the OS under disk pressure.
///
/// Names are deliberately model-agnostic (`modelFileName`, `modelURL`) so that
/// swapping the pinned build is a single-file change in `ModelDescriptor`. The
/// fileName itself does encode the model identity, so previous downloads land
/// in different files and can be deleted manually if the user wants the disk
/// space back — we don't auto-prune.
enum ModelLocation {
    /// Pinned to a specific GGUF build. Bumping this is a deliberate product
    /// decision (see CLAUDE.md). Old files with previous names are left on
    /// disk so a user who rolls back doesn't have to re-download.
    static let modelFileName = "gemma-4-E2B-it-Q4_K_M.gguf"

    /// `~/Library/Application Support/Scribe/`
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Scribe", isDirectory: true)
    }

    /// `~/Library/Application Support/Scribe/models/`
    static var modelsDirectory: URL {
        supportDirectory.appendingPathComponent("models", isDirectory: true)
    }

    static var modelURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    /// `<file>.partial` and `<file>.partial.meta` belong to the download layer
    /// — defined here so the layer and the cleanup paths share the names rather
    /// than re-inventing them in two places.
    static var modelPartialURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName + ".partial")
    }

    static var modelPartialMetaURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName + ".partial.meta")
    }

    /// Best-effort directory creation. Returns `false` if we couldn't create it
    /// (e.g. user hardened ~ with weird perms) so the caller can surface the
    /// failure rather than silently failing later in the download flow.
    @discardableResult
    static func ensureModelsDirectoryExists() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: modelsDirectory,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }

    static func modelIsPresent() -> Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }
}
