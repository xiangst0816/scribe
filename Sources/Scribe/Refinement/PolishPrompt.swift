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

        Your job is to infer what the speaker actually meant to say and write
        it down cleanly. Use context to resolve ambiguity rather than
        translating ambiguity into the output.

        Rules:
        - Rewrite the raw text into clean, complete, well-formed sentences.
        - Preserve the speaker's meaning, intent, vocabulary, register, and
          tone — casual stays casual, formal stays formal, technical terms
          stay technical.
        - Remove fillers ("um", "uh", "you know", "like", "嗯", "那个", "啊",
          "あのー", "어").
        - Collapse repeated words and phrases ("the the meeting" → "the
          meeting"; "我我觉得" → "我觉得").
        - Resolve self-corrections — when the speaker corrects themselves
          mid-sentence ("Tuesday, actually no wait, Wednesday"), keep only
          the final intended message.
        - Keep proper nouns, code identifiers, numbers, currency, units, and
          quoted strings exactly as written.
        - Do not add information that was not said.
        - Do not editorialize, summarize, expand, or shorten beyond removing
          disfluencies.
        - Do not translate. Keep the speaker's language exactly as dictated:
          never render "系统提示词" as "system prompt", "API" as "应用程序
          接口", or "メニューバー" as "menu bar".

        Output language rules:
        - The user's selected dictation language is: {{language_hint}}
        - If {{language_hint}} is "auto", detect the language of the raw
          text and output in that same language.
        - Otherwise, output in {{language_hint}}, regardless of any stray
          words in other languages in the raw text.

        Examples (illustrative — match the actual input's language; do not
        translate examples to your output language):

        raw:  uh so I I think we should um maybe ship the the feature on Tuesday I guess
        out:  I think we should ship the feature on Tuesday.

        raw:  the meeting is on Tuesday actually no wait Wednesday at 3pm
        out:  The meeting is on Wednesday at 3pm.

        raw:  yeah totally I'm down let's grab coffee tomorrow um around 10 maybe
        out:  Yeah totally — I'm down, let's grab coffee tomorrow around 10.

        raw:  嗯那个我觉得我们应该应该把这个那个 feature 在周二上线吧
        out:  我觉得我们应该把这个 feature 在周二上线。

        raw:  明天下午三点开会哦不对应该是四点然后会议室是 B201
        out:  明天下午四点开会，会议室是 B201。

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

    /// Substitute `{{language_hint}}` into the system prompt. Returns just
    /// the L1 (fixed) prompt — no persona / recent layers. Useful for tests
    /// and as a backstop when the adaptive feature is off.
    static func resolvedSystemPrompt(languageHint: String) -> String {
        system.replacingOccurrences(of: "{{language_hint}}", with: languageHint)
    }

    /// Assemble the full system prompt from all available layers. Layers
    /// follow the L1 / R / L2 / L3 design in [docs/adaptive-polish.md].
    /// Empty `persona` / `recent` cause the corresponding layers to be
    /// elided entirely so we don't show "About the user: <empty>" to the
    /// model.
    ///
    /// `runtimeContext` is the placeholder for Phase 5.3's per-app tone;
    /// pass `nil` (or empty) until then.
    static func assemble(
        languageHint: String,
        runtimeContext: String? = nil,
        persona: String = "",
        recent: [PersonaStore.Entry] = []
    ) -> String {
        var blocks: [String] = []

        // L1 — fixed core.
        blocks.append(resolvedSystemPrompt(languageHint: languageHint))

        // R — runtime context (Phase 5.3 placeholder; usually empty).
        if let runtimeContext, !runtimeContext.isEmpty {
            blocks.append("Current context: " + runtimeContext)
        }

        // L2 — who the user is.
        let trimmedPersona = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPersona.isEmpty {
            blocks.append("About the user (who they are):\n" + trimmedPersona)
        }

        // L3 — most recent final outputs as context examples.
        if !recent.isEmpty {
            let bulletList = recent.map { "- \"\($0.text)\"" }.joined(separator: "\n")
            blocks.append("User's recent finished writing (for reference, not to copy):\n" + bulletList)
        }

        return blocks.joined(separator: "\n\n")
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
