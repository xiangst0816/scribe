import AVFoundation
import Foundation
import WhisperKit

final class WhisperSpeechProvider: SpeechProvider {
    /// Conditioning prompt fed to the Whisper decoder. Biases recognition toward
    /// common English tech terms that get mangled in 中英 mixed speech
    /// (e.g. "GitHub" → "get up" / "gtihub"). Whisper prompts cap at ~224 tokens.
    static let initialPrompt = """
    GitHub, GitLab, VSCode, Cursor, Claude, ChatGPT, OpenAI, Anthropic, \
    TypeScript, JavaScript, Python, Swift, Rust, Golang, Node.js, npm, pnpm, \
    React, Vue, Astro, Next.js, Tailwind, Vite, Webpack, \
    macOS, iOS, Linux, Docker, Kubernetes, AWS, Cloudflare, Vercel, \
    API, SDK, CLI, JSON, YAML, HTTP, OAuth, JWT, gRPC, \
    Whisper, CoreML, MLX, LLM, prompt, token, embedding, \
    PR, commit, merge, rebase, diff, repo, branch.
    """

    var onAudioLevel: ((Float) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    /// ISO-639-1 language code (e.g. "zh", "en"). nil = auto-detect.
    var languageHint: String?

    var isReady: Bool { ModelManager.shared.loadedKit != nil }

    private var audioProcessor: AudioProcessor?
    private var levelTimer: Timer?
    private var isRecording = false

    func start() {
        guard let _ = ModelManager.shared.loadedKit else {
            onError?("Voice model is not loaded yet.")
            return
        }

        let processor = AudioProcessor()
        audioProcessor = processor
        isRecording = true

        do {
            try processor.startRecordingLive(inputDeviceID: nil) { [weak self] _ in
                // Buffer is appended internally; we just need to keep recording alive.
                _ = self
            }
        } catch {
            onError?("Microphone failed: \(error.localizedDescription)")
            audioProcessor = nil
            isRecording = false
            return
        }

        // Drive the waveform from `relativeEnergy` updates.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let processor = self.audioProcessor else { return }
            let level = processor.relativeEnergy.last ?? 0
            self.onAudioLevel?(level)
        }
    }

    func stop() {
        guard isRecording, let processor = audioProcessor else { return }
        isRecording = false

        levelTimer?.invalidate()
        levelTimer = nil
        processor.stopRecording()

        let samples = Array(processor.audioSamples)
        audioProcessor = nil

        guard !samples.isEmpty else {
            onFinalResult?("")
            return
        }

        Task {
            await transcribe(samples: samples)
        }
    }

    func cancel() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioProcessor?.stopRecording()
        audioProcessor = nil
        isRecording = false
    }

    // MARK: - Private

    /// Drop a segment if its `noSpeechProb` is at or above this. Whisper hallucinates
    /// canned phrases ("Thank you.", "감사합니다.") on near-silent input even when the
    /// VAD pre-filter lets the clip through; this catches those per-segment.
    private static let noSpeechProbCutoff: Float = 0.6

    private func transcribe(samples: [Float]) async {
        guard let kit = ModelManager.shared.loadedKit else {
            await deliver(error: "Voice model is not loaded.")
            return
        }

        // VAD pre-filter: if the whole buffer has no detectable speech, skip the
        // model entirely. Whisper otherwise hallucinates training-set boilerplate
        // like "Thank you for watching" / "3Q" on silent or breath-only input.
        let speechRanges = EnergyVAD().calculateActiveChunks(in: samples)
        if speechRanges.isEmpty {
            NSLog("Scribe transcribe: VAD found no speech in %d samples, skipping", samples.count)
            await deliver(text: "")
            return
        }

        do {
            // large-v3 trips its no-speech / first-token-logprob filters on
            // short utterances and returns an empty transcript even when the
            // smaller models hear the same audio fine. Loosen the gates so
            // any model produces text and we filter hallucinations downstream.
            // The custom tech-term prompt also seems to push large-v3 toward
            // "no speech" — only attach it for the smaller variants where
            // it actually helps with English jargon recognition.
            let isLarge = ModelManager.shared.loadedQuality == .high
            let promptTokens = isLarge
                ? nil
                : kit.tokenizer?.encode(text: " " + Self.initialPrompt)

            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: languageHint,
                temperature: 0,
                topK: 5,
                usePrefillPrompt: !isLarge,
                detectLanguage: languageHint == nil,
                skipSpecialTokens: true,
                withoutTimestamps: true,
                promptTokens: promptTokens,
                suppressBlank: true,
                compressionRatioThreshold: nil,
                logProbThreshold: nil,
                firstTokenLogProbThreshold: nil,
                noSpeechThreshold: nil
            )
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            let allSegments = results.flatMap { $0.segments }
            let speechSegments = Self.filterHallucinatedSegments(allSegments)
            let raw = speechSegments.map { $0.text }.joined(separator: " ")
            let cleaned = Self.cleanupTranscript(raw)
            // Diagnostics — surface model output so empty pastes can be traced
            // (e.g. HQ-only hallucinations getting stripped, or empty result
            // arrays from over-strict no-speech detection). Inspect via:
            //   log show --predicate 'process == "Scribe"' --last 1m
            NSLog("Scribe transcribe: model=%@ samples=%d segments=%d kept=%d raw=%@ cleaned=%@",
                  ModelManager.shared.loadedQuality?.rawValue ?? "?",
                  samples.count, allSegments.count, speechSegments.count,
                  raw.isEmpty ? "<empty>" : raw,
                  cleaned.isEmpty ? "<empty>" : cleaned)
            await deliver(text: cleaned)
        } catch {
            await deliver(error: error.localizedDescription)
        }
    }

    @MainActor
    private func deliver(text: String) {
        onFinalResult?(text)
    }

    /// Drops segments whose `noSpeechProb` is at or above `noSpeechProbCutoff`.
    /// Whisper's own per-segment confidence is the most reliable signal we have
    /// for "this segment is hallucinated boilerplate" — see `noSpeechProbCutoff`.
    static func filterHallucinatedSegments(_ segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        segments.filter { $0.noSpeechProb < noSpeechProbCutoff }
    }

    /// Strips Whisper's non-speech annotations like `[笑]`, `(Music)`, `[Applause]`, `♪♪`
    /// that the model hallucinates on silence/noise. Leaves real speech untouched.
    static func cleanupTranscript(_ text: String) -> String {
        let keywords =
            "笑声?|大笑|微笑|哭(泣|声)?|叹气?|哽咽|咳嗽|清嗓|喘息|呼吸|沉默|静音|停顿|轻声|背景音乐?|噪音|音乐|掌声|鼓掌"
            + "|嗯+|呃+|啊+|哦+|唉+|嘿+|哎+|哈+"
            + "|laugh(s|ter|ing)?|chuckle[ds]?|giggle[ds]?|sigh(s|ed|ing)?|cough(s|ing|ed)?"
            + "|cry(ing)?|cries|cried|sob(s|bed|bing)?|breath(s|ing|ed)?"
            + "|silence|pause|music|applause|clap(s|ping|ped)?|inaudible|mumbl(e|es|ed|ing)|whispers?"
            + "|♪+|♫+|♩+"

        let bracketed =
            "[\\[\\(（【〔][^\\]\\)）】〕]{0,40}?(\(keywords))[^\\]\\)）】〕]{0,40}?[\\]\\)）】〕]"

        var cleaned = text.replacingOccurrences(
            of: bracketed,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        // Strip bare music-note runs (e.g. "♪♪♪" without brackets).
        cleaned = cleaned.replacingOccurrences(
            of: "[♪♫♩]+",
            with: "",
            options: .regularExpression
        )
        // Collapse double spaces left behind by removals.
        cleaned = cleaned.replacingOccurrences(
            of: "\\s{2,}",
            with: " ",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func deliver(error message: String) {
        onError?(message)
    }
}
