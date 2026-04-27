import XCTest
@testable import ScribeCore

/// Covers `PolishCoordinator` — the timeout, validation, and circuit-breaker
/// behaviour that decides whether a polish call's output makes it to the user
/// or whether we silently fall back to the raw transcript.
@MainActor
final class PolishCoordinatorTests: XCTestCase {

    private var coordinator: PolishCoordinator!

    override func setUp() async throws {
        // Each test gets its own coordinator with a fresh defaults suite so
        // persistence (polish.enabled, polish.backend) doesn't bleed across
        // tests or pick up the developer's real choices.
        let suiteName = "ScribeTests-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suiteName)
        coordinator = PolishCoordinator(testDefaults: UserDefaults(suiteName: suiteName)!)
    }

    func testNoPolishWhenDisabled() async {
        coordinator.isEnabled = false
        let result = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        XCTAssertEqual(result, "hello")
    }

    func testNoPolishWhenSelectedBackendIsNotReady() async {
        coordinator.isEnabled = true
        coordinator.selectedBackend = .local  // stub, not ready
        let result = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        XCTAssertEqual(result, "hello")
    }

    func testCircuitBreakerTripsAfterThreeFailures() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubFailingService(), as: .local)
        coordinator.selectedBackend = .local

        var trippedMessage: String?
        coordinator.onBreakerTripped = { msg in trippedMessage = msg }

        for _ in 0..<3 {
            _ = await coordinator.maybePolish("hello", selectedLocaleCode: "en-US")
        }

        XCTAssertEqual(coordinator.consecutiveFailures, 3)
        XCTAssertTrue(coordinator.isBreakerTripped)
        XCTAssertFalse(coordinator.isEnabled, "Breaker tripping must flip the master switch off")
        XCTAssertNotNil(trippedMessage)
    }

    func testSuccessResetsFailureCounter() async {
        coordinator.isEnabled = true
        let svc = StubFlakyService(throwOnFirstNCalls: 1)
        coordinator.injectStubService(svc, as: .local)
        coordinator.selectedBackend = .local

        let first = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        XCTAssertEqual(first, "hi", "First call throws → falls back to raw")
        XCTAssertEqual(coordinator.consecutiveFailures, 1)

        let second = await coordinator.maybePolish("hi there", selectedLocaleCode: "en-US")
        XCTAssertEqual(second, "POLISHED: hi there")
        XCTAssertEqual(coordinator.consecutiveFailures, 0, "Successful call resets the counter")
    }

    func testEmptyOutputIsTreatedAsFailure() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubReturning(""), as: .local)
        coordinator.selectedBackend = .local

        let result = await coordinator.maybePolish("the original", selectedLocaleCode: "en-US")
        XCTAssertEqual(result, "the original")
        XCTAssertEqual(coordinator.consecutiveFailures, 1)
    }

    func testLengthExplosionIsTreatedAsFailure() async {
        coordinator.isEnabled = true
        let runaway = String(repeating: "x", count: 1000)
        coordinator.injectStubService(StubReturning(runaway), as: .local)
        coordinator.selectedBackend = .local

        let result = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        XCTAssertEqual(result, "hi", "Output 500x longer than input is rejected; raw is pasted")
        XCTAssertEqual(coordinator.consecutiveFailures, 1)
    }

    func testTimeoutFallsBackToRaw() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubSlowService(delaySeconds: 5), as: .local)
        coordinator.selectedBackend = .local

        let start = Date()
        let result = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(result, "hi")
        XCTAssertLessThan(elapsed, PolishCoordinator.timeoutSeconds + 1.0,
                          "Must abort by the configured timeout, not wait the full delay")
        XCTAssertEqual(coordinator.consecutiveFailures, 1)
    }

    func testResetCircuitBreakerClearsState() async {
        coordinator.isEnabled = true
        coordinator.injectStubService(StubFailingService(), as: .local)
        coordinator.selectedBackend = .local

        for _ in 0..<3 {
            _ = await coordinator.maybePolish("hi", selectedLocaleCode: "en-US")
        }
        XCTAssertTrue(coordinator.isBreakerTripped)

        coordinator.resetCircuitBreaker()
        XCTAssertEqual(coordinator.consecutiveFailures, 0)
        XCTAssertFalse(coordinator.isBreakerTripped)
    }

    func testPurgeLegacyKeysClearsOldDefaults() {
        let suiteName = "ScribeTests-legacy-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(true, forKey: "llmEnabled")
        defaults.set("https://example.com", forKey: "llmAPIBaseURL")
        defaults.set("sk-old", forKey: "llmAPIKey")
        defaults.set("gpt-4", forKey: "llmModel")

        PolishCoordinator.purgeLegacyKeys(in: defaults)

        XCTAssertNil(defaults.object(forKey: "llmEnabled"))
        XCTAssertNil(defaults.object(forKey: "llmAPIBaseURL"))
        XCTAssertNil(defaults.object(forKey: "llmAPIKey"))
        XCTAssertNil(defaults.object(forKey: "llmModel"))
    }
}

// MARK: - Stub services

@MainActor
private final class StubFailingService: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: always fails" }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, languageHint: String) async throws -> String {
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
    func polish(_ raw: String, languageHint: String) async throws -> String { output }
}

@MainActor
private final class StubFlakyService: PolishService {
    let backend: PolishBackend = .local
    var isReady: Bool { true }
    var statusText: String { "stub: throws first N calls" }
    private var remainingThrows: Int
    init(throwOnFirstNCalls n: Int) { self.remainingThrows = n }
    func warmUp() async throws { /* no-op */ }
    func polish(_ raw: String, languageHint: String) async throws -> String {
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
    func polish(_ raw: String, languageHint: String) async throws -> String {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return "POLISHED: " + raw
    }
}
