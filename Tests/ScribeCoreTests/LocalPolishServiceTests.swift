import Testing
@testable import ScribeCore

/// Covers the R3 contract: `refreshAvailability` must preserve
/// user-visible failure states across incidental refreshes (e.g.
/// `applicationDidBecomeActive`). Without this, a download/load failure
/// silently resets to `Not downloaded` the next time the user switches
/// apps and back — losing the reason they should retry.
@Suite @MainActor
struct LocalPolishServiceTests {

    // MARK: - R3 sticky failure preservation

    @Test func refreshPreservesDownloadFailedWhenModelMissing() {
        let svc = LocalPolishService(modelIsPresent: { false })
        svc._setDownloadStateForTesting(
            .downloadFailed(reason: "stub network failure", retriable: true)
        )

        svc.refreshAvailability()

        guard case .downloadFailed(let reason, let retriable) = svc.downloadState else {
            Issue.record("Expected .downloadFailed, got \(svc.downloadState)")
            return
        }
        #expect(reason == "stub network failure")
        #expect(retriable)
        #expect(!svc.isReady)
    }

    @Test func refreshPreservesLoadFailedEvenWhenFilePresent() {
        // .loadFailed happens *with* the file on disk (mmap / llama_model_load
        // failure). It must NOT be auto-promoted to .ready just because the
        // file is still there — that would mask the underlying failure.
        let svc = LocalPolishService(modelIsPresent: { true })
        svc._setDownloadStateForTesting(.loadFailed(reason: "stub corrupt model"))

        svc.refreshAvailability()

        guard case .loadFailed(let reason) = svc.downloadState else {
            Issue.record("Expected .loadFailed, got \(svc.downloadState)")
            return
        }
        #expect(reason == "stub corrupt model")
        #expect(!svc.isReady)
    }

    @Test func refreshPromotesNotDownloadedToReadyWhenFileAppears() {
        // The user-pasted-the-file-manually path. `.notDownloaded` isn't
        // sticky — file appearing is an unconditional promotion.
        let svc = LocalPolishService(modelIsPresent: { true })
        svc._setDownloadStateForTesting(.notDownloaded)

        svc.refreshAvailability()

        #expect(svc.downloadState == .ready)
        #expect(svc.isReady)
    }

    @Test func refreshDemotesReadyToNotDownloadedWhenFileDisappears() {
        // The user-deleted-the-file-from-Finder path. `.ready` isn't sticky —
        // disk truth wins.
        let svc = LocalPolishService(modelIsPresent: { false })
        svc._setDownloadStateForTesting(.ready)

        svc.refreshAvailability()

        #expect(svc.downloadState == .notDownloaded)
        #expect(!svc.isReady)
    }

    @Test func refreshLeavesDownloadingAlone() {
        // In-flight download must not be clobbered by a stray refresh.
        let svc = LocalPolishService(modelIsPresent: { false })
        svc._setDownloadStateForTesting(.downloading(percent: 42))

        svc.refreshAvailability()

        guard case .downloading(let pct) = svc.downloadState else {
            Issue.record("Expected .downloading, got \(svc.downloadState)")
            return
        }
        #expect(pct == 42)
    }

    @Test func refreshLeavesVerifyingAlone() {
        let svc = LocalPolishService(modelIsPresent: { false })
        svc._setDownloadStateForTesting(.verifying)

        svc.refreshAvailability()

        #expect(svc.downloadState == .verifying)
    }
}
