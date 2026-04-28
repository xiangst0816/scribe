import Foundation
import Testing
@testable import ScribeCore

/// Regression tests for the cancellation + drain primitive that backs
/// `LlamaContext`. Exercising it against a real `LlamaContext` would mean
/// pulling a 3.46 GB GGUF into CI; instead we drive `CancellableInferenceQueue`
/// directly with synthetic work that mimics the per-token poll loop in
/// `LlamaContext.generateSync`. The mechanism is the same — if these pass,
/// the inference loop's cancellation flow works too.
@Suite struct CancellableInferenceQueueTests {

    // MARK: - R1 — cancel actually unblocks the awaiting task

    /// The headline regression. Before the fix, a `Task.checkCancellation()`
    /// inside the dispatch closure was a no-op because the closure had no
    /// current Task. With the flag-based primitive, an external `task.cancel()`
    /// must propagate to the work loop within one poll interval.
    @Test func cancelUnblocksWithinOnePollInterval() async {
        let q = CancellableInferenceQueue(label: "test.q1")

        let pollInterval: TimeInterval = 0.01
        let workTask = Task<Void, Error> {
            try await q.run { token in
                // Simulate a long inference loop polling each "token".
                for _ in 0..<10_000 {
                    try token.checkCancelled()
                    Thread.sleep(forTimeInterval: pollInterval)
                }
            }
        }

        // Give the work a moment to actually start running.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let cancelTime = Date()
        workTask.cancel()

        do {
            try await workTask.value
            Issue.record("Cancelled work must throw, not return normally")
        } catch is CancellableInferenceQueue.CancelledError {
            let elapsed = Date().timeIntervalSince(cancelTime)
            // Allow one poll interval + scheduling slack. Without the fix this
            // would be the full work loop (~100 s) and the test would time out.
            #expect(
                elapsed < 0.3,
                "Cancel must unblock within one poll interval; elapsed = \(elapsed)s"
            )
        } catch {
            Issue.record("Expected CancelledError, got \(error)")
        }
    }

    /// The composite regression: when the work is wrapped in
    /// `PolishCoordinator.withTimeout`, the user-visible duration must be
    /// bounded by the timeout, not by the work's natural completion. This is
    /// the actual user-impact assertion — without R1, the timeout wrapper
    /// blocks until the inner work finishes naturally.
    @Test @MainActor func timeoutWrapperReturnsPromptly() async {
        let q = CancellableInferenceQueue(label: "test.q2")
        let timeoutSeconds: TimeInterval = 0.2
        let pollInterval: TimeInterval = 0.01

        let start = Date()
        do {
            _ = try await withTimeout(seconds: timeoutSeconds) {
                try await q.run { token in
                    for _ in 0..<10_000 {
                        try token.checkCancelled()
                        Thread.sleep(forTimeInterval: pollInterval)
                    }
                    return "done"
                }
            }
            Issue.record("Should have timed out")
        } catch PolishError.timeout {
            let elapsed = Date().timeIntervalSince(start)
            // Timeout (0.2 s) + one poll interval + scheduling slack.
            #expect(
                elapsed < 0.6,
                "Timeout must return promptly; elapsed = \(elapsed)s"
            )
        } catch {
            Issue.record("Expected PolishError.timeout, got \(error)")
        }
    }

    /// Natural (non-cancelled) completion still works and returns the value.
    /// Pins that the cancellation plumbing didn't break the happy path.
    @Test func naturalCompletionReturnsValue() async throws {
        let q = CancellableInferenceQueue(label: "test.q3")
        let result = try await q.run { token in
            for _ in 0..<10 {
                try token.checkCancelled()
                Thread.sleep(forTimeInterval: 0.001)
            }
            return 42
        }
        #expect(result == 42)
    }

    /// A second `run` after a cancelled first `run` must observe a fresh
    /// (un-cancelled) flag. Per-call reset is what makes this work.
    @Test func flagResetsBetweenCalls() async throws {
        let q = CancellableInferenceQueue(label: "test.q4")

        // First call — cancel mid-flight, expect throw.
        let task1 = Task<Void, Error> {
            try await q.run { token in
                while !token.isCancelled {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                try token.checkCancelled()
            }
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task1.cancel()
        do { try await task1.value } catch is CancellableInferenceQueue.CancelledError { /* ok */ }

        // Second call — must run to completion, not see a stuck flag.
        let result = try await q.run { _ in "second" }
        #expect(result == "second")
    }

    // MARK: - R2 — cancelAndDrain blocks until work has unwound

    /// `cancelAndDrain` must not return until any in-flight work has
    /// observably finished. This is what makes it safe to free C resources
    /// (the global ggml backend) immediately afterward.
    @Test func cancelAndDrainBlocksUntilWorkCompletes() async throws {
        let q = CancellableInferenceQueue(label: "test.q5")
        let inFlight = ConcurrentCounter()

        // Kick off long-running work, don't await yet.
        let workTask = Task<Void, Error> {
            do {
                try await q.run { token in
                    inFlight.increment()
                    defer { inFlight.decrement() }
                    while !token.isCancelled {
                        Thread.sleep(forTimeInterval: 0.005)
                    }
                    try token.checkCancelled()
                }
            } catch is CancellableInferenceQueue.CancelledError {
                // Expected — drain triggered cancel.
            }
        }

        // Wait for the work to actually start.
        try await pollUntil(timeout: 1.0) { inFlight.value == 1 }
        #expect(inFlight.value == 1, "Work should be running before drain")

        // The contract: when cancelAndDrain returns, no work is in flight.
        await Task.detached { q.cancelAndDrain() }.value
        #expect(
            inFlight.value == 0,
            "cancelAndDrain must block until work has unwound"
        )

        // Sanity: the work task finishes too. We caught CancelledError inside,
        // so this never throws — the `try?` is belt-and-suspenders.
        _ = try? await workTask.value
    }

    /// `cancelAndDrain` is safe to call when nothing is running — must not
    /// hang or crash.
    @Test func cancelAndDrainOnIdleQueueIsNoop() async {
        let q = CancellableInferenceQueue(label: "test.q6")
        await confirmation { confirm in
            await Task.detached {
                q.cancelAndDrain()
                confirm()
            }.value
        }
    }

    // MARK: - Helpers

    private func pollUntil(
        timeout: TimeInterval,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw NSError(domain: "test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "predicate never became true within \(timeout)s",
        ])
    }
}

/// Trivial atomic counter for cross-thread observability inside tests.
/// Avoids a Foundation dep on swift-atomics for this one helper.
private final class ConcurrentCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return _value }
    func increment() { lock.lock(); _value += 1; lock.unlock() }
    func decrement() { lock.lock(); _value -= 1; lock.unlock() }
}
