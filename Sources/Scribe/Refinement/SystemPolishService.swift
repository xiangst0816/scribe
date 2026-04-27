import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Polishes via Apple's built-in `SystemLanguageModel`. Only does anything on
/// macOS 26.0+; on older systems the type still exists but reports
/// `isReady == false` permanently and `polish` throws.
///
/// "Eligibility" depends on three things outside our control: macOS version,
/// device hardware/region (Apple Intelligence availability), and whether the
/// user has enabled Apple Intelligence in System Settings. Only the first is
/// checked at compile time; the latter two are queried at runtime.
@MainActor
final class SystemPolishService: PolishService {
    let backend: PolishBackend = .system

    private(set) var isReady: Bool = false
    private(set) var statusText: String = ""

#if canImport(FoundationModels)
    private var session: Any?  // type-erased LanguageModelSession (gated)
    private var sessionPromptKey: String?  // hash of the system prompt the session was built with
#endif

    init() {
        refreshAvailability()
    }

    /// Re-query the OS for current availability. Cheap — meant to be called
    /// from `applicationDidBecomeActive` so flipping the system toggle is
    /// reflected without a relaunch.
    func refreshAvailability() {
        if #available(macOS 26.0, *) {
#if canImport(FoundationModels)
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                isReady = true
                statusText = L10n.t("polish.system.statusAvailable")
            case .unavailable(let reason):
                isReady = false
                statusText = Self.describeUnavailable(reason)
            }
#else
            isReady = false
            statusText = L10n.t("polish.system.statusRequiresMacOS26")
#endif
        } else {
            isReady = false
            statusText = L10n.t("polish.system.statusRequiresMacOS26")
        }
        NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
    }

    func warmUp() async throws {
        if #available(macOS 26.0, *) {
#if canImport(FoundationModels)
            guard SystemLanguageModel.default.availability == .available else {
                throw PolishError.unavailable(statusText)
            }
            // Build a session with a baseline (L1-only) prompt so the first
            // real polish is fast. The coordinator may pass a richer prompt
            // including L2/L3 at call time, in which case we rebuild.
            buildSession(systemPrompt: PolishPrompt.resolvedSystemPrompt(languageHint: "auto"))
            return
#endif
        }
        throw PolishError.unavailable(L10n.t("polish.system.statusRequiresMacOS26"))
    }

    func polish(_ raw: String, systemPrompt: String) async throws -> String {
        if #available(macOS 26.0, *) {
#if canImport(FoundationModels)
            // Rebuild the session whenever the prompt content changes — Apple FM
            // bakes instructions into the session at construction. A coarse
            // identity check (length + first/last chars) avoids hashing the
            // prompt on every call.
            let key = "\(systemPrompt.count):\(systemPrompt.prefix(16))…\(systemPrompt.suffix(16))"
            if sessionPromptKey != key || !(session is LanguageModelSession) {
                buildSession(systemPrompt: systemPrompt)
                sessionPromptKey = key
            }
            guard let s = session as? LanguageModelSession else {
                throw PolishError.unavailable(statusText)
            }
            let opts = GenerationOptions(temperature: 0.25, maximumResponseTokens: 1024)
            let response = try await s.respond(to: raw, options: opts)
            return PolishPrompt.stripCommonPreface(response.content)
#endif
        }
        throw PolishError.unavailable(L10n.t("polish.system.statusRequiresMacOS26"))
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func buildSession(systemPrompt: String) {
        let s = LanguageModelSession(instructions: systemPrompt)
        s.prewarm()
        self.session = s
    }
#endif

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func describeUnavailable(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return L10n.t("polish.system.statusDeviceNotEligible")
        case .appleIntelligenceNotEnabled:
            return L10n.t("polish.system.statusNotEnabled")
        case .modelNotReady:
            return L10n.t("polish.system.statusModelNotReady")
        @unknown default:
            return L10n.t("polish.system.statusUnavailable")
        }
    }
#endif
}

enum PolishError: LocalizedError {
    case unavailable(String)
    case timeout
    case emptyOutput
    case lengthExploded

    var errorDescription: String? {
        switch self {
        case .unavailable(let s): return s
        case .timeout:            return "Polish timed out"
        case .emptyOutput:        return "Polish returned empty output"
        case .lengthExploded:     return "Polish output exceeded length budget"
        }
    }
}
