import Foundation
import os

/// Serial dispatch queue that bridges synchronous, cancellation-polling work
/// (the llama.cpp inference loop) to Swift's async/await world.
///
/// The hazard this exists to solve: putting `Task.checkCancellation()` inside
/// a `DispatchQueue.async` closure does nothing — the closure has no current
/// Task, so `Task.isCancelled` returns `false` regardless of what the
/// awaiting Task's state is. Every cancellation check the inference loop
/// thinks it's doing is a no-op, so a polish that hits the 5 s timeout
/// keeps generating up to `maxNewTokens` tokens before unblocking the
/// awaiting `withCheckedThrowingContinuation`. `withTimeout`'s implicit
/// await-on-cancel then *also* waits for that natural completion before
/// returning to the user. End result: the visible polish duration on
/// timeout becomes 5 s + remaining-generation-time (potentially 10–15 s
/// on slow Apple Silicon) instead of just 5 s.
///
/// Mechanism here:
/// - `run(_:)` resets the flag, then enters `withTaskCancellationHandler`.
///   If the calling Task is already cancelled the handler runs immediately
///   and sets the flag, so the work's first poll trips. If cancellation
///   arrives mid-flight, the handler runs concurrently and the work's
///   *next* poll trips. Either way, control returns to the caller within
///   one poll interval of cancel — not after the work runs to completion.
/// - `cancelAndDrain()` sets the flag and **blocks** via `queue.sync { }`
///   until the queue is idle. Use this from `applicationWillTerminate`
///   before tearing down resources the work was using (e.g. ggml's
///   process-wide backend) so we don't free state out from under an
///   in-flight `llama_decode`.
final class CancellableInferenceQueue: @unchecked Sendable {
    /// Thrown by `Token.checkCancelled()` when external cancellation has
    /// been requested. Distinct type so callers can match it precisely
    /// rather than relying on `LocalizedError` strings.
    struct CancelledError: Swift.Error, LocalizedError {
        var errorDescription: String? { "Inference cancelled" }
    }

    /// Handed to each `run` invocation's work closure. The work must call
    /// `checkCancelled()` (or read `isCancelled`) at safe points — typically
    /// once per generated token. Bounded poll latency = bounded user-visible
    /// cancel latency.
    final class Token: @unchecked Sendable {
        fileprivate let lock: OSAllocatedUnfairLock<Bool>
        fileprivate init(lock: OSAllocatedUnfairLock<Bool>) { self.lock = lock }

        var isCancelled: Bool { lock.withLock { $0 } }

        func checkCancelled() throws {
            if isCancelled { throw CancelledError() }
        }
    }

    private let queue: DispatchQueue
    private let lock = OSAllocatedUnfairLock<Bool>(initialState: false)

    init(label: String, qos: DispatchQoS = .userInitiated) {
        self.queue = DispatchQueue(label: label, qos: qos)
    }

    /// Run `work` on the serial queue. Honours the calling Task's
    /// cancellation: if it's cancelled (now or later), the token's flag
    /// flips and `work`'s next poll throws `CancelledError`.
    ///
    /// Resets the cancellation flag at entry — `cancelAndDrain` is meant
    /// to terminate the *current* in-flight work and end the queue's
    /// useful life; new `run` calls after a drain are not expected, but
    /// resetting here keeps the per-call semantics clean.
    func run<T: Sendable>(_ work: @escaping @Sendable (Token) throws -> T) async throws -> T {
        lock.withLock { $0 = false }
        let token = Token(lock: lock)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Swift.Error>) in
                queue.async {
                    do {
                        let value = try work(token)
                        cont.resume(returning: value)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
        } onCancel: { [lock] in
            lock.withLock { $0 = true }
        }
    }

    /// Set the cancel flag, then synchronously wait for the queue to
    /// reach idle. After this returns, no further work is using whatever
    /// resources the previous `run` closure touched, so the caller is
    /// safe to free C state (model, context, ggml backend).
    ///
    /// Bounded by the work's poll interval (single-digit ms for a
    /// per-token check) plus any single in-flight C call already issued
    /// before the most recent poll — for `llama_decode`, that's whatever
    /// one decode step costs.
    func cancelAndDrain() {
        lock.withLock { $0 = true }
        queue.sync { }
    }
}
