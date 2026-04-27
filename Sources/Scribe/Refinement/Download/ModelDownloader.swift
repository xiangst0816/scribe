import Foundation

/// Downloads the local-polish GGUF (Gemma 4 E2B) with mirror fallback,
/// cross-launch resume,
/// and SHA-256 verification. Implements the failure matrix in design doc §4.4.
///
/// Threading: not `@MainActor`. URLSession delegate callbacks fire on the
/// private operation queue we hand the session; public API is safe to call
/// from any actor and `stateChanged` is delivered on the main queue.
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
        return URLSession(configuration: cfg, delegate: self, delegateQueue: queue)
    }()

    private var descriptor: ModelDescriptor?
    private var mirrorChain: [ModelMirror] = []
    private var mirrorIndex = 0
    private var currentTask: URLSessionDownloadTask?
    private var totalBytesExpected: Int64 = 0
    private var failedStatusCodes: [Int] = []
    private var manualCancelInFlight = false

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
        // current descriptor, try to resume; otherwise start fresh from the
        // first mirror.
        let resumed = tryResumeFromMeta(for: descriptor)
        if !resumed {
            cleanPartialFiles()
            startNextMirror()
        }
    }

    /// Stop the current download. State transitions to `.cancelled`. The
    /// `.partial` file is **kept** so the user can resume next time — design
    /// doc §4.3 (NotDownloaded state requires deleting partials, but cancel
    /// is an explicit user action that wants to preserve progress).
    func cancel() {
        manualCancelInFlight = true
        currentTask?.cancel(byProducingResumeData: { [weak self] data in
            guard let self else { return }
            if let data { self.persistResumeData(data) }
            self.transition(to: .cancelled)
        })
        currentTask = nil
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

        // Resume from existing .partial if present.
        let partialURL = ModelLocation.modelPartialURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: partialURL.path),
           let size = attrs[.size] as? Int64, size > 0 {
            req.setValue("bytes=\(size)-", forHTTPHeaderField: "Range")
        }

        let task = session.downloadTask(with: req)
        task.taskDescription = String(mirror.rawValue)
        currentTask = task
        transition(to: .downloading(bytesReceived: 0, totalBytes: totalBytesExpected))
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
        // The .partial file may still exist; re-issue the GET with Range.
        startNextMirror()
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

    private func persistResumeData(_ data: Data) {
        try? data.write(to: ModelLocation.modelPartialURL.appendingPathExtension("resumeData"),
                        options: .atomic)
    }

    private func cleanPartialFiles() {
        let fm = FileManager.default
        try? fm.removeItem(at: ModelLocation.modelPartialURL)
        try? fm.removeItem(at: ModelLocation.modelPartialMetaURL)
        try? fm.removeItem(at: ModelLocation.modelPartialURL.appendingPathExtension("resumeData"))
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

// MARK: - URLSessionDownloadDelegate

extension ModelDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytesExpected
        // For Range responses, totalBytesExpectedToWrite is just the remaining
        // bytes; combine with whatever the .partial already had on disk.
        let already = (try? FileManager.default.attributesOfItem(atPath: ModelLocation.modelPartialURL.path))?[.size] as? Int64 ?? 0
        let observed = already + totalBytesWritten
        transition(to: .downloading(bytesReceived: observed, totalBytes: max(total, totalBytesExpected)))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Inspect the HTTP response to detect mirror errors masked by a
        // successful "download" of an HTML 404 page.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) && http.statusCode != 416 {
            failedStatusCodes.append(http.statusCode)
            mirrorIndex += 1
            startNextMirror()
            return
        }

        // If we resumed via Range (206 Partial Content), append the new bytes
        // onto the existing .partial; otherwise, the new file IS the partial.
        let fm = FileManager.default
        let dest = ModelLocation.modelPartialURL
        do {
            if (downloadTask.response as? HTTPURLResponse)?.statusCode == 206,
               fm.fileExists(atPath: dest.path) {
                try appendContents(of: location, to: dest)
                try? fm.removeItem(at: location)
            } else {
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.moveItem(at: location, to: dest)
            }
        } catch let err as NSError where err.code == NSFileWriteOutOfSpaceError {
            transition(to: .failed(reason: .diskFull))
            return
        } catch {
            transition(to: .failed(reason: .ioError(error.localizedDescription)))
            return
        }

        // Promote .partial → final file, then verify.
        let finalURL = ModelLocation.modelURL
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

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }  // success path handled above
        if manualCancelInFlight {
            manualCancelInFlight = false
            return
        }
        let nserror = error as NSError
        // Disk-full surfaces here on some macOS versions even mid-stream.
        if nserror.code == NSFileWriteOutOfSpaceError {
            transition(to: .failed(reason: .diskFull))
            return
        }
        // Network-class errors → try the next mirror.
        mirrorIndex += 1
        startNextMirror()
    }

    /// Append-copy in 1 MiB chunks so we don't hold 1 GB in RAM.
    private func appendContents(of source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: destination.path) else {
            try fm.moveItem(at: source, to: destination)
            return
        }
        let inHandle = try FileHandle(forReadingFrom: source)
        defer { try? inHandle.close() }
        let outHandle = try FileHandle(forWritingTo: destination)
        defer { try? outHandle.close() }
        try outHandle.seekToEnd()
        let chunkSize = 1 << 20
        while autoreleasepool(invoking: {
            let chunk = inHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { return false }
            outHandle.write(chunk)
            return true
        }) { /* loop in autoreleasepool to bound memory */ }
    }
}
