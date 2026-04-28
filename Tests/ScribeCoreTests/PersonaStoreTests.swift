import Testing
@testable import ScribeCore

/// Covers `PersonaStore` — the on-disk L2 (persona) + L3 (recent finished
/// writing) store, plus its capacity caps. Disk reads/writes go through the
/// real `~/Library/Application Support/Scribe/` path because PersonaStore
/// wasn't designed with a configurable path; each test purges before/after
/// to stay isolated. `.serialized` so two tests don't race on the shared
/// singleton.
@Suite(.serialized)
@MainActor
final class PersonaStoreTests {

    private let store: PersonaStore

    init() {
        // Shared singleton. Wipe whatever's there from a previous run — also
        // serves as the after-cleanup for the *previous* test, since
        // swift-testing instantiates a fresh suite per test and `deinit` on
        // a @MainActor class can't call @MainActor methods.
        store = PersonaStore.shared
        store.purgeAll()
    }

    @Test func personaCapsAtMaxLength() {
        let oversized = String(repeating: "x", count: PersonaStore.maxPersonaCharacters + 250)
        let written = store.setPersona(oversized)
        #expect(written.count == PersonaStore.maxPersonaCharacters)
        #expect(store.persona.count == PersonaStore.maxPersonaCharacters)
    }

    @Test func personaPersistsAcrossReload() {
        store.setPersona("I'm a Swift developer who mixes Mandarin and English.")
        // Force a reload — simulates next-launch behavior.
        store.load()
        #expect(
            store.persona == "I'm a Swift developer who mixes Mandarin and English."
        )
    }

    @Test func recentEntryIsTruncatedToMaxCharacters() {
        let oversized = String(repeating: "我", count: PersonaStore.maxRecentEntryCharacters + 50)
        store.recordFinalText(oversized, languageCode: "zh-CN")
        #expect(store.recent.count == 1)
        #expect(store.recent[0].text.count == PersonaStore.maxRecentEntryCharacters)
    }

    @Test func recentRollsOldEntriesOff() {
        for i in 0..<(PersonaStore.maxRecentEntries + 3) {
            store.recordFinalText("entry \(i)", languageCode: "en-US")
        }
        #expect(store.recent.count == PersonaStore.maxRecentEntries)
        // Oldest entries (0, 1, 2) should have been dropped; newest is "entry 7".
        #expect(store.recent.first?.text == "entry 3")
        #expect(store.recent.last?.text == "entry \(PersonaStore.maxRecentEntries + 2)")
    }

    @Test func recentSkipsEmptyText() {
        store.recordFinalText("   \n  ", languageCode: "en-US")
        #expect(
            store.recent.count == 0,
            "Pure-whitespace entries shouldn't pollute history"
        )
    }

    @Test func recentPersistsAcrossReload() {
        store.recordFinalText("hello world", languageCode: "en-US")
        store.recordFinalText("再见世界", languageCode: "zh-CN")
        store.load()  // simulate next launch
        #expect(store.recent.count == 2)
        #expect(store.recent[0].text == "hello world")
        #expect(store.recent[0].lang == "en-US")
        #expect(store.recent[1].text == "再见世界")
        #expect(store.recent[1].lang == "zh-CN")
    }

    @Test func purgeAllClearsBothLayers() {
        store.setPersona("something")
        store.recordFinalText("anything", languageCode: "en-US")
        store.purgeAll()
        #expect(store.persona == "")
        #expect(store.recent.isEmpty)
    }
}
