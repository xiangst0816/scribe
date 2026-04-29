import Foundation

/// Local-only public façade so `Tools/PolishEval` can drive the local
/// polish backend without `@testable import`.
public enum PolishEvalAPI {
    @MainActor
    public static func runOnce(
        raw: String,
        languageHint: String
    ) async throws -> String {
        let svc = Self.shared
        try await svc.warmUp()
        let prompt = PolishPrompt.resolvedSystemPrompt(languageHint: languageHint)
        return try await svc.polish(raw, systemPrompt: prompt)
    }

    @MainActor
    public static var statusText: String {
        Self.shared.statusText
    }

    @MainActor
    public static var isReady: Bool {
        Self.shared.isReady
    }

    /// Mirror of `AppDelegate.applicationWillTerminate`'s shutdown sequence.
    /// Without this, `exit()` on the eval CLI lets ggml's C++ static
    /// destructor for the metal-device vector race the still-loaded backend
    /// and SIGABRTs — same crash family the v0.3.3 `tearDownProcessBackend`
    /// mechanism was created to prevent.
    @MainActor
    public static func tearDown() {
        Self.shared.releaseContextForShutdown()
        LlamaContext.tearDownProcessBackend()
    }

    @MainActor
    private static let shared = LocalPolishService()
}
