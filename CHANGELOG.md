# Changelog

All notable changes to Scribe are tracked here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
adheres to [Semantic Versioning](https://semver.org/) — minor bumps cover
behaviour fixes that affect end users; patch bumps cover small regressions
or polish without behavioural change.

## [Unreleased]

## [0.5.0] — 2026-04-28

A reliability + correctness pass on the transcript-polishing pipeline,
plus the test infrastructure to keep regressions out. No new features;
the Polish toggle, Settings layout, and recording lifecycle behave the
same way they did in v0.4.3 — they just behave more reliably.

### Fixed

- **Polish that hits the timeout no longer hangs the UI.** The previous
  cancellation hook lived inside a `DispatchQueue.async` closure that
  has no current Task, so the per-token poll was a no-op. A polish that
  clipped the 5 s budget on slower Apple Silicon (M2 Air, 8 GB) actually
  blocked for 5 s + remaining-generation-time — typically 10–15 s of
  spinner with the Fn key locked out. Now bounded by one decode step
  (~single-digit ms) of the timeout firing.
- **Cmd-Q during an in-flight polish no longer races ggml's
  process-wide teardown.** The shutdown path now drains the inference
  queue before freeing llama's process backend. Sibling crash to the
  v0.3.3 ggml destructor race; same family of cause, separate location.
- **The Polish: Download failed status no longer disappears when you
  switch apps and come back.** `applicationDidBecomeActive`'s incidental
  refresh used to reset any failure state to "Not downloaded", losing
  the reason you should retry. Failure states (download / load) are now
  sticky until you take an explicit action (Retry, Delete).
- **Polish timeouts now show in the menu bar.** Previously the menu
  said `Polish: Ready` even when every dictation in a session was
  silently falling back to raw because the model was just barely too
  slow. Timeouts now surface as `Polish: Skipped last call (timed out)`
  while still not tripping the breaker (which would auto-disable polish
  mid-session on slow hardware).
- **Local-backend download cancel + resume actually works.** The pre-Y5
  implementation used `URLSessionDownloadTask`, which only writes to
  disk on full completion. So `.partial` was always empty when you hit
  Cancel or the connection dropped, and the next attempt restarted from
  byte 0 — even though the comments and the `Range:` header logic
  promised resume. Now uses streaming-append so the bytes that arrived
  stay on disk, and the next start truly resumes.
- **Settings persona edit saves don't get dropped on Cmd-Q.** The
  500 ms debounce timer now runs in `.common` run-loop modes, so a
  modal alert mid-edit doesn't keep the timer from firing.

### Changed

- **Settings: Reset profile and history.** New destructive button under
  the persona text area. Wipes both `persona.txt` and `recent.jsonl`
  with a confirmation alert. Localized in en / zh-Hans / zh-Hant / ja / ko.
- **Waveform audio level throttled to ~30 Hz.** The audio tap fires at
  the input device's natural rate (100+ Hz). The UI only redraws at
  ~60 fps and the waveform's smoothing keeps it visually continuous from
  the slower input. Saves a few hundred main-queue hops per second.
- **`SystemPolishService` rebuilds its FM session on real prompt
  changes, not just length-collisions.** Previous cache key was
  `count + first/last 16 chars`; with adaptive (L2 persona / L3 recent)
  layers, two distinct prompts of equal length share the L1 bookends and
  collided, so the cached `LanguageModelSession` was reused with stale
  instructions. Now SHA-256 over the full prompt.

### Added

- **`swift test` runs on every push and PR** — `.github/workflows/test.yml`
  on a `macos-15` runner with Xcode 16. The repository was previously
  only running build/release CI; the first thing that uncovered was a
  stale assertion in `PolishCoordinatorTests` that had been silently
  red since v0.4.1.
- **The test target is now usable without full Xcode.** Migrated from
  `XCTest` to `swift-testing` (`import Testing`, `@Suite` / `@Test` /
  `#expect`), which ships with Swift 6 and works against
  Xcode-CommandLineTools-only setups and swift.org toolchains. The
  `.swift-version` pin (6.3.1) keeps swiftly users on the same toolchain.
- 22 new unit tests across three new suites
  (`CancellableInferenceQueueTests`, `LocalPolishServiceTests`,
  `ModelDownloaderTests`) plus 5 additions to existing suites pinning
  the Y6 and R4 invariants. 56 tests total, 7 suites, all green.

### Internal

- **`CancellableInferenceQueue`** — a small reusable type that bridges
  synchronous polling work to async/await with `OSAllocatedUnfairLock`-
  backed cancellation and a `cancelAndDrain()` for shutdown safety.
  Owned by `LlamaContext`, exercised standalone by
  `CancellableInferenceQueueTests`.
- **`docs/code-review-2026-04.md`** — the audit that motivated this
  release. Each item (R1–R4, Y5–Y8, G9–G12) carries symptom, fix, tests
  to add, and verify checklist.
- **`docs/y7-actor-reentrancy-audit.md`** — Y7's outcome doc. The
  audit concluded no code change was needed; the snapshot pattern in
  `maybePolish` plus the `.polishing` Fn-lock cover every load-bearing
  reentrancy path. Records the conditions that would invalidate the
  conclusion (concurrent polishes, mid-session persona derivation,
  runtime-context fields).

### Deferred

- **Y8** (move `TextInjector` work off the main thread): inspected and
  intentionally not changed. Async-dispatching the inject flow flips the
  perceived UX ordering between paste and overlay-dismiss in a way
  that's net worse than the 50 ms main-thread sleep it would save (and
  only for non-ASCII input source users, where the sleep is unavoidable
  anyway).
- **G9** (drop the 100 ms `Task.sleep` in `deliverFinal`): not modified
  this pass. The cancellation race the comment alludes to needs an
  on-device check (Fn re-press + paste-injection timing) that the
  toolchain on the dev machine couldn't reproduce. Punted to a future
  pass with manual verification.

---

## [0.4.3] — 2026-04-27

- Fixed: transcript pill now ellipsises at the head, not the tail, so
  the most recent words remain visible while the user is mid-sentence.

## [0.4.2] — 2026-04-26

- Fixed: overlay's transcript pill stays on a single line and hides
  during the loading (transcribe / polish) state.

## [0.4.1] — 2026-04-25

- Changed: bumped `PolishCoordinator.timeoutSeconds` from 3 s to 5 s
  so M2 Air doesn't trip the breaker on every borderline polish.
- Changed: `.polishing` state now locks the Fn key out for the whole
  duration of the polish pipeline, preventing accidental second
  recordings while the model is still working on the first.

## [0.4.0]

- Changed: local-polish backend swapped from Qwen 2.5-1.5B (~1 GB)
  to Gemma 4 E2B-it Q4_K_M (~3.5 GB). Persona-leak / question-answering /
  multilingual-preservation adversarial cases that Qwen 1.5B failed are
  handled by Gemma 4 E2B; details in `docs/polish-model-eval.md`.
  Existing Qwen download lives on disk as an orphan for users who want
  to roll back; we don't auto-prune.

## [0.3.8]

- Fixed: harden adaptive prompt against persona-leak (partial fix —
  full fix shipped in v0.4.0 with the Gemma 4 swap).

## [0.3.7]

- Fixed: persona textarea was rendering typed characters with an
  invisible foreground colour. Now sets both `textColor` and
  `typingAttributes`.

## [0.3.6]

- Fixed: don't fail releases when Apple's CloudKit notarization
  replication is slow; budget 15 min of retries before shipping un-stapled.

## [0.3.5]

- Fixed: polish now refuses to answer dictated questions instead of
  polishing them ("what time is the meeting?" stays a question, doesn't
  get an answer).

## [0.3.4]

- Fixed: llama.cpp Metal abort on Cmd-Q (`tearDownProcessBackend`
  introduced).

## [0.3.3]

- Added: Phase 5.0 polish prompt upgrade.
- Fixed: UTF-8 split issues in Local backend output.
- Changed: `n_batch` tuned for the Gemma turn wrapper.

[Unreleased]: https://github.com/xiangst0816/scribe/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/xiangst0816/scribe/compare/v0.4.3...v0.5.0
[0.4.3]: https://github.com/xiangst0816/scribe/compare/v0.4.2...v0.4.3
[0.4.2]: https://github.com/xiangst0816/scribe/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/xiangst0816/scribe/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/xiangst0816/scribe/compare/v0.3.8...v0.4.0
[0.3.8]: https://github.com/xiangst0816/scribe/compare/v0.3.7...v0.3.8
[0.3.7]: https://github.com/xiangst0816/scribe/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/xiangst0816/scribe/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/xiangst0816/scribe/compare/v0.3.4...v0.3.5
[0.3.4]: https://github.com/xiangst0816/scribe/compare/v0.3.3...v0.3.4
[0.3.3]: https://github.com/xiangst0816/scribe/releases/tag/v0.3.3
