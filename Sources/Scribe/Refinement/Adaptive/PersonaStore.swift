import Foundation

/// On-disk store for the two adaptive-polish layers (per docs/adaptive-polish.md):
///
///   • **persona.txt** — Layer 2: a free-form description of *who the user is*
///     (handwritten in Settings; Phase 5.2+ may also be machine-derived).
///     Capped at 1000 characters.
///   • **recent.jsonl** — Layer 3: the last 5 *final* dictation outputs
///     (polished if polish was on, raw if it was off). Each entry capped at
///     100 characters. JSON Lines, oldest-first; we drop from the front when
///     it exceeds 5 entries.
///
/// Both files live next to the model under `~/Library/Application Support/
/// Scribe/`, so the user can see + edit + delete everything in one place from
/// Finder. The Settings UI doesn't need a Reset button — opening the folder
/// is enough.
@MainActor
final class PersonaStore {
    static let shared = PersonaStore()

    static let maxPersonaCharacters = 1000
    static let maxRecentEntries = 5
    static let maxRecentEntryCharacters = 100

    /// Layer 2 — what the user wrote about themselves.
    private(set) var persona: String = ""

    /// Layer 3 — most recent final outputs, newest last.
    private(set) var recent: [Entry] = []

    struct Entry: Codable, Equatable {
        let ts: String
        let lang: String
        let text: String
    }

    private let personaURL: URL
    private let recentURL: URL
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init() {
        self.personaURL = ModelLocation.supportDirectory.appendingPathComponent("persona.txt")
        self.recentURL = ModelLocation.supportDirectory.appendingPathComponent("recent.jsonl")
        load()
    }

    // MARK: - Disk I/O

    /// Reload from disk. Cheap; used at startup and when the user clicks
    /// "Open folder in Finder" then comes back (we re-read on activation in
    /// case they edited persona.txt by hand).
    func load() {
        if let data = try? Data(contentsOf: personaURL),
           let text = String(data: data, encoding: .utf8) {
            persona = String(text.prefix(Self.maxPersonaCharacters))
        } else {
            persona = ""
        }
        if let data = try? Data(contentsOf: recentURL),
           let text = String(data: data, encoding: .utf8) {
            let decoder = JSONDecoder()
            recent = text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
                guard let lineData = line.data(using: .utf8),
                      let entry = try? decoder.decode(Entry.self, from: lineData)
                else { return nil }
                return entry
            }
        } else {
            recent = []
        }
    }

    /// User-handwritten persona — invoked from the Settings textarea. Caps at
    /// the size limit and writes through atomically.
    @discardableResult
    func setPersona(_ text: String) -> String {
        let capped = String(text.prefix(Self.maxPersonaCharacters))
        persona = capped
        ModelLocation.ensureModelsDirectoryExists()  // creates parent dir
        try? capped.data(using: .utf8)?.write(to: personaURL, options: .atomic)
        return capped
    }

    /// Append a final-text entry. Called from `PolishCoordinator.maybePolish`
    /// after the polish step (or fallback) returns. `text` is the bytes that
    /// will actually get pasted at the cursor.
    ///
    /// No-op if the adaptive feature is disabled — gating happens in the
    /// caller. PersonaStore itself is dumb storage.
    func recordFinalText(_ text: String, languageCode: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let truncated = String(trimmed.prefix(Self.maxRecentEntryCharacters))
        let entry = Entry(
            ts: isoFormatter.string(from: Date()),
            lang: languageCode,
            text: truncated
        )
        recent.append(entry)
        while recent.count > Self.maxRecentEntries {
            recent.removeFirst()
        }
        flushRecent()
    }

    /// Wipe both files. Not exposed in Settings UI per design (Open Finder is
    /// enough), but available for tests and a possible future Reset action.
    func purgeAll() {
        persona = ""
        recent = []
        try? FileManager.default.removeItem(at: personaURL)
        try? FileManager.default.removeItem(at: recentURL)
    }

    // MARK: - Private

    private func flushRecent() {
        ModelLocation.ensureModelsDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // deterministic for diffing
        let lines = recent.compactMap { entry -> String? in
            guard let data = try? encoder.encode(entry),
                  let line = String(data: data, encoding: .utf8) else { return nil }
            return line
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? body.data(using: .utf8)?.write(to: recentURL, options: .atomic)
    }
}
