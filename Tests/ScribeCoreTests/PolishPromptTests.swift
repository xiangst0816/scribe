import XCTest
@testable import ScribeCore

/// Covers `PolishPrompt` — the language-hint mapping driven by the Settings
/// "Language" menu's locale code, plus the conservative preface stripper.
final class PolishPromptTests: XCTestCase {

    // MARK: - languageHint(for:)

    func testEmptyCodeMapsToAuto() {
        XCTAssertEqual(PolishPrompt.languageHint(for: ""), "auto")
    }

    func testKnownCodesMap() {
        XCTAssertEqual(PolishPrompt.languageHint(for: "en-US"), "English")
        XCTAssertEqual(PolishPrompt.languageHint(for: "zh-CN"), "Simplified Chinese")
        XCTAssertEqual(PolishPrompt.languageHint(for: "zh-TW"), "Traditional Chinese")
        XCTAssertEqual(PolishPrompt.languageHint(for: "ja-JP"), "Japanese")
        XCTAssertEqual(PolishPrompt.languageHint(for: "ko-KR"), "Korean")
    }

    func testUnknownCodeFallsBackToAuto() {
        // Future locales we add to the menu must also be mapped here, but until
        // they are, "auto" is the safe default — the model picks language by
        // input detection rather than guessing wrong.
        XCTAssertEqual(PolishPrompt.languageHint(for: "fr-FR"), "auto")
    }

    // MARK: - resolvedSystemPrompt(languageHint:)

    func testResolvedPromptSubstitutesHint() {
        let resolved = PolishPrompt.resolvedSystemPrompt(languageHint: "Simplified Chinese")
        XCTAssertTrue(resolved.contains("Simplified Chinese"))
        XCTAssertFalse(resolved.contains("{{language_hint}}"))
    }

    func testResolvedPromptKeepsCoreInstructions() {
        let resolved = PolishPrompt.resolvedSystemPrompt(languageHint: "auto")
        // Critical instructions that the prompt must preserve regardless of hint.
        XCTAssertTrue(resolved.contains("Output ONLY the polished text"))
        XCTAssertTrue(resolved.contains("Do not translate"))
    }

    // MARK: - stripCommonPreface(_:)

    func testStripsEnglishPrefaceWhenBodyFollows() {
        let raw = "Sure, here's the polished version:\nThe meeting is at three p.m. tomorrow."
        XCTAssertEqual(
            PolishPrompt.stripCommonPreface(raw),
            "The meeting is at three p.m. tomorrow."
        )
    }

    func testStripsChinesePrefaceWhenBodyFollows() {
        let raw = "好的，以下是润色后的版本：\n会议安排在明天下午三点。"
        XCTAssertEqual(
            PolishPrompt.stripCommonPreface(raw),
            "会议安排在明天下午三点。"
        )
    }

    func testKeepsTextWhenPrefaceLooksLikeRealContent() {
        // Single-line "Sure, ..." with no body to fall back to — leave it alone
        // rather than risk dropping the whole answer.
        let raw = "Sure, the report is on your desk."
        XCTAssertEqual(PolishPrompt.stripCommonPreface(raw), raw)
    }

    func testNoOpOnCleanOutput() {
        let raw = "The meeting is at three p.m."
        XCTAssertEqual(PolishPrompt.stripCommonPreface(raw), raw)
    }

    func testTrimsLeadingTrailingWhitespace() {
        XCTAssertEqual(PolishPrompt.stripCommonPreface("   hello world  \n"), "hello world")
    }
}
