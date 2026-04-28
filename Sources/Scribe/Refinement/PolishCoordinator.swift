import Foundation

/// Single entry-point for the polishing feature. Owns the two backend services
/// (System / Local), arbitrates which one is active based on user preference
/// in Settings, enforces the 3-second hard timeout, and trips a circuit
/// breaker after 3 consecutive failures.
///
/// The arbitration is **explicit** — `selectedBackend` decides which service
/// gets called. There is no automatic fallback from one backend to the other:
/// the Settings UI is what users use to pick.
@MainActor
final class PolishCoordinator {
    @MainActor static let shared = PolishCoordinator()

    /// Protocol-typed so tests can swap in stubs. In production these point at
    /// the concrete `SystemPolishService` / `LocalPolishService`.
    var system: PolishService
    var local: PolishService

    private let defaults: UserDefaults

    /// Hard timeout per polish call. Anything slower than this gets cancelled
    /// and the raw transcript is pasted instead — better to lose polish than
    /// to lose the recording.
    ///
    /// Bumped from 3.0 → 5.0 in v0.4.1 because Gemma 4 E2B on slower Apple
    /// Silicon (M2 Air, 8 GB) lands at 2–3 s per polish, occasionally clipping
    /// 3 s and tripping the breaker. M4 Max stays well under 1 s, so this is
    /// just slack for the bottom of the supported range.
    static let timeoutSeconds: TimeInterval = 5.0

    /// After this many consecutive failures, master toggle auto-disables and
    /// the user is notified. Prevents a broken model from quietly eating every
    /// recording.
    static let breakerThreshold = 3

    // MARK: - Persistence

    private static let kEnabled  = "polish.enabled"
    private static let kBackend  = "polish.backend"
    private static let kMirror   = "polish.local.mirror"
    private static let kAdaptive = "polish.adaptive.enabled"

    /// Adaptive (Phase 5.1): when on, the assembled system prompt includes
    /// L2 (persona) + L3 (recent finished writing) on every polish call, and
    /// every successfully-pasted text gets appended to L3 history. Default
    /// off — until the user opts in, no transcript text gets persisted.
    var isAdaptiveEnabled: Bool {
        get { defaults.bool(forKey: Self.kAdaptive) }
        set {
            defaults.set(newValue, forKey: Self.kAdaptive)
            NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
        }
    }

    let personaStore: PersonaStore

    /// Mirror preference for the Local backend's download. Default is `.auto`,
    /// which the downloader resolves against the user's current dictation locale.
    var mirrorPreference: ModelMirrorPreference {
        get {
            let raw = defaults.string(forKey: Self.kMirror) ?? ""
            return ModelMirrorPreference(rawValue: raw) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.kMirror)
            NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
        }
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.kEnabled) }
        set {
            defaults.set(newValue, forKey: Self.kEnabled)
            if newValue {
                resetCircuitBreaker()
                prewarmIfNeeded()
            }
            NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
        }
    }

    var selectedBackend: PolishBackend {
        get {
            let raw = defaults.string(forKey: Self.kBackend) ?? ""
            return PolishBackend(rawValue: raw) ?? defaultBackend()
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.kBackend)
            resetCircuitBreaker()
            prewarmIfNeeded()
            NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
        }
    }

    // MARK: - Circuit breaker state

    private(set) var consecutiveFailures: Int = 0
    private(set) var lastFailureMessage: String?

    /// Set when the breaker has tripped, until the user re-enables polish.
    private(set) var isBreakerTripped: Bool = false

    /// **Tracked separately from `consecutiveFailures`** (R4): timeouts are
    /// performance signals, not engine-broke signals — they don't trip the
    /// breaker, because slow Apple Silicon would otherwise auto-disable
    /// polish mid-session every time the model happens to clip the budget.
    /// But the user still needs to know polish silently fell back to raw,
    /// so the menu surfaces the most recent timeout via this flag (cleared
    /// on the next successful polish). See `AppDelegate.refreshPolishMenuItem`
    /// for the menu-bar wiring; the `lastCallTimedOut` branch must be
    /// checked **before** the `active()` ready branch — otherwise as long
    /// as the backend is still ready (it always is after a timeout, since
    /// timeouts don't trip the breaker), the ready label shadows this and
    /// the timeout signal never reaches the user.
    private(set) var consecutiveTimeouts: Int = 0
    private(set) var lastCallTimedOut: Bool = false

    /// Fired when consecutive failures hit `breakerThreshold` — UI / status bar
    /// should react (notify the user, flip the master toggle off).
    var onBreakerTripped: ((String) -> Void)?

    // MARK: - Init

    init(
        system: PolishService? = nil,
        local: PolishService? = nil,
        defaults: UserDefaults = .standard,
        personaStore: PersonaStore? = nil
    ) {
        self.system = system ?? SystemPolishService()
        self.local  = local  ?? LocalPolishService()
        self.defaults = defaults
        self.personaStore = personaStore ?? PersonaStore.shared
    }

    /// Test-only convenience to keep the call sites in tests readable.
    convenience init(testDefaults: UserDefaults) {
        self.init(defaults: testDefaults)
    }

    /// Test-only setter so tests can replace one of the backends after
    /// construction. Production code never calls this — use init injection.
    func injectStubService(_ service: PolishService, as backend: PolishBackend) {
        switch backend {
        case .system: self.system = service
        case .local:  self.local  = service
        }
    }

    /// Convenience for early-startup wiring. Asks each service to refresh its
    /// read of the environment (e.g. macOS toggling Apple Intelligence in
    /// System Settings), so Settings reflects current truth without a relaunch.
    func refreshAvailability() {
        system.refreshAvailability()
        local.refreshAvailability()
    }

    /// Fire-and-forget warm-up of the active backend so the user's first polish
    /// call doesn't have to absorb model-load latency under the 3 s timeout.
    /// Idempotent — `warmUp()` is a no-op once the backend is loaded.
    func prewarmIfNeeded() {
        guard let svc = active() else { return }
        Task { @MainActor in
            try? await svc.warmUp()
        }
    }

    /// Convenience for the Settings UI: kick off the Local backend's download
    /// using the current mirror preference + dictation locale (the locale tells
    /// the downloader which mirror to try first when preference is `.auto`).
    func startLocalDownload() {
        let locale = defaults.string(forKey: "selectedLocaleCode") ?? ""
        local.startDownload(mirrorPreference: mirrorPreference, localeCode: locale)
    }

    func cancelLocalDownload() {
        local.cancelDownload()
    }

    func purgeLocalModel() {
        local.purgeModel()
    }

    /// Default backend pick at first launch: System if it can possibly run on
    /// this machine, otherwise Local.
    private func defaultBackend() -> PolishBackend {
        system.isReady ? .system : .local
    }

    // MARK: - Routing

    /// The service that *would* run if `polish` were called right now.
    /// `nil` means "no polish — paste raw" for any reason: master toggle off,
    /// breaker tripped, selected backend not ready.
    func active() -> PolishService? {
        guard isEnabled, !isBreakerTripped else { return nil }
        switch selectedBackend {
        case .system: return system.isReady ? system : nil
        case .local:  return local.isReady ? local : nil
        }
    }

    // MARK: - Inference

    /// Try to polish `raw`. On any failure (timeout, throw, empty output,
    /// length explosion, breaker tripped, no active backend) returns `raw`
    /// unchanged so the caller can paste *something*. The caller doesn't need
    /// any error handling.
    ///
    /// The assembled system prompt includes L2 (persona) + L3 (recent
    /// finished writing) when adaptive mode is on, plus the L1 fixed prompt.
    /// After the call, the resulting *final* text — polished if successful,
    /// raw on fallback — is appended to L3 history (also gated by adaptive
    /// mode).
    func maybePolish(_ raw: String, selectedLocaleCode: String) async -> String {
        guard let svc = active() else {
            captureFinalIfAdaptive(raw, locale: selectedLocaleCode)
            return raw
        }

        let hint = PolishPrompt.languageHint(for: selectedLocaleCode)
        let systemPrompt: String
        if isAdaptiveEnabled {
            systemPrompt = PolishPrompt.assemble(
                languageHint: hint,
                runtimeContext: nil,                      // Phase 5.3 placeholder
                persona: personaStore.persona,
                recent: personaStore.recent
            )
        } else {
            systemPrompt = PolishPrompt.resolvedSystemPrompt(languageHint: hint)
        }

        let final: String
        do {
            let polished = try await withTimeout(seconds: Self.timeoutSeconds) {
                try await svc.polish(raw, systemPrompt: systemPrompt)
            }
            try validate(polished, against: raw)
            recordSuccess()
            final = polished
        } catch PolishError.timeout {
            // Timeout is a transient performance signal, not a hard failure.
            // Quietly fall back to the raw transcript and DO NOT increment
            // the breaker — otherwise users on slower Apple Silicon get
            // their polish auto-disabled mid-session every time the model
            // happens to clip the budget. Real failures (load error, bad
            // output) still trip the breaker via the catch-all below.
            NSLog("Scribe polish timeout (>%.1fs); pasting raw", Self.timeoutSeconds)
            recordTimeout()
            final = raw
        } catch {
            recordFailure(error.localizedDescription)
            final = raw
        }
        captureFinalIfAdaptive(final, locale: selectedLocaleCode)
        return final
    }

    /// Append the just-pasted final text to L3 history. No-op if adaptive
    /// mode is off — that's the privacy gate. The user opted into Polish but
    /// not into having Scribe remember anything.
    private func captureFinalIfAdaptive(_ text: String, locale: String) {
        guard isAdaptiveEnabled else { return }
        personaStore.recordFinalText(text, languageCode: locale)
    }

    /// Reject empty / nonsense / runaway outputs — fall back to raw. Length
    /// budget is `2× input` per design doc §3.4.
    private func validate(_ polished: String, against raw: String) throws {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw PolishError.emptyOutput }
        if trimmed.count > max(64, raw.count * 2) {
            throw PolishError.lengthExploded
        }
    }

    // MARK: - Circuit breaker

    private func recordSuccess() {
        consecutiveFailures = 0
        lastFailureMessage = nil
        // Cleared on every success: a single OK polish is enough to drop
        // the menu out of the "Skipped (timed out)" state. If the next call
        // also times out, it'll re-arm.
        consecutiveTimeouts = 0
        lastCallTimedOut = false
    }

    private func recordFailure(_ message: String) {
        consecutiveFailures += 1
        lastFailureMessage = message
        // A hard failure also resolves the timeout signal — `lastCallTimedOut`
        // is "the *most recent* call timed out", so a subsequent failure
        // takes precedence in the menu (failure → ".skipped"; failure on the
        // 3rd consecutive call trips the breaker, which dominates).
        lastCallTimedOut = false
        NSLog("Scribe polish failure (%d/%d): %@",
              consecutiveFailures, Self.breakerThreshold, message)
        if consecutiveFailures >= Self.breakerThreshold {
            tripBreaker(message)
        }
        NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
    }

    private func recordTimeout() {
        consecutiveTimeouts += 1
        lastCallTimedOut = true
        NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
    }

    private func tripBreaker(_ message: String) {
        isBreakerTripped = true
        isEnabled = false  // master switch off; user must explicitly re-enable
        onBreakerTripped?(message)
    }

    func resetCircuitBreaker() {
        consecutiveFailures = 0
        lastFailureMessage = nil
        consecutiveTimeouts = 0
        lastCallTimedOut = false
        isBreakerTripped = false
    }

    // MARK: - Old-key cleanup

    /// Removes UserDefaults keys from the deprecated remote-LLM path. Safe to
    /// call on every launch — `removeObject(forKey:)` is a no-op if missing.
    static func purgeLegacyKeys(in defaults: UserDefaults = .standard) {
        let oldKeys = ["llmEnabled", "llmAPIBaseURL", "llmAPIKey", "llmModel"]
        for k in oldKeys { defaults.removeObject(forKey: k) }
    }
}

// MARK: - Timeout helper

/// Race the work against a sleep; whichever finishes first wins, the other
/// gets cancelled. `Task.sleep` cancellation propagates immediately, so the
/// loser doesn't hang around.
@MainActor
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PolishError.timeout
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else {
            throw PolishError.timeout
        }
        return first
    }
}
