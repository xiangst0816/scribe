import AVFoundation
import Foundation
import WhisperKit

final class WhisperSpeechProvider: SpeechProvider {
    var onAudioLevel: ((Float) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((String) -> Void)?

    /// ISO-639-1 language code (e.g. "zh", "en"). nil = auto-detect.
    var languageHint: String?

    var isReady: Bool { ModelManager.shared.loadedKit != nil }

    private var audioProcessor: AudioProcessor?
    private var levelTimer: Timer?
    private var isRecording = false

    func start() {
        guard let _ = ModelManager.shared.loadedKit else {
            onError?("Voice model is not loaded yet.")
            return
        }

        let processor = AudioProcessor()
        audioProcessor = processor
        isRecording = true

        do {
            try processor.startRecordingLive(inputDeviceID: nil) { [weak self] _ in
                // Buffer is appended internally; we just need to keep recording alive.
                _ = self
            }
        } catch {
            onError?("Microphone failed: \(error.localizedDescription)")
            audioProcessor = nil
            isRecording = false
            return
        }

        // Drive the waveform from `relativeEnergy` updates.
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let processor = self.audioProcessor else { return }
            let level = processor.relativeEnergy.last ?? 0
            self.onAudioLevel?(level)
        }
    }

    func stop() {
        guard isRecording, let processor = audioProcessor else { return }
        isRecording = false

        levelTimer?.invalidate()
        levelTimer = nil
        processor.stopRecording()

        let samples = Array(processor.audioSamples)
        audioProcessor = nil

        guard !samples.isEmpty else {
            onFinalResult?("")
            return
        }

        Task {
            await transcribe(samples: samples)
        }
    }

    func cancel() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioProcessor?.stopRecording()
        audioProcessor = nil
        isRecording = false
    }

    // MARK: - Private

    private func transcribe(samples: [Float]) async {
        guard let kit = ModelManager.shared.loadedKit else {
            await deliver(error: "Voice model is not loaded.")
            return
        }

        do {
            let options = DecodingOptions(
                verbose: false,
                task: .transcribe,
                language: languageHint,
                temperature: 0,
                topK: 5,
                usePrefillPrompt: true,
                detectLanguage: languageHint == nil,
                skipSpecialTokens: true,
                withoutTimestamps: true
            )
            let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
            let text = results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            await deliver(text: text)
        } catch {
            await deliver(error: error.localizedDescription)
        }
    }

    @MainActor
    private func deliver(text: String) {
        onFinalResult?(text)
    }

    @MainActor
    private func deliver(error message: String) {
        onError?(message)
    }
}
