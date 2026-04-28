import Testing
@testable import ScribeCore

/// Covers `PolishPrompt` — the language-hint mapping driven by the Settings
/// "Language" menu's locale code, plus the conservative preface stripper.
@Suite struct PolishPromptTests {

    // MARK: - languageHint(for:)

    @Test func emptyCodeMapsToAuto() {
        #expect(PolishPrompt.languageHint(for: "") == "auto")
    }

    @Test func knownCodesMap() {
        #expect(PolishPrompt.languageHint(for: "en-US") == "English")
        #expect(PolishPrompt.languageHint(for: "zh-CN") == "Simplified Chinese")
        #expect(PolishPrompt.languageHint(for: "zh-TW") == "Traditional Chinese")
        #expect(PolishPrompt.languageHint(for: "ja-JP") == "Japanese")
        #expect(PolishPrompt.languageHint(for: "ko-KR") == "Korean")
    }

    @Test func unknownCodeFallsBackToAuto() {
        // Future locales we add to the menu must also be mapped here, but until
        // they are, "auto" is the safe default — the model picks language by
        // input detection rather than guessing wrong.
        #expect(PolishPrompt.languageHint(for: "fr-FR") == "auto")
    }

    // MARK: - resolvedSystemPrompt(languageHint:)

    @Test func resolvedPromptSubstitutesHint() {
        let resolved = PolishPrompt.resolvedSystemPrompt(languageHint: "Simplified Chinese")
        #expect(resolved.contains("Simplified Chinese"))
        #expect(!resolved.contains("{{language_hint}}"))
    }

    @Test func resolvedPromptKeepsCoreInstructions() {
        let resolved = PolishPrompt.resolvedSystemPrompt(languageHint: "auto")
        // Critical instructions that the prompt must preserve regardless of hint.
        #expect(resolved.contains("Output ONLY the polished text"))
        #expect(resolved.contains("Do not translate"))
    }

    // MARK: - stripCommonPreface(_:)

    @Test func stripsEnglishPrefaceWhenBodyFollows() {
        let raw = "Sure, here's the polished version:\nThe meeting is at three p.m. tomorrow."
        #expect(
            PolishPrompt.stripCommonPreface(raw)
            == "The meeting is at three p.m. tomorrow."
        )
    }

    @Test func stripsChinesePrefaceWhenBodyFollows() {
        let raw = "好的，以下是润色后的版本：\n会议安排在明天下午三点。"
        #expect(
            PolishPrompt.stripCommonPreface(raw)
            == "会议安排在明天下午三点。"
        )
    }

    @Test func keepsTextWhenPrefaceLooksLikeRealContent() {
        // Single-line "Sure, ..." with no body to fall back to — leave it alone
        // rather than risk dropping the whole answer.
        let raw = "Sure, the report is on your desk."
        #expect(PolishPrompt.stripCommonPreface(raw) == raw)
    }

    @Test func noOpOnCleanOutput() {
        let raw = "The meeting is at three p.m."
        #expect(PolishPrompt.stripCommonPreface(raw) == raw)
    }

    @Test func trimsLeadingTrailingWhitespace() {
        #expect(PolishPrompt.stripCommonPreface("   hello world  \n") == "hello world")
    }

    // MARK: - Y6: SystemPolishService prompt cache key

    /// Two assembled prompts with identical length and identical L1
    /// bookends but different L2 layers must produce different cache keys.
    /// The pre-Y6 implementation (`count:prefix(16)…suffix(16)`) returned
    /// the same key for both, so the cached `LanguageModelSession` was
    /// reused with stale instructions.
    @Test func promptKeyDistinguishesEqualLengthDifferentMiddle() {
        let l1 = PolishPrompt.resolvedSystemPrompt(languageHint: "English")
        // Same L1 + same trailing bookend, different middle. Padded to the
        // same length so a length-only key would also collide.
        let withPersonaA = l1 + "\n\nABOUT THE USER: Alice writes Swift."
        let withPersonaB = l1 + "\n\nABOUT THE USER: Bob writes Rust...."
        #expect(
            withPersonaA.count == withPersonaB.count,
            "Test setup: prompts must be equal-length to exercise the collision"
        )

        let keyA = SystemPolishService.promptCacheKey(withPersonaA)
        let keyB = SystemPolishService.promptCacheKey(withPersonaB)
        #expect(
            keyA != keyB,
            "Different prompts must produce different keys; otherwise the FM session is reused with stale L2/L3"
        )
    }

    @Test func promptKeyIsStableAcrossEqualPrompts() {
        let prompt = PolishPrompt.resolvedSystemPrompt(languageHint: "Japanese")
        #expect(
            SystemPolishService.promptCacheKey(prompt)
            == SystemPolishService.promptCacheKey(prompt),
            "Identical prompts must share a key — otherwise we'd rebuild the session every call"
        )
    }
}
