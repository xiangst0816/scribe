import Foundation

/// Download source for the local Qwen GGUF. Per design doc §4.2, the download
/// layer tries mirrors in order; users in `zh-CN` / `zh-TW` get ModelScope
/// first (faster + works without VPN in mainland China), everyone else gets
/// HuggingFace first.
///
/// All mirrors point at the **same file**. The SHA-256 baked into
/// `ModelDescriptor` must match the bytes from any mirror; a hash mismatch
/// means CDN poisoning or a model version bump and is treated as a fatal
/// download failure (see ModelDownloader).
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

    /// URL for the Qwen2.5-1.5B-Instruct-Q4_K_M GGUF on this mirror.
    var qwenURL: URL {
        switch self {
        case .modelScope:
            return URL(string: "https://modelscope.cn/models/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/master/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
        case .huggingFace:
            return URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
        case .hfMirror:
            return URL(string: "https://hf-mirror.com/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
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

    /// The Qwen build Phase B targets. Pinned against the official ModelScope
    /// mirror's `qwen2.5-1.5b-instruct-q4_k_m.gguf` (Qwen team upload).
    /// Bumping these is a deliberate product decision — see CLAUDE.md.
    static let qwen25_1_5B_Instruct_Q4_K_M = ModelDescriptor(
        fileName: ModelLocation.qwenFileName,
        expectedSize: 1_117_320_736,
        expectedSHA256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e"
    )

    /// `true` when the descriptor is fully pinned and the integrity check
    /// can run. With an empty hash, the downloader refuses to mark a file
    /// as `Verified` — see ModelIntegrity.
    var isPinned: Bool { !expectedSHA256.isEmpty }
}
