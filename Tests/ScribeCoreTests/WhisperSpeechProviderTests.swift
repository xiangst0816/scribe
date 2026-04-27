import XCTest
import WhisperKit
@testable import ScribeCore

final class WhisperSpeechProviderTests: XCTestCase {

    // MARK: - filterHallucinatedSegments

    func testFilterDropsHighNoSpeechProbSegments() {
        let segments = [
            seg(text: "hello", noSpeechProb: 0.1),
            seg(text: "Thank you for watching.", noSpeechProb: 0.95),
            seg(text: "world", noSpeechProb: 0.4),
        ]
        let kept = WhisperSpeechProvider.filterHallucinatedSegments(segments)
        XCTAssertEqual(kept.map { $0.text }, ["hello", "world"])
    }

    func testFilterKeepsAllWhenAllConfident() {
        let segments = [
            seg(text: "hello", noSpeechProb: 0.0),
            seg(text: "world", noSpeechProb: 0.59),
        ]
        let kept = WhisperSpeechProvider.filterHallucinatedSegments(segments)
        XCTAssertEqual(kept.count, 2)
    }

    func testFilterDropsAllWhenAllSilent() {
        let segments = [
            seg(text: "Thank you.", noSpeechProb: 0.99),
            seg(text: "감사합니다.", noSpeechProb: 0.92),
        ]
        let kept = WhisperSpeechProvider.filterHallucinatedSegments(segments)
        XCTAssertTrue(kept.isEmpty)
    }

    // Boundary: cutoff is strict `<`, so exactly-at-cutoff is dropped.
    func testFilterDropsSegmentExactlyAtCutoff() {
        let segments = [seg(text: "edge", noSpeechProb: 0.6)]
        let kept = WhisperSpeechProvider.filterHallucinatedSegments(segments)
        XCTAssertTrue(kept.isEmpty)
    }

    // MARK: - cleanupTranscript

    func testCleanupStripsBracketedNonSpeech() {
        let cleaned = WhisperSpeechProvider.cleanupTranscript("hello [Music] world")
        XCTAssertEqual(cleaned.trimmingCharacters(in: .whitespaces), "hello world")
    }

    func testCleanupStripsChineseBracketedAnnotations() {
        let cleaned = WhisperSpeechProvider.cleanupTranscript("你好（笑）世界")
        XCTAssertEqual(cleaned, "你好世界")
    }

    func testCleanupStripsBareMusicNotes() {
        let cleaned = WhisperSpeechProvider.cleanupTranscript("hi ♪♪♪ there")
        XCTAssertEqual(cleaned.trimmingCharacters(in: .whitespaces), "hi  there".replacingOccurrences(of: "  ", with: " "))
    }

    // Critical regression: real "Thank you" must NOT be stripped — that was the
    // explicit reason we use `noSpeechProb` filtering instead of a phrase blocklist.
    func testCleanupLeavesRealThankYouAlone() {
        let cleaned = WhisperSpeechProvider.cleanupTranscript("Thank you for the help")
        XCTAssertEqual(cleaned, "Thank you for the help")
    }

    // MARK: - VAD pre-filter (sanity checks on the WhisperKit API we depend on)

    func testEnergyVADReportsNoSpeechOnSilence() {
        let oneSecondSilence = [Float](repeating: 0, count: WhisperKit.sampleRate)
        let chunks = EnergyVAD().calculateActiveChunks(in: oneSecondSilence)
        XCTAssertTrue(chunks.isEmpty, "VAD should find no active chunks in pure silence")
    }

    func testEnergyVADDetectsLoudTone() {
        // 1s of a 440Hz sine wave at amplitude 0.5 — well above the default 0.02 energy threshold.
        let sampleRate = WhisperKit.sampleRate
        let samples: [Float] = (0..<sampleRate).map { i in
            0.5 * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
        }
        let chunks = EnergyVAD().calculateActiveChunks(in: samples)
        XCTAssertFalse(chunks.isEmpty, "VAD should detect a loud sine wave as speech-like activity")
    }

    // MARK: - Helpers

    private func seg(text: String, noSpeechProb: Float) -> TranscriptionSegment {
        TranscriptionSegment(text: text, noSpeechProb: noSpeechProb)
    }
}
