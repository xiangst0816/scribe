import Foundation

/// Downloads the local-polish GGUF (Gemma 4 E2B) with mirror fallback,
/// cross-launch resume, and SHA-256 verification. Implements the failure
/// matrix in design doc §4.4.
///
/// Threading: not `@MainActor`. URLSession delegate callbacks fire on the
/// private operation queue we hand the session; public API is safe to call
/// from any actor and `stateChanged` is delivered on the main queue.
///
/// Resume mechanism (Y5): we use a `URLSessionDataTask` and append received
/// chunks directly to `.partial`, so on cancel/error the bytes that arrived
/// are preserved on disk. The next `start()` reads `.partial`'s size and
/// sends `Range: bytes=N-` to resume across launches and across mirrors.
/// (The pre-Y5 implementation used `URLSessionDownloadTask`, which only
/// produced a file at the moment of full completion — bytes received
/// before a cancel/error were never written to `.partial`, so the
/// "Range from .partial size" path was effectively dead and every retry
/// started from byte 0. The orphan `<file>.partial.resumeData` was
/// written but never read.)
final class ModelDownloader: NSObject {
    static let shared = ModelDownloader()

    enum State: Equatable {
        case idle
        case downloading(bytesReceived: Int64, totalBytes: Int64)
        case verifying
        case done
        case failed(reason: FailureReason)
        case cancelled

        /// Hint for the UI: should "Retry" be shown?
        var isRetriable: Bool {
            switch self {
            case .failed(let r): return r.isRetriable
            case .cancelled:     return true
            default:             return false
            }
        }
    }

    enum FailureReason: Equatable {
        case unreachable                   // every mirror failed to connect
        case mirrorErrors([Int])           // every mirror returned 4xx/5xx
        case integrity(actual: String, expected: String)
        case notPinned                     // descriptor has no hash to verify against
        case diskFull
        case ioError(String)
        case unknown(String)

        var isRetriable: Bool {
            switch self {
            case .integrity, .notPinned: return false
            default:                      return true
            }
        }
    }

    /// Last-known download state. Read from any thread.
    var state: State {
        stateLock.lock(); defer { stateLock.unlock() }
        return _state
    }

    /// State change observer; invoked on the **main thread** so UI code can
    /// be plain. Set after init, before `start`.
    var stateChanged: ((State) -> Void)?

    // MARK: - Private state

    private var _state: State = .idle
    private let stateLock = NSLock()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.yetone.Scribe.ModelDownloader"
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60 * 4
        // Custom URLSessions don't pick up classes registered with
        // `URLProtocol.registerClass(_:)` — that registration only applies
        // to the shared session and `NSURLConnection`. So tests have to
        // explicitly inject their stub here. Prepend (rather than append)
        // so the stub wins over any built-in handlers for the same scheme.
        if !_protocolClassesForTesting.isEmpty {
            cfg.protocolClasses = _protocolClassesForTesting + (cfg.protocolClasses ?? [])
        }
        return URLSession(configuration: cfg, delegate: self, delegateQueue: queue)
    }()

    /// Test-only seam — production code never sets this. `ModelDownloaderTests`
    /// installs `StubURLProtocol` here before calling `start(...)`.
    /// Underscore-prefixed by convention.
    var _protocolClassesForTesting: [AnyClass] = []

    private var descriptor: ModelDescriptor?
    private var mirrorChain: [ModelMirror] = []
    private var mirrorIndex = 0
    private var currentTask: URLSessionDataTask?
    private var totalBytesExpected: Int64 = 0
    private var failedStatusCodes: [Int] = []
    private var manualCancelInFlight = false

    /// Open during reception so each `didReceive Data` call can append
    /// without re-opening the file. Closed in `didCompleteWithError`,
    /// `cancel()`, and the 416 short-circuit. The handle owns the only
    /// write position into `.partial` while a task is active.
    private var partialFileHandle: FileHandle?

    /// Set by the response-handler when it elects to short-circuit a task
    /// (e.g. 4xx → next mirror, 416 → already complete) so the
    /// subsequent `didCompleteWithError(NSURLErrorCancelled)` doesn't
    /// re-handle the same task.
    private var responseShortCircuit: ResponseShortCircuit = .none

    private enum ResponseShortCircuit {
        case none
        case advancedToNextMirror   // 4xx/5xx — already incremented mirrorIndex + restarted
        case treatAsComplete         // 416 — already moved + verifying
    }

    // MARK: - Public API

    /// Begin (or resume) downloading. Idempotent if a download is already in
    /// flight for the same descriptor.
    func start(
        descriptor: ModelDescriptor,
        mirrorPreference: ModelMirrorPreference,
        localeCode: String
    ) {
        if case .downloading = state { return }

        ModelLocation.ensureModelsDirectoryExists()

        // If we already have a finalised file that matches the descriptor,
        // verify and short-circuit — no need to re-download.
        if FileManager.default.fileExists(atPath: ModelLocation.modelURL.path) {
            self.descriptor = descriptor
            transition(to: .verifying)
            verifyAndFinalize(at: ModelLocation.modelURL)
            return
        }

        self.descriptor = descriptor
        self.mirrorChain = mirrorPreference.fallbackChain(forLocaleCode: localeCode)
        self.mirrorIndex = 0
        self.failedStatusCodes = []
        self.totalBytesExpected = descriptor.expectedSize
        self.manualCancelInFlight = false

        // If we have a `.partial.meta` from a prior run AND it matches the
        // current descriptor, try to resume; otherwise start fresh.
        if !tryResumeFromMeta(for: descriptor) {
            cleanPartialFiles()
        }
        startNextMirror()
    }

    /// Stop the current download. State transitions to `.cancelled`. The
    /// `.partial` file is **kept** so the user can resume next time — design
    /// doc §4.3 (NotDownloaded state requires deleting partials, but cancel
    /// is an explicit user action that wants to preserve progress).
    ///
    /// Y5: we no longer ask URLSession for resume data — the bytes already
    /// live in `.partial` because of streaming-append, so the next `start()`
    /// can resume via a `Range:` header against the file's size.
    func cancel() {
        manualCancelInFlight = true
        currentTask?.cancel()
        currentTask = nil
        try? partialFileHandle?.close()
        partialFileHandle = nil
        transition(to: .cancelled)
    }

    /// Wipe everything — used by "delete and re-download" UX when the model
    /// file is corrupt or stale. NOT called automatically.
    func purge() {
        cancel()
        try? FileManager.default.removeItem(at: ModelLocation.modelURL)
        cleanPartialFiles()
        transition(to: .idle)
    }

    // MARK: - Mirror chain

    private func startNextMirror() {
        guard let descriptor else {
            transition(to: .failed(reason: .unknown("no descriptor")))
            return
        }
        guard mirrorIndex < mirrorChain.count else {
            // Every mirror failed.
            if !failedStatusCodes.isEmpty {
                transition(to: .failed(reason: .mirrorErrors(failedStatusCodes)))
            } else {
                transition(to: .failed(reason: .unreachable))
            }
            return
        }
        let mirror = mirrorChain[mirrorIndex]
        var req = URLRequest(url: mirror.modelURL)
        req.httpMethod = "GET"

        // Resume from existing .partial if present. Y5: this Range header is
        // now actually load-bearing — `.partial` accumulates live across the
        // download lifetime, so a partial download truly resumes from the
        // last received byte (within and across launches, within and across
        // mirrors).
        let partialURL = ModelLocation.modelPartialURL
        let existingPartialBytes: Int64
        if let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            existingPartialBytes = size
            req.setValue("bytes=\(size)-", forHTTPHeaderField: "Range")
        } else {
            existingPartialBytes = 0
        }

        responseShortCircuit = .none
        let task = session.dataTask(with: req)
        task.taskDescription = String(mirror.rawValue)
        currentTask = task
        // Keep the existing partial bytes visible in progress immediately —
        // otherwise the UI flashes back to 0% on each mirror retry.
        transition(to: .downloading(
            bytesReceived: existingPartialBytes,
            totalBytes: totalBytesExpected
        ))
        writePartialMeta(descriptor: descriptor)
        task.resume()
    }

    // MARK: - Resume from meta

    private func tryResumeFromMeta(for descriptor: ModelDescriptor) -> Bool {
        guard let raw = try? Data(contentsOf: ModelLocation.modelPartialMetaURL),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let savedSize = (json["expected_size"] as? NSNumber)?.int64Value,
              let savedHash = json["expected_sha256"] as? String,
              savedSize == descriptor.expectedSize,
              savedHash == descriptor.expectedSHA256
        else {
            return false
        }
        // Meta matches — keep `.partial` in place; `startNextMirror` will
        // append to it via Range.
        return true
    }

    private func writePartialMeta(descriptor: ModelDescriptor) {
        let dict: [String: Any] = [
            "url":              mirrorChain[mirrorIndex].modelURL.absoluteString,
            "expected_size":    descriptor.expectedSize,
            "expected_sha256":  descriptor.expectedSHA256,
            "started_at":       ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]) {
            try? data.write(to: ModelLocation.modelPartialMetaURL, options: .atomic)
        }
    }

    private func cleanPartialFiles() {
        let fm = FileManager.default
        try? fm.removeItem(at: ModelLocation.modelPartialURL)
        try? fm.removeItem(at: ModelLocation.modelPartialMetaURL)
        // Pre-Y5 also cleaned `<file>.partial.resumeData`; that path is
        // gone now. If a pre-upgrade install left one behind, it's an
        // orphan — harmless and small.
    }

    // MARK: - Verify & finalise

    private func verifyAndFinalize(at fileURL: URL) {
        guard let descriptor else {
            transition(to: .failed(reason: .unknown("no descriptor")))
            return
        }
        let result = ModelIntegrity.verify(fileURL: fileURL, against: descriptor)
        switch result {
        case .match:
            // Finalised file is at the canonical path; clean up stragglers.
            cleanPartialFiles()
            transition(to: .done)
            // Notify LocalPolishService so it flips to ready.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .polishAvailabilityChanged, object: nil)
            }
        case .mismatch(let actual, let expected):
            // Per design doc §4.4: don't retry, don't repair — delete and fail.
            try? FileManager.default.removeItem(at: fileURL)
            cleanPartialFiles()
            transition(to: .failed(reason: .integrity(actual: actual, expected: expected)))
        case .notPinned:
            // Developer build with no canonical hash. Refuse to mark ready;
            // the user must place the file manually until we ship a pinned
            // descriptor.
            transition(to: .failed(reason: .notPinned))
        case .ioError(let s):
            transition(to: .failed(reason: .ioError(s)))
        }
    }

    /// Move `.partial` to the canonical model URL and verify. Used both
    /// from the natural completion path (didCompleteWithError with no
    /// error) and the 416 short-circuit ("we already have everything").
    private func finalizePartialAfterDownload() {
        try? partialFileHandle?.close()
        partialFileHandle = nil

        let dest = ModelLocation.modelPartialURL
        let finalURL = ModelLocation.modelURL
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: finalURL.path) {
                try fm.removeItem(at: finalURL)
            }
            try fm.moveItem(at: dest, to: finalURL)
        } catch {
            transition(to: .failed(reason: .ioError(error.localizedDescription)))
            return
        }
        transition(to: .verifying)
        verifyAndFinalize(at: finalURL)
    }

    // MARK: - State transitions

    private func transition(to new: State) {
        stateLock.lock()
        _state = new
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.stateChanged?(new)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension ModelDownloader: URLSessionDataDelegate {

    /// Inspect the response headers. Y5: 4xx/5xx fail this mirror and we
    /// move to the next; 416 means our `Range:` was past the file (so
    /// `.partial` already holds the whole thing) and we short-circuit
    /// to verify; 2xx accepts the body and opens the file handle for
    /// streaming append.
    ///
    /// **Mirror-advancement and finalization are deliberately deferred
    /// to `didCompleteWithError`** rather than fired synchronously here.
    /// URLSession may fire this task's `didCompleteWithError` after a
    /// later task has already started — if we'd already advanced the
    /// mirror index from inside `didReceive response`, the late completion
    /// would advance it a second time and skip the wrong mirror.
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            // Not HTTP (file://, ftp://) — refuse and fail this mirror.
            failedStatusCodes.append(0)
            responseShortCircuit = .advancedToNextMirror
            completionHandler(.cancel)
            return
        }
        let code = http.statusCode

        if code == 416 {
            // Server says our Range start is past the file — we already
            // have the whole thing in `.partial`. didCompleteWithError will
            // promote .partial to final and verify.
            responseShortCircuit = .treatAsComplete
            completionHandler(.cancel)
            return
        }

        if !(200..<300).contains(code) {
            failedStatusCodes.append(code)
            responseShortCircuit = .advancedToNextMirror
            completionHandler(.cancel)
            return
        }

        // 2xx — open the partial file handle for append. For 200 we may
        // need to wipe an existing partial (the server gave us the whole
        // file, not a continuation); for 206 we keep what's there and
        // append at end.
        do {
            try openPartialForAppend(isPartialContent: code == 206)
        } catch {
            transition(to: .failed(reason: .ioError(error.localizedDescription)))
            responseShortCircuit = .advancedToNextMirror
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    /// Append each received chunk to `.partial` and update progress.
    /// Disk-full surfaces here (write throw) — handled directly so the
    /// task doesn't churn through more mirrors with the same problem.
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive data: Data) {
        guard let handle = partialFileHandle else {
            // Shouldn't happen — the response-handler opens the file before
            // returning .allow. Defend anyway.
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch let err as NSError where err.code == NSFileWriteOutOfSpaceError {
            transition(to: .failed(reason: .diskFull))
            currentTask?.cancel()
            return
        } catch {
            transition(to: .failed(reason: .ioError(error.localizedDescription)))
            currentTask?.cancel()
            return
        }

        let received: Int64
        if let offset = try? handle.offset() {
            received = Int64(offset)
        } else {
            // Fall back to file system size if offset() throws (rare).
            let attrs = try? FileManager.default.attributesOfItem(atPath: ModelLocation.modelPartialURL.path)
            received = (attrs?[.size] as? Int64) ?? 0
        }
        transition(to: .downloading(
            bytesReceived: received,
            totalBytes: totalBytesExpected
        ))
    }

    /// Final delegate call. Branches:
    ///   - response-handler set `.advancedToNextMirror` (4xx/5xx): advance
    ///     the mirror index here (deferred from `didReceive response` to
    ///     avoid the double-advance race when a late completion arrives
    ///     after the *next* task has already started).
    ///   - response-handler set `.treatAsComplete` (416): `.partial`
    ///     already holds the file; finalize.
    ///   - the user called `cancel()`: state is already `.cancelled`.
    ///   - genuine network error: try the next mirror; bytes already in
    ///     `.partial` get reused via `Range:` on the next attempt.
    ///   - no error: download completed naturally; finalize.
    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {

        let priorShortCircuit = responseShortCircuit
        responseShortCircuit = .none

        // Always close the file handle on completion — every branch below
        // either finalizes (which closes again, harmless) or advances to a
        // new task (which will open a fresh handle).
        try? partialFileHandle?.close()
        partialFileHandle = nil

        switch priorShortCircuit {
        case .advancedToNextMirror:
            mirrorIndex += 1
            startNextMirror()
            return
        case .treatAsComplete:
            finalizePartialAfterDownload()
            return
        case .none:
            break
        }

        if manualCancelInFlight {
            manualCancelInFlight = false
            return
        }

        if let error {
            let nserror = error as NSError
            if nserror.code == NSFileWriteOutOfSpaceError {
                transition(to: .failed(reason: .diskFull))
                return
            }
            // Network-class errors → try the next mirror. The bytes that
            // *did* arrive remain in `.partial`, and the next attempt will
            // resume from there via `Range:`.
            mirrorIndex += 1
            startNextMirror()
            return
        }

        // No error — all bytes received. Finalize.
        finalizePartialAfterDownload()
    }

    /// Open `.partial` for append. For a 200 response that arrives when we
    /// already have a `.partial` on disk, the server sent the whole file
    /// (didn't honour our Range:), so we have to truncate and start over to
    /// avoid stitching mismatched bytes. For 206 the existing bytes are
    /// preserved and we seek to end.
    private func openPartialForAppend(isPartialContent: Bool) throws {
        let fm = FileManager.default
        let url = ModelLocation.modelPartialURL

        if !isPartialContent {
            // 200: discard whatever we had and start from byte 0.
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
            fm.createFile(atPath: url.path, contents: nil)
        } else if !fm.fileExists(atPath: url.path) {
            // 206 with no existing file is unusual but defensible — create
            // empty and treat as fresh.
            fm.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        partialFileHandle = handle
    }
}
