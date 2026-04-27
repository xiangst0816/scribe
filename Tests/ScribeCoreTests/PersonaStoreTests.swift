import XCTest
@testable import ScribeCore

/// Covers `PersonaStore` — the on-disk L2 (persona) + L3 (recent finished
/// writing) store, plus its capacity caps. Disk reads/writes go through the
/// real `~/Library/Application Support/Scribe/` path because PersonaStore
/// wasn't designed with a configurable path; tests therefore use a sentinel
/// prefix and clean up after themselves.
@MainActor
final class PersonaStoreTests: XCTestCase {

    private var store: PersonaStore!

    override func setUp() async throws {
        // Shared singleton. Wipe whatever's there from a previous run.
        store = PersonaStore.shared
        store.purgeAll()
    }

    override func tearDown() async throws {
        store.purgeAll()
    }

    func testPersonaCapsAtMaxLength() {
        let oversized = String(repeating: "x", count: PersonaStore.maxPersonaCharacters + 250)
        let written = store.setPersona(oversized)
        XCTAssertEqual(written.count, PersonaStore.maxPersonaCharacters)
        XCTAssertEqual(store.persona.count, PersonaStore.maxPersonaCharacters)
    }

    func testPersonaPersistsAcrossReload() {
        store.setPersona("I'm a Swift developer who mixes Mandarin and English.")
        // Force a reload — simulates next-launch behavior.
        store.load()
        XCTAssertEqual(
            store.persona,
            "I'm a Swift developer who mixes Mandarin and English."
        )
    }

    func testRecentEntryIsTruncatedToMaxCharacters() {
        let oversized = String(repeating: "我", count: PersonaStore.maxRecentEntryCharacters + 50)
        store.recordFinalText(oversized, languageCode: "zh-CN")
        XCTAssertEqual(store.recent.count, 1)
        XCTAssertEqual(store.recent[0].text.count, PersonaStore.maxRecentEntryCharacters)
    }

    func testRecentRollsOldEntriesOff() {
        for i in 0..<(PersonaStore.maxRecentEntries + 3) {
            store.recordFinalText("entry \(i)", languageCode: "en-US")
        }
        XCTAssertEqual(store.recent.count, PersonaStore.maxRecentEntries)
        // Oldest entries (0, 1, 2) should have been dropped; newest is "entry 7".
        XCTAssertEqual(store.recent.first?.text, "entry 3")
        XCTAssertEqual(store.recent.last?.text, "entry \(PersonaStore.maxRecentEntries + 2)")
    }

    func testRecentSkipsEmptyText() {
        store.recordFinalText("   \n  ", languageCode: "en-US")
        XCTAssertEqual(store.recent.count, 0,
                       "Pure-whitespace entries shouldn't pollute history")
    }

    func testRecentPersistsAcrossReload() {
        store.recordFinalText("hello world", languageCode: "en-US")
        store.recordFinalText("再见世界", languageCode: "zh-CN")
        store.load()  // simulate next launch
        XCTAssertEqual(store.recent.count, 2)
        XCTAssertEqual(store.recent[0].text, "hello world")
        XCTAssertEqual(store.recent[0].lang, "en-US")
        XCTAssertEqual(store.recent[1].text, "再见世界")
        XCTAssertEqual(store.recent[1].lang, "zh-CN")
    }

    func testPurgeAllClearsBothLayers() {
        store.setPersona("something")
        store.recordFinalText("anything", languageCode: "en-US")
        store.purgeAll()
        XCTAssertEqual(store.persona, "")
        XCTAssertTrue(store.recent.isEmpty)
    }
}
