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
    /// Run inference. Caller is responsible for timeout enforcement.
    func polish(_ raw: String, languageHint: String) async throws -> String
}

extension PolishService {
    func refreshAvailability() { /* no-op default */ }

    /// Backend-specific lifecycle hooks. Defaulted to no-ops so the coordinator
    /// can call them on any backend; only `LocalPolishService` actually
    /// implements them today.
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
