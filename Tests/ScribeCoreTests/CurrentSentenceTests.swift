import XCTest
@testable import ScribeCore

/// Covers `OverlayPanel.currentSentence` — the heuristic that pulls just the
/// sentence the user is currently saying out of the running interim transcript,
/// so the floating pill above the capsule doesn't grow forever.
final class CurrentSentenceTests: XCTestCase {

    // No terminator yet — the user is still mid-sentence, show everything.
    func testReturnsWholeTextWhenNoTerminator() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: "我今天想说"), "我今天想说")
    }

    // After a Chinese full stop, only the new sentence should show.
    func testReturnsTextAfterChineseFullStop() {
        let result = OverlayPanel.currentSentence(from: "第一句话。第二句进行中")
        XCTAssertEqual(result, "第二句进行中")
    }

    // ASCII period in English speech.
    func testReturnsTextAfterEnglishPeriod() {
        let result = OverlayPanel.currentSentence(from: "First sentence. Second one in progress")
        XCTAssertEqual(result, "Second one in progress")
    }

    // Question and exclamation marks count too.
    func testRecognizesQuestionAndExclamation() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: "你好吗？我很好"), "我很好")
        XCTAssertEqual(OverlayPanel.currentSentence(from: "Wow! Now what"), "Now what")
    }

    // If the sentence just ended (terminator is the last char), the user is
    // between sentences — show the just-completed one rather than going blank.
    func testKeepsLastSentenceWhenTerminatorIsAtEnd() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: "句一。句二完成。"), "句二完成。")
    }

    // Single completed sentence with no prior text — show it instead of empty.
    func testKeepsSoleSentenceWhenItIsTerminated() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: "Hello world."), "Hello world.")
    }

    // Hesitations / fillers stay — they're part of the current sentence.
    func testPreservesFillersAndPauses() {
        let raw = "First done. um, the next thing is, uh"
        XCTAssertEqual(OverlayPanel.currentSentence(from: raw), "um, the next thing is, uh")
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: "   hi there   "), "hi there")
    }

    func testEmptyInput() {
        XCTAssertEqual(OverlayPanel.currentSentence(from: ""), "")
    }
}
