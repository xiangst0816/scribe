import Foundation

/// System prompt + language-hint mapping shared by every backend. Two engines
/// (System / Local) producing visibly different wording for the same input
/// would surprise the user when they switch backends — keep this single-source.
enum PolishPrompt {
    static let system = """
        You are a transcript polisher. The user dictated speech; an automatic
        speech recognizer produced the raw text below. Raw transcripts often
        contain filler words, false starts, repetitions, run-on sentences, and
        informal disfluencies typical of spoken language.

        Your job:
        - Rewrite the raw text into clean, complete, well-formed sentences.
        - Preserve the speaker's original meaning, intent, terminology, and tone.
        - Keep proper nouns, code identifiers, numbers, and quoted strings exactly as written.
        - Do not add information that was not said.
        - Do not editorialize, summarize, or shorten beyond removing disfluencies.
        - Do not translate.

        Output language rules:
        - The user's selected dictation language is: {{language_hint}}
        - If {{language_hint}} is "auto", detect the language of the raw text and
          output in that same language.
        - Otherwise, output in {{language_hint}}, regardless of any stray words
          in other languages in the raw text.

        Output ONLY the polished text. No preface, no quotes, no commentary,
        no markdown.
        """

    /// Maps the user-selected dictation locale code to a `language_hint` token
    /// that gets substituted into the system prompt. Empty string ⇒ "auto"
    /// (System Default in the menu) so the model picks language by detection.
    static func languageHint(for selectedLocaleCode: String) -> String {
        switch selectedLocaleCode {
        case "":       return "auto"
        case "en-US":  return "English"
        case "zh-CN":  return "Simplified Chinese"
        case "zh-TW":  return "Traditional Chinese"
        case "ja-JP":  return "Japanese"
        case "ko-KR":  return "Korean"
        default:       return "auto"
        }
    }

    /// Substitute `{{language_hint}}` into the system prompt. Returns the final
    /// prompt to feed to the engine.
    static func resolvedSystemPrompt(languageHint: String) -> String {
        system.replacingOccurrences(of: "{{language_hint}}", with: languageHint)
    }

    /// Looks like the engine prepended a verbose preface ("Sure, here's the
    /// polished version: …") and the actual content is on a later line. Local
    /// small models do this occasionally even with a clear prompt. Keep the
    /// stripping conservative — never alter content that *might* be the answer.
    static func stripCommonPreface(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefacePatterns = [
            "Sure, here",
            "Sure! Here",
            "Here is the polished",
            "Here's the polished",
            "Polished text:",
            "好的，",
            "以下是",
            "润色后",
        ]
        let lower = trimmed.prefix(40).lowercased()
        for p in prefacePatterns where lower.contains(p.lowercased()) {
            // Only strip if there is a clear newline-separated body to fall
            // back to; otherwise leave the text alone — better to paste the
            // preface than to nuke real content.
            if let nl = trimmed.firstIndex(where: { $0.isNewline }) {
                let after = trimmed[trimmed.index(after: nl)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !after.isEmpty { return after }
            }
            return trimmed
        }
        return trimmed
    }
}
