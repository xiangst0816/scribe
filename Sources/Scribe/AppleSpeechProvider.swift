import AVFoundation
import Speech

final class AppleSpeechProvider: SpeechProvider {
    var onAudioLevel: ((Float) -> Void)?
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onLocaleUnavailable: ((String) -> Void)?

    var isReady: Bool { speechRecognizer?.isAvailable == true }

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?

    private var lastPartialText = ""
    private var finalFallbackTimer: Timer?
    private var didDeliverResult = false

    var locale: Locale {
        didSet {
            speechRecognizer = SFSpeechRecognizer(locale: locale)
            if speechRecognizer == nil {
                onLocaleUnavailable?("Speech recognition is not supported for \(locale.identifier). Please check that the language is downloaded in System Settings → General → Keyboard → Dictation.")
            }
        }
    }

    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.locale = locale
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)
    }

    static func requestPermissions(completion: @escaping (Bool, String?) -> Void) {
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
        recognitionTask?.cancel()
        recognitionTask = nil
        lastPartialText = ""
        didDeliverResult = false

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?("Speech recognizer not available for \(locale.identifier)")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lastPartialText = text
                if result.isFinal {
                    self.deliverFinal(text)
                } else {
                    // Stream interim text out so the overlay can show what
                    // the user is saying as they speak.
                    self.onPartialResult?(text)
                }
            }
            if let error, (error as NSError).code != 216 {
                self.onError?(error.localizedDescription)
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            self?.emitAudioLevel(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?("Audio engine failed: \(error.localizedDescription)")
            cleanup()
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()

        // SFSpeechRecognizer sometimes never produces isFinal; fall back after 2s.
        finalFallbackTimer?.invalidate()
        finalFallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self, !self.didDeliverResult else { return }
            self.deliverFinal(self.lastPartialText)
        }
    }

    func cancel() {
        finalFallbackTimer?.invalidate()
        finalFallbackTimer = nil
        recognitionTask?.cancel()
        cleanup()
    }

    // MARK: - Private

    private func deliverFinal(_ text: String) {
        guard !didDeliverResult else { return }
        didDeliverResult = true
        finalFallbackTimer?.invalidate()
        finalFallbackTimer = nil
        cleanup()
        onFinalResult?(text)
    }

    private func cleanup() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func emitAudioLevel(_ buffer: AVAudioPCMBuffer) {
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
            self?.onAudioLevel?(normalized)
        }
    }
}
