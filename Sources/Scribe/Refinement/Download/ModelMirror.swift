import Foundation

/// Download source for the local-polish GGUF. Per design doc §4.2, the
/// download layer tries mirrors in order; users in `zh-CN` / `zh-TW` get
/// ModelScope first (faster + works without VPN in mainland China), everyone
/// else gets HuggingFace first.
///
/// All mirrors point at the **same file** — the bartowski quant of Gemma 4
/// E2B-it Q4_K_M. The SHA-256 baked into `ModelDescriptor` must match the
/// bytes from any mirror; a hash mismatch means CDN poisoning or a model
/// version bump and is treated as a fatal download failure (see ModelDownloader).
enum ModelMirror: String, CaseIterable {
    case modelScope
    case huggingFace
    case hfMirror

    /// User-facing label for the Settings dropdown.
    var displayName: String {
        switch self {
        case .modelScope:  return "ModelScope"
        case .huggingFace: return "HuggingFace"
        case .hfMirror:    return "HF Mirror (hf-mirror.com)"
        }
    }

    /// URL for the pinned GGUF on this mirror. All three mirror the same
    /// `bartowski/google_gemma-4-E2B-it-GGUF` upload.
    var modelURL: URL {
        switch self {
        case .modelScope:
            return URL(string: "https://modelscope.cn/models/bartowski/google_gemma-4-E2B-it-GGUF/resolve/master/google_gemma-4-E2B-it-Q4_K_M.gguf")!
        case .huggingFace:
            return URL(string: "https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!
        case .hfMirror:
            return URL(string: "https://hf-mirror.com/bartowski/google_gemma-4-E2B-it-GGUF/resolve/main/google_gemma-4-E2B-it-Q4_K_M.gguf")!
        }
    }
}

/// User preference for which mirror to start with. `auto` picks based on the
/// recognizer language; an explicit override always wins.
enum ModelMirrorPreference: String {
    case auto
    case modelScope
    case huggingFace
    case hfMirror

    /// Resolve `auto` against the user's selected dictation locale.
    func resolved(forLocaleCode locale: String) -> ModelMirror {
        switch self {
        case .auto:
            return locale.hasPrefix("zh") ? .modelScope : .huggingFace
        case .modelScope:  return .modelScope
        case .huggingFace: return .huggingFace
        case .hfMirror:    return .hfMirror
        }
    }

    /// Fallback order: try the resolved primary first, then the others in a
    /// fixed sequence. Per design doc §4.2 the fallback chain is mirror-aware
    /// rather than arbitrary so users hitting CDN trouble migrate predictably.
    func fallbackChain(forLocaleCode locale: String) -> [ModelMirror] {
        let primary = resolved(forLocaleCode: locale)
        let rest: [ModelMirror]
        switch primary {
        case .modelScope:  rest = [.huggingFace, .hfMirror]
        case .huggingFace: rest = [.modelScope, .hfMirror]
        case .hfMirror:    rest = [.huggingFace, .modelScope]
        }
        return [primary] + rest
    }
}

/// Pin of the exact model file Scribe expects. Bumping this is a deliberate
/// product decision: model version, file name, expected size, expected
/// SHA-256, all change together. Old files on disk become orphans that the
/// user can manually delete (we don't auto-prune).
struct ModelDescriptor {
    let fileName: String
    let expectedSize: Int64
    let expectedSHA256: String

    /// Gemma 4 E2B-it Q4_K_M (~3.46 GB) from `bartowski/google_gemma-4-E2B-it-GGUF`.
    /// Switched from Qwen2.5-1.5B in the v0.4.x line after probe runs showed
    /// E2B handled persona-leak / question-answering / multilingual-preservation
    /// adversarial cases that Qwen 1.5B failed on
    /// (see [docs/polish-model-eval.md](../../../../docs/polish-model-eval.md)).
    static let gemma4_E2B_it_Q4_K_M = ModelDescriptor(
        fileName: ModelLocation.modelFileName,
        expectedSize: 3_462_677_760,
        expectedSHA256: "cded614c9b24be92e5a868d2ba38fb24e15dfea34fc650193c475a6debc233a7"
    )

    /// `true` when the descriptor is fully pinned and the integrity check
    /// can run. With an empty hash, the downloader refuses to mark a file
    /// as `Verified` — see ModelIntegrity.
    var isPinned: Bool { !expectedSHA256.isEmpty }
}
