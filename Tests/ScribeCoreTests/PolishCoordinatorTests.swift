import Foundation
import Testing
@testable import ScribeCore

/// Covers `PolishCoordinator` — the timeout, validation, and circuit-breaker
/// behaviour that decides whether a polish call's output makes it to the user
/// or whether we silently fall back to the raw transcript.
@Suite @MainActor
final class PolishCoordinatorTests {

    private let coordinator: PolishCoordinator

    init() {
        // Each test gets its own coordinator with a fresh defaults suite so
        // persistence (polish.enabled, polish.backend) doesn't bleed across
        // tests or pick up the developer's real choices.
        let suiteName = "ScribeTests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suiteName)
        coordinator = PolishCoordinator(testDefaults: UserDefaults(suiteName: suiteName)!)
    }

    @Test func noPolishWhenDisabled() async {
        coordinator.isEnabled = false
        let result = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        #expect(result == "hello")
    }

    @Test func noPolishWhenSelectedBackendIsNotReady() async {
        coordinator.isEnabled = true
        coordinator.selectedBackend = .local  // stub, not ready
        let result = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        #expect(result == "hello")
    }

    @Test func circuitBreakerTripsAfterThreeFailures() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubFailingService(), as: .local)
        coordinator.selectedBackend = .local

        var trippedMessage: String?
        coordinator.onBreakerTripped = { msg in trippedMessage = msg }

        for _ in 0..<3 {
            _ = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        }

        #expect(coordinator.consecutiveFailures == 3)
        #expect(coordinator.isBreakerTripped)
        #expect(!coordinator.isEnabled, "Breaker tripping must flip the master switch off")
        #expect(trippedMessage != nil)
    }

    @Test func successResetsFailureCounter() async {
        coordinator.isEnabled = true
        let svc = StubFlakyService(throwOnFirstNCalls: 1)
        coordinator.injectStubService(svc, as: .local)
        coordinator.selectedBackend = .local

        let first = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        #expect(first == "hi", "First call throws → falls back to raw")
        #expect(coordinator.consecutiveFailures == 1)

        let second = await coordinator.maybePolish("hi there", selectedLocaleCode: "en-US")
        #expect(second == "POLISHED: hi there")
        #expect(coordinator.consecutiveFailures == 0, "Successful call resets the counter")
    }

    @Test func emptyOutputIsTreatedAsFailure() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubReturning(""), as: .local)
        coordinator.selectedBackend = .local

        let result = await coordinator.maybePolish("the original", selectedLocaleCode: "en-US")
        #expect(result == "the original")
        #expect(coordinator.consecutiveFailures == 1)
    }

    @Test func lengthExplosionIsTreatedAsFailure() async {
        coordinator.isEnabled = true
        let runaway = String(repeating: "x", count: 1000)
        coordinator.injectStubService(StubReturning(runaway), as: .local)
        coordinator.selectedBackend = .local

        let result = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        #expect(result == "hi", "Output 500x longer than input is rejected; raw is pasted")
        #expect(coordinator.consecutiveFailures == 1)
    }

    @Test func timeoutFallsBackToRaw() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubSlowService(delaySeconds: 30), as: .local)
        coordinator.selectedBackend = .local

        let start = Date()
        let result = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == "hi")
        #expect(
            elapsed < PolishCoordinator.timeoutSeconds + 1.0,
            "Must abort by the configured timeout, not wait the full delay"
        )

        // R4: timeouts MUST NOT increment the breaker counter — slow Apple
        // Silicon would otherwise auto-disable polish mid-session every time
        // the model happens to clip the budget. Timeouts are tracked
        // separately so the menu can still surface them.
        #expect(
            coordinator.consecutiveFailures == 0,
            "Timeout must not increment consecutiveFailures (would trip breaker on slow hardware)"
        )
        #expect(
            coordinator.lastCallTimedOut,
            "Menu needs lastCallTimedOut to surface the silent fallback to the user"
        )
        #expect(coordinator.consecutiveTimeouts == 1)
    }

    @Test func successAfterTimeoutClearsLastCallTimedOut() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubSlowService(delaySeconds: 30), as: .local)
        coordinator.selectedBackend = .local

        // First call times out.
        _ = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        #expect(coordinator.lastCallTimedOut)
        #expect(coordinator.consecutiveTimeouts == 1)

        // Swap in a fast stub. A single successful polish must clear the
        // timeout flag (otherwise the menu sticks at "Skipped (timed out)"
        // forever even after polish recovered).
        coordinator.injectStubService(StubReturning("POLISHED: hi"), as: .local)
        let result = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        #expect(result == "POLISHED: hi")
        #expect(!coordinator.lastCallTimedOut)
        #expect(coordinator.consecutiveTimeouts == 0)
    }

    @Test func repeatedTimeoutsDoNotTripBreaker() async {
        // The whole reason timeouts and failures count separately. Many
        // timeouts in a row on slow hardware must NOT auto-disable polish.
        coordinator.isEnabled = true
        coordinator.injectStubService(StubSlowService(delaySeconds: 30), as: .local)
        coordinator.selectedBackend = .local

        for _ in 0..<5 {
            _ = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        }

        #expect(!coordinator.isBreakerTripped)
        #expect(coordinator.isEnabled)
        #expect(coordinator.consecutiveFailures == 0)
        #expect(coordinator.consecutiveTimeouts == 5)
    }

    @Test func resetCircuitBreakerClearsState() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubFailingService(), as: .local)
        coordinator.selectedBackend = .local

        for _ in 0..<3 {
            _ = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        }
        #expect(coordinator.isBreakerTripped)

        coordinator.resetCircuitBreaker()
        #expect(coordinator.consecutiveFailures == 0)
        #expect(!coordinator.isBreakerTripped)
    }

    @Test func purgeLegacyKeysClearsOldDefaults() {
        let suiteName = "ScribeTests-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "llmEnabled")
        defaults.set("https://example.com", forKey: "llmAPIBaseURL")
        defaults.set("sk-old", forKey: "llmAPIKey")
        defaults.set("gpt-4", forKey: "llmModel")

        PolishCoordinator.purgeLegacyKeys(in: defaults)

        #expect(defaults.object(forKey: "llmEnabled") == nil)
        #expect(defaults.object(forKey: "llmAPIBaseURL") == nil)
        #expect(defaults.object(forKey: "llmAPIKey") == nil)
        #expect(defaults.object(forKey: "llmModel") == nil)
    }
}

// MARK: - Stub services

@MainActor
private final class StubFailingService: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: always fails" }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, systemPrompt: String) async throws -> String {
        throw PolishError.unavailable("stub failure")
    }
}

@MainActor
private final class StubReturning: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: returns fixed text" }
    private let output: String
    init(_ output: String) { self.output = output }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, systemPrompt: String) async throws -> String { output }
}

@MainActor
private final class StubFlakyService: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: throws first N calls" }
    private var remainingThrows: Int
    init(throwOnFirstNCalls n: Int) { self.remainingThrows = n }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, systemPrompt: String) async throws -> String {
        if remainingThrows > 0 {
            remainingThrows -= 1
            throw PolishError.unavailable("flaky")
        }
        return "POLISHED: " + raw
    }
}

@MainActor
private final class StubSlowService: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: very slow" }
    private let delay: TimeInterval
    init(delaySeconds: TimeInterval) { self.delay = delaySeconds }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, systemPrompt: String) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return "POLISHED: " + raw
    }
}
