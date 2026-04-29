import Foundation

/// One transcript-polishing engine. The coordinator owns one of each kind
/// (System / Local) and routes per-call to whichever the user selected.
///
/// Contract:
/// - All methods are called on the main actor.
/// - `isReady` reflects the engine's current ability to handle a `polish` call
///   *right now*. Implementations may flip this any time (e.g. local model file
///   downloaded, Apple Intelligence toggled in System Settings) and should post
///   `.polishAvailabilityChanged` so the UI re-renders.
/// - `polish` may take seconds. The coordinator wraps each call in a hard
///   timeout and falls back to the raw transcript on any throw.
@MainActor
protocol PolishService: AnyObject {
    var backend: PolishBackend { get }
    var isReady: Bool { get }
    /// Localized status string shown under the radio in Settings.
    var statusText: String { get }
    /// Re-query environment for current readiness (e.g. macOS toggled Apple
    /// Intelligence in System Settings). Default impl is a no-op for backends
    /// whose readiness can't change at runtime.
    func refreshAvailability()
    /// Pre-load weights / open a session. May throw on hard unavailability
    /// (device not eligible, model file missing). Calling it again after
    /// success is a no-op.
    func warmUp() async throws
    /// Run inference. The caller (PolishCoordinator) is responsible for:
    /// (a) resolving `systemPrompt` via `PolishPrompt.resolvedSystemPrompt`,
    ///     and
    /// (b) wrapping this call in the 3 s timeout + breaker.
    /// Backends are pure plumbing — they take a fully-formed system prompt
    /// and a raw user message, do inference, return the polished string.
    func polish(_ raw: String, systemPrompt: String) async throws -> String

    // Backend-specific lifecycle hooks. **Must be declared as protocol
    // requirements** (not just extension defaults) — otherwise calls through
    // a protocol-typed reference dispatch statically to the extension's
    // no-op, never reaching the conforming type's override. That bug was
    // shipped in v0.3.0 and silently broke the Local backend's Download
    // button.
    func startDownload(mirrorPreference: ModelMirrorPreference, localeCode: String)
    func cancelDownload()
    func purgeModel()
}

extension PolishService {
    func refreshAvailability() { /* no-op default */ }

    /// No-op defaults so backends that don't manage downloadable assets
    /// (e.g. SystemPolishService) don't have to repeat empty stubs.
    func startDownload(mirrorPreference: ModelMirrorPreference, localeCode: String) {}
    func cancelDownload() {}
    func purgeModel() {}
}

enum PolishBackend: String {
    case system
    case local
}

extension Notification.Name {
    static let polishAvailabilityChanged = Notification.Name("polishAvailabilityChanged")
}
