import Foundation
import llama

/// Thin Swift wrapper over llama.cpp's C API. Owns one model + one context;
/// a single Polish session reuses both across calls.
///
/// Threading: the wrapper is intentionally **not** `@MainActor`. Inference is
/// CPU-/GPU-bound for hundreds of milliseconds; we serialise it onto a private
/// dispatch queue so it can't block the main thread while the user is mid-paste.
/// All public methods are safe to call from any actor; results come back on
/// the caller's actor via `async`.
final class LlamaContext {
    enum Error: LocalizedError {
        case modelLoadFailed(String)
        case contextInitFailed
        case tokenizationFailed(Int32)
        case decodeFailed(Int32)
        case samplerInitFailed
        case generationCancelled

        var errorDescription: String? {
            switch self {
            case .modelLoadFailed(let p):     return "Failed to load model at \(p)"
            case .contextInitFailed:          return "Failed to initialise llama context"
            case .tokenizationFailed(let n):  return "Tokenization failed (\(n))"
            case .decodeFailed(let n):        return "Decode failed with status \(n)"
            case .samplerInitFailed:          return "Failed to initialise sampler"
            case .generationCancelled:        return "Generation cancelled"
            }
        }
    }

    struct SamplingParams {
        var temperature: Float = 0.25
        var topP: Float = 0.9
        var repeatPenalty: Float = 1.1
        var maxNewTokens: Int = 256
        var seed: UInt32 = 0xCAFE
    }

    private let modelPath: String
    private let queue: DispatchQueue
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var nCtx: UInt32 = 4096

    /// Tracks whether `llama_backend_init()` has run in this process. Used by
    /// `tearDownProcessBackend` to skip the free if no llama context was ever
    /// loaded (e.g. user never enabled Local backend).
    nonisolated(unsafe) private static var backendInitialized = false

    /// Backend init must happen exactly once per process. Done lazily here.
    private static let backendOnce: Void = {
        // Silence ggml/llama log spam in production. The framework otherwise
        // dumps Metal kernel compile lines and per-token timing that would
        // pollute Console.app for every Polish call.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        LlamaContext.backendInitialized = true
    }()

    /// Drain ggml's process-wide state. Must run **before** NSApplication's
    /// `exit()` calls C++ static destructors, otherwise the destructor for
    /// the global `vector<ggml_metal_device>` races against any background
    /// `__ggml_metal_rsets_init_block_invoke` still compiling pipelines and
    /// `ggml_abort()` → SIGABRT (this is what crashed v0.3.3 on Cmd-Q).
    ///
    /// Idempotent — safe to call from `applicationWillTerminate` whether or
    /// not the Local backend was ever warmed up.
    static func tearDownProcessBackend() {
        guard backendInitialized else { return }
        llama_backend_free()
        backendInitialized = false
    }

    init(modelPath: String) {
        _ = LlamaContext.backendOnce
        self.modelPath = modelPath
        self.queue = DispatchQueue(label: "com.yetone.Scribe.llama", qos: .userInitiated)
    }

    deinit {
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
    }

    /// Load model + context into memory. Synchronously runs on the inference
    /// queue; first call typically takes 0.5–1.5 s on M2 for Qwen2.5-1.5B.
    /// Subsequent calls are no-ops.
    func warmUp() async throws {
        try await onQueue { [self] in
            guard model == nil else { return }
            let mparams = llama_model_default_params()
            guard let m = llama_model_load_from_file(modelPath, mparams) else {
                throw Error.modelLoadFailed(modelPath)
            }
            self.model = m
            self.vocab = llama_model_get_vocab(m)

            var cparams = llama_context_default_params()
            cparams.n_ctx = nCtx
            // The polish prompt + Qwen ChatML wrapper + few-shot examples is
            // ~700–900 tokens on the long side; n_batch must fit the whole
            // prompt-decode pass in one shot or llama_decode aborts with
            // "n_tokens_all <= cparams.n_batch". 2048 leaves headroom for
            // future prompt growth without paying for the full 4096 ctx.
            cparams.n_batch = 2048
            guard let c = llama_init_from_model(m, cparams) else {
                llama_model_free(m)
                self.model = nil
                throw Error.contextInitFailed
            }
            self.ctx = c
        }
    }

    /// Run a single prompt → completion. Stops at EOS, the Qwen end-of-message
    /// tokens, or `maxNewTokens` — whichever comes first.
    ///
    /// `prompt` is the fully-templated text including chat-format wrappers.
    /// The caller (PolishPrompt) owns formatting decisions.
    func generate(prompt: String, params: SamplingParams = .init()) async throws -> String {
        try await onQueue { [self] in
            try ensureLoaded()
            return try generateSync(prompt: prompt, params: params)
        }
    }

    // MARK: - Private (always runs on `queue`)

    private func ensureLoaded() throws {
        guard model != nil else {
            // The coordinator should have called warmUp() first; tolerate the
            // hot-load path anyway so callers don't crash.
            throw Error.contextInitFailed
        }
    }

    private func generateSync(prompt: String, params: SamplingParams) throws -> String {
        guard let ctx, let vocab else { throw Error.contextInitFailed }

        // Reset KV cache so each polish call is independent (no carryover
        // between unrelated dictations).
        llama_memory_clear(llama_get_memory(ctx), true)

        // Tokenize the prompt. Allocate generously — Qwen ChatML wrappers add
        // ~10 tokens around a typical 30-token transcript.
        let cstr = prompt.cString(using: .utf8) ?? []
        let cstrLen = Int32(cstr.count - 1)  // exclude trailing NUL
        var tokens = [llama_token](repeating: 0, count: max(Int(cstrLen) + 32, 64))
        let n = tokens.withUnsafeMutableBufferPointer { buf in
            llama_tokenize(vocab, cstr, cstrLen,
                           buf.baseAddress, Int32(buf.count),
                           true /* add_special */, true /* parse_special */)
        }
        // llama_tokenize returns negative if buffer was too small (negated
        // required size); grow once and retry.
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            let n2 = tokens.withUnsafeMutableBufferPointer { buf in
                llama_tokenize(vocab, cstr, cstrLen,
                               buf.baseAddress, Int32(buf.count),
                               true, true)
            }
            guard n2 > 0 else { throw Error.tokenizationFailed(n2) }
            tokens = Array(tokens.prefix(Int(n2)))
        } else {
            guard n > 0 else { throw Error.tokenizationFailed(n) }
            tokens = Array(tokens.prefix(Int(n)))
        }

        // Decode the prompt in one batch.
        let batch = llama_batch_get_one(&tokens, Int32(tokens.count))
        let r = llama_decode(ctx, batch)
        guard r == 0 else { throw Error.decodeFailed(r) }

        // Build a sampler chain: temperature → top_p → distribution.
        let sparams = llama_sampler_chain_default_params()
        guard let sampler = llama_sampler_chain_init(sparams) else {
            throw Error.samplerInitFailed
        }
        defer { llama_sampler_free(sampler) }
        if params.repeatPenalty != 1.0 {
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, params.repeatPenalty, 0.0, 0.0))
        }
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.topP, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temperature))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(params.seed))

        // Accumulate raw token bytes here. Tokens may emit *partial* UTF-8
        // sequences (CJK code points are 3 bytes; one byte per token is
        // common). Building the result via per-token `String(cString:)`
        // would split multi-byte sequences and produce U+FFFD replacement
        // chars in the polished Chinese / Japanese / Korean output. We
        // collect bytes and only flush to a String when the trailing bytes
        // form a complete UTF-8 sequence.
        var byteAccumulator: [UInt8] = []
        byteAccumulator.reserveCapacity(params.maxNewTokens * 4)
        var nGenerated = 0
        var pieceBuf = [UInt8](repeating: 0, count: 128)

        while nGenerated < params.maxNewTokens {
            // Cooperative cancellation — coordinator's withTimeout cancels the
            // outer Task; the queue hop in `onQueue` checks `Task.isCancelled`.
            // We also check inside the generation loop so we stop ASAP.
            try Task.checkCancellation()

            var nextTok = llama_sampler_sample(sampler, ctx, -1)
            if llama_vocab_is_eog(vocab, nextTok) { break }

            let pieceLen = pieceBuf.withUnsafeMutableBufferPointer { buf -> Int32 in
                buf.baseAddress!.withMemoryRebound(to: CChar.self, capacity: buf.count) { rebound in
                    llama_token_to_piece(vocab, nextTok,
                                         rebound, Int32(buf.count),
                                         0 /* lstrip */, true /* special */)
                }
            }
            if pieceLen > 0 {
                byteAccumulator.append(contentsOf: pieceBuf.prefix(Int(pieceLen)))
            }

            let stepBatch = llama_batch_get_one(&nextTok, 1)
            let dr = llama_decode(ctx, stepBatch)
            guard dr == 0 else { throw Error.decodeFailed(dr) }
            nGenerated += 1
        }

        // Decode the accumulated bytes as UTF-8. Done once at the end so we
        // never split a multi-byte code point. Lossy conversion would fall
        // back to U+FFFD on malformed bytes, which we'd rather see than
        // crash; in practice the model outputs valid UTF-8 once the full
        // token stream is in hand.
        return String(decoding: byteAccumulator, as: UTF8.self)
    }

    /// Run a closure on the inference queue and bridge the result back to the
    /// caller's actor. Honours task cancellation by failing fast before the
    /// hop and after the work returns.
    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                if Task.isCancelled {
                    cont.resume(throwing: Error.generationCancelled)
                    return
                }
                do {
                    let value = try work()
                    cont.resume(returning: value)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
