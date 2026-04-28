import AVFoundation
import os
import Speech

/// One speech recognition attempt. Construct, configure callbacks, then `start()`.
/// Terminate with `stop()` (waits briefly for a final result) or `cancel()`
/// (drops any pending result).
///
/// Contract:
/// - `onTerminated` fires exactly once, on the main thread.
/// - All other callbacks also fire on the main thread.
/// - After `onTerminated` fires, no further callbacks fire.
/// - Sessions are single-use: a terminated session cannot be restarted.
final class AppleSpeechSession {
    enum Termination {
        case final(text: String)
        case cancelled
        case error(message: String)
    }

    var onAudioLevel: ((Float) -> Void)?
    var onPartial: ((String) -> Void)?
    var onTerminated: ((Termination) -> Void)?

    private enum State {
        case idle
        case running
        case stopping
        case terminated
    }

    private let locale: Locale
    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var state: State = .idle
    private var lastPartial = ""
    private var fallbackTimer: Timer?

    /// Last main-actor audio-level hop. The audio tap fires at the input
    /// device's natural rate (~100+ Hz on most devices); the waveform UI
    /// only needs ~30 Hz to look smooth. Throttling here keeps the dispatch
    /// cost (closure alloc + main-queue hop) bounded regardless of input rate.
    /// Read+written from the audio tap thread; `OSAllocatedUnfairLock`
    /// guards it without bringing in the dispatch overhead a serial queue
    /// would add.
    private let lastAudioEmitNanos = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    private static let audioEmitMinIntervalNanos: UInt64 = 33_000_000  // ~30 Hz

    /// Time after `stop()` to wait for a final result before delivering whatever
    /// partial text we have. SFSpeechRecognizer occasionally never delivers
    /// `isFinal`, so this is the safety net.
    private static let fallbackSeconds: TimeInterval = 2.0

    /// Error code emitted when a recognition request is canceled. Expected on
    /// `cancel()`; not surfaced as an error.
    private static let cancelledErrorCode = 216

    init(locale: Locale) {
        self.locale = locale
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    static func isLocaleSupported(_ locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale) != nil
    }

    static func requestPermissions(completion: @escaping (_ granted: Bool, _ message: String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                completion(true, nil)
                            } else {
                                completion(false, "Microphone access denied.\nGrant in System Settings → Privacy & Security → Microphone.")
                            }
                        }
                    }
                case .denied, .restricted:
                    completion(false, "Speech recognition denied.\nGrant in System Settings → Privacy & Security → Speech Recognition.")
                case .notDetermined:
                    completion(false, "Speech recognition permission not determined.")
                @unknown default:
                    completion(false, "Unknown speech recognition authorization status.")
                }
            }
        }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .idle else { return }

        guard let recognizer, recognizer.isAvailable else {
            asyncTerminate(.error(message: "Speech recognition unavailable for \(locale.identifier). Confirm the language is downloaded in System Settings → General → Keyboard → Dictation."))
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(macOS 13, *) { req.addsPunctuation = true }
        self.request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.handleRecognition(result: result, error: error)
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            self?.emitAudioLevel(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            asyncTerminate(.error(message: "Audio engine failed: \(error.localizedDescription)"))
            return
        }

        state = .running
    }

    /// User released the trigger key. Stop feeding audio and wait briefly
    /// for a final transcription before terminating.
    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .running else { return }
        state = .stopping
        teardownAudio()
        request?.endAudio()

        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: Self.fallbackSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.terminate(.final(text: self.lastPartial))
        }
    }

    /// Abandon the session without delivering a transcript.
    func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard state == .running || state == .stopping else { return }
        terminate(.cancelled)
    }

    // MARK: - Private

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard state == .running || state == .stopping else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            lastPartial = text
            if result.isFinal {
                terminate(.final(text: text))
                return
            }
            onPartial?(text)
        }

        if let error, (error as NSError).code != Self.cancelledErrorCode {
            terminate(.error(message: error.localizedDescription))
        }
    }

    /// Defer a synchronous start-time failure so the caller finishes wiring
    /// callbacks before the terminal one fires.
    private func asyncTerminate(_ reason: Termination) {
        DispatchQueue.main.async { [weak self] in
            self?.terminate(reason)
        }
    }

    private func terminate(_ reason: Termination) {
        guard state != .terminated else { return }
        state = .terminated

        fallbackTimer?.invalidate()
        fallbackTimer = nil
        task?.cancel()
        task = nil
        request = nil
        teardownAudio()

        onTerminated?(reason)
    }

    private func teardownAudio() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func emitAudioLevel(_ buffer: AVAudioPCMBuffer) {
        // Throttle gate first — RMS calc is cheap but the main-queue hop
        // and onAudioLevel closure aren't, and the audio tap fires at the
        // device's natural rate (typically 100+ Hz). UI only redraws at
        // ~60 fps and the smoothing in WaveformView keeps it visually
        // continuous from a 30 Hz input.
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldEmit = lastAudioEmitNanos.withLock { last in
            if now - last >= Self.audioEmitMinIntervalNanos {
                last = now
                return true
            }
            return false
        }
        guard shouldEmit else { return }

        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrtf(sum / Float(max(frameLength, 1)))
        let dB = 20 * log10(max(rms, 1e-6))
        let normalized = max(Float(0), min(Float(1), (dB + 50) / 40))
        DispatchQueue.main.async { [weak self] in
            guard let self, self.state == .running else { return }
            self.onAudioLevel?(normalized)
        }
    }
}
