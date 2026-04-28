import Foundation
import Testing
@testable import ScribeCore

/// Y5 regression tests. The pre-Y5 downloader used `URLSessionDownloadTask`,
/// which only writes to disk on full completion; cancel/error mid-download
/// produced an empty `.partial` and any `Range:` resume started from
/// byte 0. The new `URLSessionDataTask` + streaming-append flow has to
/// (a) actually populate `.partial` while bytes are arriving, (b) advance
/// to the next mirror on 4xx, (c) honour the `Range:` header on resume,
/// and (d) reject integrity mismatches without re-trying.
///
/// HTTP is mocked through `StubURLProtocol`; disk paths are redirected
/// to a per-test temp directory via `ModelLocation._supportDirectoryOverrideForTesting`.
/// `.serialized` so the global URLProtocol registration and shared
/// `_supportDirectoryOverrideForTesting` slot don't interleave between tests.
@Suite(.serialized)
@MainActor
final class ModelDownloaderTests {

    private let tempDir: URL
    private let downloader: ModelDownloader

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelDownloaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        ModelLocation._supportDirectoryOverrideForTesting = tempDir
        ModelLocation.ensureModelsDirectoryExists()

        StubURLProtocol.reset()

        downloader = ModelDownloader()
        // Inject the stub directly into the session config — global
        // `URLProtocol.registerClass` doesn't reach custom URLSessions.
        downloader._protocolClassesForTesting = [StubURLProtocol.self]
    }

    deinit {
        StubURLProtocol.reset()
        ModelLocation._supportDirectoryOverrideForTesting = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Mirror chain

    /// Pinned in case the Y5 rewrite regressed the chain logic.
    @Test func mirrorChainAdvancesOn404() async throws {
        let body = Data("hello-world-fixture".utf8)
        StubURLProtocol.responder = { _, callIndex in
            // First mirror returns 404; subsequent attempts return the body.
            if callIndex == 1 {
                return .response(status: 404, body: Data())
            }
            return .response(status: 200, body: body)
        }

        let descriptor = ModelDescriptor(
            fileName: ModelLocation.modelFileName,
            expectedSize: Int64(body.count),
            // Hash mismatch on purpose — we want to assert the chain reached
            // the verify step, not that the fixture matched a real hash.
            expectedSHA256: String(repeating: "0", count: 64)
        )
        downloader.start(descriptor: descriptor, mirrorPreference: .auto, localeCode: "en-US")
        try await waitForTerminalState()

        // Should have ended at integrity-failure (chain succeeded, but our
        // dummy hash doesn't match the body's actual SHA-256).
        guard case .failed(let reason) = downloader.state,
              case .integrity = reason
        else {
            Issue.record("Expected .integrity failure (chain reached verify), got \(downloader.state)")
            return
        }
        #expect(
            StubURLProtocol.callCount >= 2,
            "Mirror chain must have advanced past the 404 mirror"
        )
    }

    // MARK: - Streaming append + range resume (Y5's headline regression)

    /// Cross-launch resume: a previous run left `.partial` with N bytes
    /// (the bytes streaming-append put there mid-download). On the next
    /// `start()`, the request must carry `Range: bytes=N-` and a 206
    /// reply must be appended to the existing partial — *not* used to
    /// truncate-and-restart. This is exactly what was broken pre-Y5:
    /// bytes never made it to `.partial` until full completion, so the
    /// `Range:` path was effectively dead and every retry started from 0.
    @Test func resumesFromPartialViaRangeAcrossLaunches() async throws {
        let fullBody = Data((0..<256).map { UInt8($0 % 256) })
        let halfPoint = 128

        // Simulate the previous run's streaming-append leftovers.
        try Data(fullBody.prefix(halfPoint)).write(to: ModelLocation.modelPartialURL)
        let expectedHash = ModelIntegrity.sha256HexOfData(fullBody)

        // Also write the matching .partial.meta — without it,
        // tryResumeFromMeta fails and the downloader cleans the partial
        // before the first request. (Real-world meta is written on the
        // first mirror attempt of the prior run.)
        let meta: [String: Any] = [
            "url": "https://stub.invalid/model.gguf",
            "expected_size": fullBody.count,
            "expected_sha256": expectedHash,
            "started_at": ISO8601DateFormatter().string(from: Date()),
        ]
        try JSONSerialization
            .data(withJSONObject: meta, options: [])
            .write(to: ModelLocation.modelPartialMetaURL)

        let observed = ObservedRange()
        StubURLProtocol.responder = { request, _ in
            if let range = request.value(forHTTPHeaderField: "Range") {
                observed.set(Self.parseRangeStart(range))
            }
            return .response(status: 206, body: Data(fullBody.suffix(from: halfPoint)))
        }

        let descriptor = ModelDescriptor(
            fileName: ModelLocation.modelFileName,
            expectedSize: Int64(fullBody.count),
            expectedSHA256: expectedHash
        )
        downloader.start(descriptor: descriptor, mirrorPreference: .auto, localeCode: "en-US")
        try await waitForTerminalState()

        #expect(downloader.state == .done, "Expected .done; got \(downloader.state)")
        #expect(
            observed.get() == Int64(halfPoint),
            "Resume must request bytes=N- where N is the partial-file size, not 0"
        )

        let finalData = try Data(contentsOf: ModelLocation.modelURL)
        #expect(
            finalData == fullBody,
            "Streaming-append + range-resume must reconstruct the full body, not just the second half"
        )
    }

    // MARK: - Integrity rejection

    @Test func integrityMismatchDeletesFinalFile() async throws {
        let body = Data("integrity-mismatch-fixture".utf8)
        StubURLProtocol.responder = { _, _ in .response(status: 200, body: body) }

        let descriptor = ModelDescriptor(
            fileName: ModelLocation.modelFileName,
            expectedSize: Int64(body.count),
            expectedSHA256: String(repeating: "f", count: 64)  // won't match
        )
        downloader.start(descriptor: descriptor, mirrorPreference: .auto, localeCode: "en-US")
        try await waitForTerminalState()

        guard case .failed(.integrity(_, let expected)) = downloader.state else {
            Issue.record("Expected .integrity failure, got \(downloader.state)")
            return
        }
        #expect(expected == descriptor.expectedSHA256)
        #expect(
            !FileManager.default.fileExists(atPath: ModelLocation.modelURL.path),
            "Integrity mismatch must delete the bad file rather than leave it where future warmUps would re-load it"
        )
    }

    // MARK: - Helpers

    private func waitForTerminalState(timeout: TimeInterval = 10.0) async throws {
        try await pollUntil(timeout: timeout) {
            switch self.downloader.state {
            case .done, .failed, .cancelled, .idle: return true
            default: return false
            }
        }
    }

    private func pollUntil(
        timeout: TimeInterval,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw NSError(domain: "test", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "Predicate never became true within \(timeout)s",
        ])
    }

    private static func parseRangeStart(_ header: String) -> Int64? {
        // "bytes=128-" → 128
        guard let eq = header.split(separator: "=").last else { return nil }
        let start = eq.split(separator: "-").first ?? ""
        return Int64(start)
    }
}

// MARK: - Convenience: hash a Data blob via ModelIntegrity

extension ModelIntegrity {
    /// Test-only helper: write the bytes to a temp file and hash via the
    /// production code path. Keeps the assertions honest — we're measuring
    /// the same digest function the production verifier uses.
    static func sha256HexOfData(_ data: Data) -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hash-\(UUID().uuidString).bin")
        try? data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return (try? sha256Hex(of: url)) ?? ""
    }
}

/// Small lock-protected box so the URLProtocol stub closure (running on
/// the URLSession's delegate queue) can hand a value back to the test
/// (running on `@MainActor`).
private final class ObservedRange: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int64?
    func set(_ v: Int64?) { lock.lock(); _value = v; lock.unlock() }
    func get() -> Int64? { lock.lock(); defer { lock.unlock() }; return _value }
}

// MARK: - URLProtocol stub

/// Captures HTTP requests issued by `ModelDownloader` and replies with
/// canned responses. Reset between tests via `reset()`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    enum Reply {
        case response(status: Int, body: Data)
        case partialThenError(status: Int, body: Data, error: NSError)
        case networkError(NSError)
    }

    /// Receives the `URLRequest` and a 1-based call index; decides what to
    /// send. The index lets a single test vary the response across mirror
    /// attempts.
    nonisolated(unsafe) static var responder: ((URLRequest, Int) -> Reply)?
    nonisolated(unsafe) static var callCount = 0
    private static let lock = NSLock()

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responder = nil
        callCount = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let snapshotRequest = request
        let reply: Reply = {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            Self.callCount += 1
            return Self.responder?(snapshotRequest, Self.callCount) ?? .networkError(
                NSError(domain: "StubURLProtocol", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "no responder configured",
                ])
            )
        }()

        switch reply {
        case .response(let status, let body):
            sendHeaders(url: snapshotRequest.url!, status: status, body: body)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocolDidFinishLoading(self)

        case .partialThenError(let status, let body, let error):
            sendHeaders(url: snapshotRequest.url!, status: status, body: body)
            if !body.isEmpty {
                client?.urlProtocol(self, didLoad: body)
            }
            client?.urlProtocol(self, didFailWithError: error)

        case .networkError(let err):
            client?.urlProtocol(self, didFailWithError: err)
        }
    }

    override func stopLoading() { /* no-op */ }

    private func sendHeaders(url: URL, status: Int, body: Data) {
        let headers: [String: String] = [
            "Content-Length": "\(body.count)",
        ]
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
}
