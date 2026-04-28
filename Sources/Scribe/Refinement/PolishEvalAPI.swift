import Foundation

/// Local-only public façade so `Tools/PolishEval` can drive the local
/// polish backend without `@testable import`. Delete this file (and the
/// `PolishEval` exec target) when prompt evaluation is finished.
public enum PolishEvalAPI {
    @MainActor
    public static func runOnce(
        raw: String,
        languageHint: String
    ) async throws -> String {
        let svc = Self.shared
        try await svc.warmUp()
        let prompt = PolishPrompt.assemble(
            languageHint: languageHint,
            runtimeContext: nil,
            persona: "",
            recent: []
        )
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

    @MainActor
    private static let shared = LocalPolishService()
}
