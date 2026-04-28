import Testing
@testable import ScribeCore

/// Covers `OverlayPanel.currentSentence` — the heuristic that pulls just the
/// sentence the user is currently saying out of the running interim transcript,
/// so the floating pill above the capsule doesn't grow forever.
@Suite struct CurrentSentenceTests {

    // No terminator yet — the user is still mid-sentence, show everything.
    @Test func returnsWholeTextWhenNoTerminator() {
        #expect(OverlayPanel.currentSentence(from: "我今天想说") == "我今天想说")
    }

    // After a Chinese full stop, only the new sentence should show.
    @Test func returnsTextAfterChineseFullStop() {
        let result = OverlayPanel.currentSentence(from: "第一句话。第二句进行中")
        #expect(result == "第二句进行中")
    }

    // ASCII period in English speech.
    @Test func returnsTextAfterEnglishPeriod() {
        let result = OverlayPanel.currentSentence(from: "First sentence. Second one in progress")
        #expect(result == "Second one in progress")
    }

    // Question and exclamation marks count too.
    @Test func recognizesQuestionAndExclamation() {
        #expect(OverlayPanel.currentSentence(from: "你好吗？我很好") == "我很好")
        #expect(OverlayPanel.currentSentence(from: "Wow! Now what") == "Now what")
    }

    // If the sentence just ended (terminator is the last char), the user is
    // between sentences — show the just-completed one rather than going blank.
    @Test func keepsLastSentenceWhenTerminatorIsAtEnd() {
        #expect(OverlayPanel.currentSentence(from: "句一。句二完成。") == "句二完成。")
    }

    // Single completed sentence with no prior text — show it instead of empty.
    @Test func keepsSoleSentenceWhenItIsTerminated() {
        #expect(OverlayPanel.currentSentence(from: "Hello world.") == "Hello world.")
    }

    // Hesitations / fillers stay — they're part of the current sentence.
    @Test func preservesFillersAndPauses() {
        let raw = "First done. um, the next thing is, uh"
        #expect(OverlayPanel.currentSentence(from: raw) == "um, the next thing is, uh")
    }

    @Test func trimsLeadingAndTrailingWhitespace() {
        #expect(OverlayPanel.currentSentence(from: "   hi there   ") == "hi there")
    }

    @Test func emptyInput() {
        #expect(OverlayPanel.currentSentence(from: "") == "")
    }
}
