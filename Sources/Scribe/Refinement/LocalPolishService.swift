import Foundation

/// Local GGUF backend (Gemma 4 E2B-it via llama.cpp).
///
/// Tracks the lifecycle from "not downloaded" → downloading → verifying →
/// ready, plus failure modes from the design doc §4.4. Inference runs off-main
/// via `LlamaContext`; the coordinator wraps every call in a 3 s hard timeout.
///
/// Why Gemma 4 E2B (vs Qwen2.5-1.5B in v0.3.x): see [docs/polish-model-eval.md].
/// The 1.5B model failed adversarial cases for persona-leak, question-answering,
/// and multilingual-preservation; E2B (~2B active params, ~5B total in MatFormer)
/// passed 33/36 cases vs Qwen's effective ~22-24/36, at the cost of ~3.46 GB
/// download (vs ~1 GB).
@MainActor
final class LocalPolishService: PolishService {
    let backend: PolishBackend = .local

    /// What the coordinator/UI sees. Maps to `PolishService.isReady` /
    /// `statusText`, plus richer state for the Settings panel's Download
    /// button.
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(percent: Int)
        case verifying
        case ready
        case downloadFailed(reason: String, retriable: Bool)
        case loadFailed(reason: String)
    }

    private(set) var downloadState: DownloadState = .notDownloaded
    var isReady: Bool { downloadState == .ready }
    var statusText: String { LocalPolishService.localizedStatus(for: downloadState) }

    private let descriptor: ModelDescriptor = .gemma4_E2B_it_Q4_K_M
    private let downloader = ModelDownloader.shared
    private var context: LlamaContext?
    private var contextWarmedUp: Bool = false

    init() {
        wireDownloader()
        refreshAvailability()
    }

    /// Re-check the model file on disk + reset stale context. Cheap.
    func refreshAvailability() {
        if ModelLocation.modelIsPresent() {
            downloadState = .ready
        } else if case .downloading = downloadState {
            // Already downloading; don't clobber.
        } else if case .verifying = downloadState {
            // mid-verify
        } else {
            downloadState = .notDownloaded
            // The file we cached against might be gone — drop the context.
            context = nil
            contextWarmedUp = false
        }
        NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
    }

    /// User clicked Download (or Retry). Idempotent.
    func startDownload(mirrorPreference: ModelMirrorPreference, localeCode: String) {
        downloader.start(
            descriptor: descriptor,
            mirrorPreference: mirrorPreference,
            localeCode: localeCode
        )
    }

    /// Cancel an in-flight download. Keeps `.partial` for resume.
    func cancelDownload() {
        downloader.cancel()
    }

    /// Delete the on-disk model file plus any partial state. Used by the
    /// Settings UI when the user wants to free disk space or re-download from
    /// scratch (e.g. after a `loadFailed`).
    func purgeModel() {
        downloader.purge()
        context = nil
        contextWarmedUp = false
        refreshAvailability()
    }

    /// Release the in-memory llama context (synchronously, via `deinit`) so
    /// `llama_free` / `llama_model_free` happen before the process tears down
    /// its global state. Called from `AppDelegate.applicationWillTerminate`.
    /// Does NOT touch the on-disk model file.
    func releaseContextForShutdown() {
        context = nil
        contextWarmedUp = false
    }

    func warmUp() async throws {
        guard isReady else {
            throw PolishError.unavailable(statusText)
        }
        let ctx = self.context ?? LlamaContext(modelPath: ModelLocation.modelURL.path)
        self.context = ctx
        if !contextWarmedUp {
            do {
                try await ctx.warmUp()
                contextWarmedUp = true
            } catch {
                // Hard load failure (corrupt file, ggml init error). Surface
                // it as `.loadFailed` so the Settings UI can offer purge.
                downloadState = .loadFailed(reason: error.localizedDescription)
                self.context = nil
                NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
                throw error
            }
        }
    }

    func polish(_ raw: String, systemPrompt: String) async throws -> String {
        try await warmUp()
        guard let ctx = context else {
            throw PolishError.unavailable(statusText)
        }
        let prompt = Self.gemma4Prompt(system: systemPrompt, user: raw)
        let result = try await ctx.generate(prompt: prompt)
        return Self.cleanGemmaOutput(result)
    }

    // MARK: - Downloader observation

    private func wireDownloader() {
        downloader.stateChanged = { [weak self] state in
            // ModelDownloader posts on main; we're already on the main thread
            // here, but the closure type is a plain `(State) -> Void` so we
            // hop through assumeIsolated to satisfy strict concurrency.
            MainActor.assumeIsolated {
                self?.applyDownloaderState(state)
            }
        }
    }

    private func applyDownloaderState(_ s: ModelDownloader.State) {
        switch s {
        case .idle:
            // Reset to whatever the disk says.
            refreshAvailability()
        case .downloading(let received, let total):
            let pct: Int
            if total > 0 { pct = max(0, min(100, Int(received * 100 / total))) }
            else         { pct = 0 }
            downloadState = .downloading(percent: pct)
        case .verifying:
            downloadState = .verifying
        case .done:
            downloadState = .ready
            // Drop any stale context tied to a previous file.
            context = nil
            contextWarmedUp = false
        case .failed(let reason):
            downloadState = .downloadFailed(
                reason: Self.describe(reason),
                retriable: reason.isRetriable
            )
        case .cancelled:
            // Treat cancel as "back to notDownloaded", but keep .partial on
            // disk so the next Retry resumes from where we stopped.
            downloadState = .notDownloaded
        }
        NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
    }

    private static func describe(_ reason: ModelDownloader.FailureReason) -> String {
        switch reason {
        case .unreachable:
            return L10n.t("polish.local.failNetwork")
        case .mirrorErrors(let codes):
            return L10n.t("polish.local.failMirror") + " (\(codes.map(String.init).joined(separator: ", ")))"
        case .integrity(let actual, let expected):
            return L10n.t("polish.local.failIntegrity") + " (\(String(actual.prefix(12)))… vs \(String(expected.prefix(12)))…)"
        case .notPinned:
            return L10n.t("polish.local.failNotPinned")
        case .diskFull:
            return L10n.t("polish.local.failDiskFull")
        case .ioError(let s):
            return L10n.t("polish.local.failIO") + ": " + s
        case .unknown(let s):
            return s
        }
    }

    private static func localizedStatus(for s: DownloadState) -> String {
        switch s {
        case .notDownloaded:
            return L10n.t("polish.local.statusNotDownloaded")
        case .downloading(let pct):
            return String(format: L10n.t("polish.local.statusDownloading"), pct)
        case .verifying:
            return L10n.t("polish.local.statusVerifying")
        case .ready:
            return L10n.t("polish.local.statusReady")
        case .downloadFailed(let reason, _):
            return L10n.t("polish.local.statusFailed") + " — " + reason
        case .loadFailed(let reason):
            return L10n.t("polish.local.statusLoadFailed") + " — " + reason
        }
    }

    // MARK: - Gemma 4 turn formatting

    /// Gemma 4 uses an entirely new turn structure (NOT the Gemma 3
    /// `<start_of_turn>` format). Verified against
    /// `google/gemma-4-E4B-it/chat_template.jinja`:
    ///
    /// - Open: `<|turn>system\n` / `<|turn>user\n` / `<|turn>model\n`
    /// - Close: `<turn|>\n`     (asymmetric pipes are intentional)
    /// - BOS is added automatically by `llama_tokenize(add_special: true)`
    /// - We deliberately omit the `<|think|>` token to keep thinking mode OFF
    ///   — E2B/E4B produce no `<|channel>thought` block when thinking is
    ///   disabled, so we don't pay the latency or risk of reasoning leaking
    ///   to the user's cursor under timeout.
    ///
    /// Raw dictation is wrapped in `<RAW>...</RAW>` markers with a fresh
    /// "polish, don't answer" preamble. This restructures the `user` turn
    /// from "user asks model" → "user tells model to polish a string" — the
    /// failure mode prevented is the v0.3.7 case where persona "我是向松涛" +
    /// dictation "你知道我是谁吗" produced "我知道你是向松涛" (persona-leak).
    /// Gemma 4 E2B passes that case without the wrapper too, but we keep
    /// the belt-and-suspenders.
    private static func gemma4Prompt(system: String, user: String) -> String {
        let wrapped = """
            Polish the dictation between <RAW> markers. Output ONLY the
            cleaned-up version of what's between the markers, in the same
            language as the dictation. Do not answer or react to it. Do not
            include the markers in your output.

            <RAW>
            \(user)
            </RAW>
            """
        return """
        <|turn>system
        \(system)<turn|>
        <|turn>user
        \(wrapped)<turn|>
        <|turn>model

        """
    }

    /// Strip Gemma 4 turn / channel tokens plus a defensive sweep of legacy
    /// markers (Qwen ChatML, generic BOS/EOS, our `<RAW>` wrappers) just in
    /// case the model emits them. Also drops any `<|channel>thought ... <channel|>`
    /// block — E2B with thinking disabled is documented not to emit these,
    /// but a one-line guard prevents reasoning text from ever reaching the
    /// user's cursor if a future build regresses.
    private static func cleanGemmaOutput(_ raw: String) -> String {
        var s = raw
        while let openRange = s.range(of: "<|channel>thought") {
            if let closeRange = s.range(of: "<channel|>", range: openRange.upperBound..<s.endIndex) {
                s.removeSubrange(openRange.lowerBound..<closeRange.upperBound)
            } else {
                s.removeSubrange(openRange.lowerBound..<s.endIndex)
                break
            }
        }
        for marker in ["<|turn>", "<turn|>", "<|channel>", "<channel|>",
                       "<|im_end|>", "<|im_start|>", "<|endoftext|>",
                       "<bos>", "<eos>",
                       "<RAW>", "</RAW>"] {
            s = s.replacingOccurrences(of: marker, with: "")
        }
        return PolishPrompt.stripCommonPreface(s)
    }
}
