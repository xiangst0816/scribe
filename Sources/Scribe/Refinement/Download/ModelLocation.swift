import Foundation

/// On-disk location for downloaded model assets. Centralises the path so
/// `LocalPolishService`, the (future) downloader, and tests all agree.
///
/// We intentionally use `Application Support`, not `Caches`, because a 1 GB
/// download the user explicitly opted into shouldn't be silently evicted by
/// the OS under disk pressure.
enum ModelLocation {
    /// Pinned to a specific Qwen build. Bumping this forces a fresh download
    /// (the old file is left on disk for the user to delete manually — we don't
    /// auto-prune in case they want to roll back).
    static let qwenFileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf"

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

    static var qwenURL: URL {
        modelsDirectory.appendingPathComponent(qwenFileName)
    }

    /// `<file>.partial` and `<file>.partial.meta` belong to the (future)
    /// download layer — define here so the layer and the cleanup paths share
    /// the names rather than re-inventing them in two places.
    static var qwenPartialURL: URL {
        modelsDirectory.appendingPathComponent(qwenFileName + ".partial")
    }

    static var qwenPartialMetaURL: URL {
        modelsDirectory.appendingPathComponent(qwenFileName + ".partial.meta")
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

    static func qwenIsPresent() -> Bool {
        FileManager.default.fileExists(atPath: qwenURL.path)
    }
}
