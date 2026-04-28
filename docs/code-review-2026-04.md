# Code review — 2026-04 refactor pass

Audit of the Swift code under `Sources/Scribe/` and `Tests/ScribeCoreTests/`. Each entry is a self-contained brief that codex can pick up: symptom, repro, proposed fix, and the tests that should accompany the fix. File references use `path:line` form against the tree at commit `2cec121`.

The headline rule: **bug fixes in this pass must land with tests**. The Refinement module already has a unit-test surface (`PolishCoordinatorTests`, `PersonaStoreTests`, `PolishPromptTests`); add to it rather than inventing a new test target.

---

## Severity 🔴 — real bugs

### R1. `LlamaContext` "cooperative cancellation" never triggers

**Location**: [Sources/Scribe/Refinement/LlamaContext.swift:206-209](../Sources/Scribe/Refinement/LlamaContext.swift#L206-L209), [Sources/Scribe/Refinement/LlamaContext.swift:242-258](../Sources/Scribe/Refinement/LlamaContext.swift#L242-L258).

**Symptom**: `try Task.checkCancellation()` and `Task.isCancelled` checks are placed inside the body of `queue.async { … }`. A `DispatchQueue.async` closure has no current Task, so `Task.isCancelled` returns `false` and `checkCancellation()` is a no-op. The "cooperative cancellation" comment in the inference loop is misleading.

**Real-world consequence** (worse than it first looks): `PolishCoordinator.withTimeout` is built on `withThrowingTaskGroup`. When the sleep arm fires at 5 s, it throws `.timeout`, the group is cancelled, and the closure tries to exit — **but `withThrowingTaskGroup` waits for cancelled child tasks to finish before returning**. The child task running `svc.polish(...)` is awaiting on a `withCheckedThrowingContinuation` whose `cont.resume(...)` is only called when the inference queue's `generateSync` returns naturally. The flag-less per-token `Task.checkCancellation()` doesn't help.

So the user-visible failure mode isn't "raw is pasted at 5 s, model keeps spinning in the background" — it's "**the polish call itself blocks for 5 s + remaining-generation-time** (potentially 10–15 s on M2 Air at `maxNewTokens = 256`) before raw gets pasted". The whole UI is in `.polishing` for that entire window: the spinner stays up, Fn is locked, and the user thinks Scribe has hung.

**Fix** — must satisfy both: (a) the inference loop bails quickly on cancel, and (b) the awaiting continuation actually resumes so `withTimeout`'s implicit await-on-cancel can return.

1. Add a thread-safe cancellation flag to `LlamaContext` (e.g. `ManagedAtomic<Bool>` from `swift-atomics`, or an `os_unfair_lock`-protected `Bool` to avoid the dependency). One instance per context, reset to `false` at the start of each `generate(...)` call.
2. The inference loop reads the flag every iteration; on `true` it frees the sampler and throws `Error.generationCancelled`. That throw flows into the existing `catch` in `onQueue`, which calls `cont.resume(throwing:)` — the continuation completes, the awaiting child task's `await` resumes with the error, and the task group's await-on-cancel unblocks. Bound: ≤ 1 token of work after the flag is set.
3. The async entry points (`generate`, `warmUp`) wrap the continuation in `withTaskCancellationHandler`. The `onCancel` closure sets the flag — that's all it can safely do (it can't touch the continuation; double-resume would crash).
4. Make sure the `cont.resume` path is called exactly once. The current code has only one resume site per branch (`do { ... try work() ... resume(returning:) } catch { resume(throwing:) }`), so as long as `work()` returns or throws exactly once, we're safe — but verify when reviewing.
5. Update the misleading "cooperative cancellation" comment to describe the actual mechanism.

**Test to add** (`Tests/ScribeCoreTests/LlamaContextCancellationTests.swift`):

The real `LlamaContext` requires a 3.5 GB GGUF — don't load that in CI. Instead, **introduce a protocol seam** (e.g. `LlamaInferenceContext` with `warmUp` / `generate` / `cancelAndDrain`) and a `MockInferenceContext` whose `generate` loop sleeps in 10 ms slices polling the cancellation flag. This is the test seam codex should add as part of the R1 fix anyway.

Assertions:
- `testCancelUnblocksWithinOneSlice`: launch `Task { try await ctx.generate(...) }`, after 50 ms call `task.cancel()`, await — must complete with `Error.generationCancelled` within ≤ 50 ms of the cancel (one slice + scheduling slack).
- `testTimeoutWrapperReturnsPromptly`: wrap the mock in `withTimeout(seconds: 0.2) { try await ctx.generate(...) }`. Total wall time ≤ 0.4 s (timeout + one slice). This is the regression gate against the headline bug — without the fix, this test would block for the full mock generation length.
- `testNaturalCompletionDoesNotResumeTwice`: run a generation that finishes before any cancel; assert no double-resume crash.

**Codex verify**:
- [ ] Search for `Task.isCancelled` and `Task.checkCancellation()` inside any `DispatchQueue.async` body — should be zero hits in the Refinement module.
- [ ] `withTaskCancellationHandler` wraps every `withCheckedThrowingContinuation` that hands work to a non-async queue.
- [ ] `testTimeoutWrapperReturnsPromptly` passes (the mechanical proof that the headline bug is fixed).
- [ ] Manual reproduction: temporarily lower `PolishCoordinator.timeoutSeconds` to 0.2 in a debug build, fire two polishes back-to-back, watch the menu icon — should drop out of `.polishing` within ~250 ms each, not 5+ s.

---

### R2. Shutdown race: `tearDownProcessBackend` runs while the inference queue is still using ggml

**Location**: [Sources/Scribe/AppDelegate.swift:132-138](../Sources/Scribe/AppDelegate.swift#L132-L138), [Sources/Scribe/Refinement/LocalPolishService.swift:89-92](../Sources/Scribe/Refinement/LocalPolishService.swift#L89-L92), [Sources/Scribe/Refinement/LlamaContext.swift:71-86](../Sources/Scribe/Refinement/LlamaContext.swift#L71-L86).

**Symptom** (refined): `LlamaContext.generate(...)` schedules its work via `onQueue { [self] in ... }`, which captures `self` strongly inside the dispatch closure. So `LocalPolishService.context = nil` does **not** immediately deinit a context whose generation is still running — the queue closure keeps it alive until it returns.

The actual hazard is the line right after, in `applicationWillTerminate`:

```swift
keyMonitor.stop()
if let local = polishCoordinator.local as? LocalPolishService {
    local.releaseContextForShutdown()
}
LlamaContext.tearDownProcessBackend()   // ← calls llama_backend_free()
```

`llama_backend_free()` tears down ggml's process-wide state. If the inference queue is still mid-`llama_decode` (or even just holding pointers into that backend), the next ggml call inside that decode trips on freed globals — same family of crash as the v0.3.3 ggml destructor race that motivated `tearDownProcessBackend` in the first place. R1's missing cancellation widens the window: the queue work doesn't even know it should stop.

**Fix**: drain the inference queue *before* tearing down the backend.

```swift
// LlamaContext
func cancelAndDrain() {
    cancelFlag.store(true, ordering: .relaxed)   // primitive added in R1
    queue.sync { }                                // wait for any in-flight work to unwind
}

// LocalPolishService
func releaseContextForShutdown() {
    context?.cancelAndDrain()
    context = nil
    contextWarmedUp = false
}

// AppDelegate.applicationWillTerminate — order is load-bearing:
//   1. releaseContextForShutdown   (drains + nils)
//   2. tearDownProcessBackend      (only safe AFTER drain)
```

`queue.sync { }` blocks main until the queue's serial slot is free — bounded by R1's per-token cancellation latency (single-digit ms). After return, no work on the queue is using llama/ggml, so backend teardown is safe and `deinit`'s `llama_free` / `llama_model_free` won't race.

**Test to add** (alongside R1's `LlamaContextCancellationTests.swift`):

- `testCancelAndDrainBlocksUntilWorkCompletes`: on the mock context, start a generation that takes 200 ms, call `cancelAndDrain()` from another task at +50 ms, assert `cancelAndDrain` returns only after the mock's generation closure has observably exited. (Use a counter / latch the mock increments on entry and decrements on exit; assert `inFlight == 0` immediately after `cancelAndDrain` returns.)
- `testTeardownOrderingPreventsBackendFreeBeforeDrain`: contrive a test that fails fast if `llama_backend_free` (or the mock equivalent) is observed before drain completes.

**Codex verify**:
- [ ] `applicationWillTerminate` calls `releaseContextForShutdown` *before* `tearDownProcessBackend` — the sequence is the whole point.
- [ ] `releaseContextForShutdown` drains before nilling.
- [ ] Manual repro: enable Local backend, hold Fn for ~3 s, release, immediately Cmd-Q while spinner is up. App should exit cleanly (no SIGABRT / SIGSEGV) on three consecutive attempts.

---

### R3. `refreshAvailability` clobbers user-visible failure state

**Location**: [Sources/Scribe/Refinement/LocalPolishService.swift:45-58](../Sources/Scribe/Refinement/LocalPolishService.swift#L45-L58).

**Symptom**: the `else` branch resets `downloadState` to `.notDownloaded` for any state that isn't `.downloading` / `.verifying`. `applicationDidBecomeActive` calls `polishCoordinator.refreshAvailability()` → into here. So the user sees `Download failed: 网络不可达`, switches to System Settings, switches back to Scribe → status now reads `Not downloaded` with no explanation. They have to retry blindly.

**Fix**: preserve `.downloadFailed` and `.loadFailed` unless the model file is actually present. Only `.notDownloaded` and `.ready` should be derived from disk state; failure states are explicit and only the user (Retry / Delete) or a new download attempt should clear them.

```swift
func refreshAvailability() {
    if ModelLocation.modelIsPresent() {
        downloadState = .ready
    } else {
        switch downloadState {
        case .downloading, .verifying, .downloadFailed, .loadFailed:
            // Don't clobber in-flight or sticky failure states.
            break
        case .notDownloaded, .ready:
            downloadState = .notDownloaded
            context = nil
            contextWarmedUp = false
        }
    }
    NotificationCenter.default.post(name: .polishAvailabilityChanged, object: self)
}
```

**Test to add** (`Tests/ScribeCoreTests/LocalPolishServiceTests.swift`):

- Force `downloadState = .downloadFailed(...)` via a test seam.
- Call `refreshAvailability()` with no model file on disk.
- Assert state is still `.downloadFailed`.
- Repeat for `.loadFailed`.
- Sanity check: when the model file is present, `.downloadFailed` does flip to `.ready` (failure resolves on its own when the file shows up — e.g. user manually copied it in).

**Codex verify**:
- [ ] State transition table in source matches the matrix above.
- [ ] No regression: `purgeModel()` still moves us back to `.notDownloaded` (it calls `refreshAvailability()` after deleting the file, and the file's absence with `.notDownloaded` already in the prior state means we stay there — verify the ordering).

---

### R4. Timeouts are invisible to the menu-bar status

**Location**: [Sources/Scribe/Refinement/PolishCoordinator.swift:228-236](../Sources/Scribe/Refinement/PolishCoordinator.swift#L228-L236), [Sources/Scribe/AppDelegate.swift:222-230](../Sources/Scribe/AppDelegate.swift#L222-L230), [Sources/Scribe/AppDelegate.swift:367-382](../Sources/Scribe/AppDelegate.swift#L367-L382).

**Symptom**: `lastPolishWasSkipped` in AppDelegate is computed as `consecutiveFailures > beforeFailures`. Timeouts deliberately don't increment that counter (so the breaker doesn't auto-disable on slow hardware), so a polish that always times out shows `Polish: ready` in the menu forever. The user has no signal that polish is silently falling back to raw on every recording.

The intent of "timeouts shouldn't trip the breaker" is correct. The intent of "timeouts shouldn't surface in the UI at all" is wrong.

**Fix**: track timeouts separately.

```swift
// PolishCoordinator
private(set) var consecutiveTimeouts: Int = 0
private(set) var lastCallTimedOut: Bool = false

// In maybePolish:
catch PolishError.timeout {
    consecutiveTimeouts += 1
    lastCallTimedOut = true
    final = raw
}
// In recordSuccess:
consecutiveTimeouts = 0
lastCallTimedOut = false
```

Then in `refreshPolishMenuItem`, the timeout case **must be checked before the `active()` ready branch** — otherwise as long as the backend is still ready (which it is after a timeout: timeouts don't trip the breaker), the early `key = "menu.polish.readyXxx"` fires and the timeout signal is shadowed forever:

```swift
let key: String
if polishCoordinator.isBreakerTripped {
    key = "menu.polish.breakerTripped"
} else if !polishCoordinator.isEnabled {
    key = "menu.polish.off"
} else if polishCoordinator.lastCallTimedOut {     // ← BEFORE active()
    key = "menu.polish.skippedTimeout"
} else if let svc = polishCoordinator.active() {
    key = svc.backend == .system ? "menu.polish.readySystem" : "menu.polish.readyLocal"
} else if lastPolishWasSkipped {
    key = "menu.polish.skipped"
} else {
    key = "menu.polish.unavailable"
}
```

Add the new L10n key (`menu.polish.skippedTimeout`) across all five locale tables in `Localized.swift`.

**Existing-test fix** ⚠️ **load-bearing — without it the suite goes red as soon as the broken assertion stops matching**:

[`Tests/ScribeCoreTests/PolishCoordinatorTests.swift:100`](../Tests/ScribeCoreTests/PolishCoordinatorTests.swift#L100) currently asserts `XCTAssertEqual(coordinator.consecutiveFailures, 1)` after a timeout. The production code at [`PolishCoordinator.swift:228-236`](../Sources/Scribe/Refinement/PolishCoordinator.swift#L228-L236) explicitly does **not** increment on timeout. This is a stale assertion left over from before v0.4.1 (the timeout-out-of-breaker change). It is currently broken — confirm it's red on `swift test` and rewrite to:

```swift
XCTAssertEqual(coordinator.consecutiveFailures, 0,
               "Timeout must NOT increment consecutiveFailures (would trip breaker on slow hardware)")
XCTAssertTrue(coordinator.lastCallTimedOut)
```

**New tests** (extend `PolishCoordinatorTests`):

- `testSuccessAfterTimeoutClearsLastCallTimedOut` — sequence: stub slow → timeout (assert `lastCallTimedOut == true`), then swap to a fast stub → success → assert `lastCallTimedOut == false`.
- `testTimeoutFollowedByFailureIncrementsBreakerCorrectly` — pin the invariant that timeouts and hard failures count on separate axes (consecutive timeouts don't burn breaker budget; consecutive failures do).

**Codex verify**:
- [ ] `consecutiveFailures` only increments on `PolishError.emptyOutput`, `.lengthExploded`, `.unavailable`, and any other non-timeout throw.
- [ ] `consecutiveTimeouts` (or whatever name you use) only increments on `PolishError.timeout`.
- [ ] In `refreshPolishMenuItem`, the `lastCallTimedOut` branch is *before* the `active()` branch.
- [ ] All five `menu.polish.skippedTimeout` strings are present in `Localized.swift`.
- [ ] `swift test` passes — the stale assertion at line 100 has been updated.

---

## Severity 🟡 — design smells / latent issues

### Y5. The download-resume mechanism is broken end-to-end

**Location**: [Sources/Scribe/Refinement/Download/ModelDownloader.swift:130-133](../Sources/Scribe/Refinement/Download/ModelDownloader.swift#L130-L133), [Sources/Scribe/Refinement/Download/ModelDownloader.swift:165-180](../Sources/Scribe/Refinement/Download/ModelDownloader.swift#L165-L180), [Sources/Scribe/Refinement/Download/ModelDownloader.swift:211-214](../Sources/Scribe/Refinement/Download/ModelDownloader.swift#L211-L214), [Sources/Scribe/Refinement/Download/ModelDownloader.swift:286-310](../Sources/Scribe/Refinement/Download/ModelDownloader.swift#L286-L310).

**Symptom** (corrected): the downloader appears to support two resume mechanisms; in practice neither one fires across the cancel-and-relaunch path.

1. **`persistResumeData` is dead.** It writes a `<file>.partial.resumeData` file on cancel, but nothing ever reads it. URLSession's `downloadTask(withResumeData:)` is never called. The file is reaped by `cleanPartialFiles()`.
2. **The `Range:` + `.partial` path doesn't actually resume either**, because `URLSessionDownloadTask` writes downloading bytes to a system-managed temp file location and only hands them to the delegate via `didFinishDownloadingTo` *on full completion*. The code only populates `.partial` from inside `didFinishDownloadingTo` (move-from-temp on the 200 path, or append-from-temp on the 206 path). On cancel or network error, the system temp file is gone and `.partial` was never touched. So when the user retries (this run or next launch), `startNextMirror` looks for `.partial`, finds nothing (or a leftover from a *fully completed* prior attempt that then failed integrity — but `cleanPartialFiles()` removes that too), and re-issues the GET without a `Range:` header. **Cross-cancel resume starts from byte 0.**

So a user with flaky internet who cancels at 80 % of a 3.46 GB download re-downloads from zero. The comments and docs claim resume works; it doesn't.

**Fix** — pick *one* direction; the current half-and-half is the worst case:

- **Option A (smaller diff): properly use URLSession's resumeData.** On cancel, `cancel(byProducingResumeData:)` already provides resumeData via the existing closure — write it to `.partial.resumeData`. On next `start`, if that file exists and the descriptor still matches, call `session.downloadTask(withResumeData:)` instead of `downloadTask(with: req)`. Drop the manual `Range:` + append-on-206 path entirely; URLSession handles it. Caveat: URLSession resumeData is opaque and tied to the URL — switching mirrors invalidates it.
- **Option B (more control, also more code): switch to `URLSessionDataTask` with streaming append.** In `urlSession(_:dataTask:didReceive:)`, append each chunk to `.partial` directly. On cancel/error, `.partial` already has whatever was received. The existing `Range:` request logic against `.partial` size then *actually* works. This is also the only viable path if the team wants to support cross-mirror resume.

Either way: delete `persistResumeData` if going with B (it's still useless), or implement the read side if going with A.

**Test to add** (`Tests/ScribeCoreTests/ModelDownloaderTests.swift`, new file):

Use `URLProtocol` to intercept HTTP (no network in CI). Test cases:

- `testMirrorChainAdvancesOn404`: first mirror returns 404, second returns a small fixture body + 200; assert state reaches `.verifying` → `.failed(.integrity(...))` (fixture hash won't match pinned hash; that's fine — we're testing the chain, not integrity).
- `testCancelResumeFromPartial` (option B) **or** `testCancelResumeFromResumeData` (option A): start a download that delivers half the body, cancel; restart; assert the second request hits the network with `Range: bytes=N-` (option B) or that `downloadTask(withResumeData:)` is used (option A) — and that the final assembled bytes equal the full fixture.
- `testIntegrityMismatchDeletesFile`: stub a complete download whose hash doesn't match; assert the file at `ModelLocation.modelURL` is removed and state is `.failed(.integrity(...))`.
- `testDiskFullSurfaces`: stub the file move to throw `NSFileWriteOutOfSpaceError`; assert `.failed(.diskFull)`.

**Codex verify**:
- [ ] One coherent resume mechanism; no half-implementation. Either `withResumeData:` is called somewhere, or `.partial` is grown incrementally by chunk append.
- [ ] Manual repro: enable Local backend on a 3 G connection, throttle to ~1 Mb/s, hit Cancel at ~30 %, hit Download again — second download starts at ~30 %, not 0 %.

---

### Y6. `SystemPolishService.sessionPromptKey` collides easily

**Location**: [Sources/Scribe/Refinement/SystemPolishService.swift:78-83](../Sources/Scribe/Refinement/SystemPolishService.swift#L78-L83).

**Symptom**: the cache key is `"\(count):\(prefix(16))…\(suffix(16))"`. The L1 system prompt in `PolishPrompt.system` is ~3 KB and identical across calls; the *adaptive* layers (L2 persona, L3 recent) are appended in `PolishPrompt.assemble` after L1. The first 16 and last 16 chars are mostly L1's fixed bookends, and the count varies only with persona / recent length. Two distinct adaptive prompts of equal length collide → the cached `LanguageModelSession` is reused with stale instructions. User sees "polish doesn't seem to follow my new persona for a few calls".

**Fix**: hash the whole prompt. `SHA256(...)` is fine; even `var hasher = Hasher(); hasher.combine(prompt); hasher.finalize()` works (per-process stable, which is all this needs).

**Test to add**: extend `PolishPromptTests` or add a tiny `SystemPolishServiceKeyTests`:

- Two assembled prompts that are equal-length and share the L1 bookends but differ in L2 must produce different keys.
- Two identical prompts must produce the same key.

**Codex verify**:
- [ ] Key derivation has no length-only / prefix-only / suffix-only shortcut.
- [ ] Migration safe: cache miss on first call after upgrade is fine.

---

### Y7. Actor-reentrancy audit around in-flight polish

**Location**: [Sources/Scribe/Refinement/PolishService.swift:14-15](../Sources/Scribe/Refinement/PolishService.swift#L14-L15), [Sources/Scribe/Refinement/PolishCoordinator.swift:201-243](../Sources/Scribe/Refinement/PolishCoordinator.swift#L201-L243), [Sources/Scribe/AppDelegate.swift:118-124](../Sources/Scribe/AppDelegate.swift#L118-L124).

**Premise** (the original framing was wrong): `await LanguageModelSession.respond(...)` does **not** "block the main actor". An `await` releases the actor while suspended — that's normal Swift concurrency. Calling out heavy work on `@MainActor` was a mis-diagnosis.

**The real concern** is *reentrancy*: while `maybePolish` is awaiting `svc.polish(...)`, the main actor is free, and any other `@MainActor` work can interleave. Specifically:

- `applicationDidBecomeActive` calls `polishCoordinator.refreshAvailability()` ([AppDelegate.swift:122](../Sources/Scribe/AppDelegate.swift#L122)) which mutates `LocalPolishService.downloadState` and posts `.polishAvailabilityChanged`. The polish that's mid-await may have read state before the refresh and act on stale assumptions afterward.
- `Settings.adaptiveCheckbox` toggling rewrites `personaStore` and the L2/L3 layers. A polish call that already assembled a prompt with the old layers happily proceeds with stale instructions.
- The breaker can change state under the in-flight call: another polish (in theory not possible because state machine locks Fn during `.polishing`, but verify) could increment failures before this one returns.

**Scope this as a separate design pass**, not bundled with R1/R2. The R1/R2 fixes don't touch isolation; mixing them would make the diff hard to review.

**Audit checklist (what codex should produce, not implement)**:
1. Inventory every mutable property on `PolishCoordinator`, `LocalPolishService`, `SystemPolishService`, `PersonaStore` — for each, identify whether it can change while `maybePolish` is awaiting `svc.polish(...)`, and whether that change is benign or load-bearing.
2. For each load-bearing one: either snapshot it at call entry (already done for `systemPrompt` — that's a string, immutable post-assembly), or guard against re-entry at the coordinator level (e.g. an `inFlight: Bool` that rejects nested `maybePolish`).
3. Decide whether dropping `@MainActor` from `PolishService.polish` would help or just move the hazard. (It probably moves it: implementations would still touch main-actor state internally; the protocol annotation isn't where the actual coupling lives.)

The likely outcome is *not* a protocol re-isolation — it's adding a snapshot or a re-entry guard inside `maybePolish`. But run the audit before deciding.

**Test to add**: hard to unit-test cleanly. Once a snapshot/guard is identified, add a regression test that drives the relevant reentrancy and asserts the in-flight polish observed its snapshot, not the post-mutation value.

**Codex verify**:
- [ ] Audit document checked in (or this section updated with conclusions). No source change is required if the audit shows current behavior is acceptable.
- [ ] If a guard is added: a test exercises the reentry path.

---

### Y8. `TextInjector` blocks main with `usleep(50_000)`

**Location**: [Sources/Scribe/TextInjector.swift:25](../Sources/Scribe/TextInjector.swift#L25).

**Symptom**: the input-source switch path sleeps the main thread for 50 ms inside `inject`. Combined with the 100 ms `Task.sleep` in `AppDelegate.deliverFinal` before `inject`, total latency from polish-done to paste-attempt is ≥ 150 ms.

**Fix**: keep the TIS API calls (they're sync), but move the whole `inject` flow to a serial dispatch queue so the `usleep` doesn't freeze the UI. Pasteboard mutation off-main is documented-safe; `CGEvent.post` is safe off-main. The current restoration `DispatchQueue.main.asyncAfter(deadline: 0.3 / 0.5)` then runs on that same private queue.

Less invasive alternative: short-circuit the `needSwitch` branch when the original source is already ASCII-capable (the code does this already) — but profile to see if non-ASCII users are actually hit. If yes, the 50 ms is unavoidable on main without queuing.

**Test to add**: unit-test impractical (TIS is system-bound). Add a manual checklist item.

---

## Severity 🟢 — polish

### G9. 100 ms `Task.sleep` in `deliverFinal` has a thin justification

[Sources/Scribe/AppDelegate.swift:240](../Sources/Scribe/AppDelegate.swift#L240). Comment says "let cancel settle". Codex should attempt to delete it, run the suite, and probe manual repro. If nothing breaks, drop it; if it's load-bearing, expand the comment to name the actual race.

### G10. Audio level dispatched per-buffer to main

[Sources/Scribe/AppleSpeechSession.swift:203-206](../Sources/Scribe/AppleSpeechSession.swift#L203-L206). 100+ Hz hops to main. Throttle to ~30 Hz with a timestamp gate inside `emitAudioLevel`.

### G11. Adaptive Reset is buried in Finder

PersonaStore has `purgeAll()` but it's not surfaced in Settings. CLAUDE.md / `PersonaStore.swift` argue Finder is enough; for a privacy-sensitive store this is borderline. Add a small "Reset persona + recent" button under the Open Folder button in `SettingsWindow`.

### G12. `Timer.scheduledTimer` for persona debounce can be delayed across modal mode

[Sources/Scribe/SettingsWindow.swift:412](../Sources/Scribe/SettingsWindow.swift#L412). The default-mode timer doesn't fire while the run loop is in `eventTracking` / `modalPanel` mode, but it does fire once the loop returns to default — so most users see "save delayed", not "save lost". The actual loss window is narrow: user types, modal alert pops up, user Cmd-Q's *from the alert* before returning to default mode → the 0.5 s debounce never fires. Low severity, easy fix: register the timer for `.common` modes instead, or use a `DispatchSourceTimer`.

---

## Prerequisite — CI executability

**Status:** resolved. `swift test` now passes locally (no Xcode required) and a CI workflow runs it on every push.

What changed:

- Added [`.github/workflows/test.yml`](../.github/workflows/test.yml) — `swift test --parallel` on a `macos-15` runner with the bundled Xcode 16 toolchain.
- **Migrated the test target from XCTest to swift-testing** (`import Testing`, `@Suite` / `@Test` / `#expect`). XCTest is only available with full Xcode on macOS; swift.org toolchains and Xcode-CommandLineTools-only setups don't ship it. swift-testing is bundled with Swift 6 and works on both. With this migration, tests run anywhere there's a Swift 6+ toolchain — the project root is pinned to 6.3.1 via `.swift-version` so swiftly users get a consistent setup automatically.
- One stale assertion at the old `PolishCoordinatorTests:100` (the `consecutiveFailures == 1` after a timeout, which contradicted the v0.4.1 production code) was repaired as part of R4 — see that section. It had been silently red since v0.4.1 because there was no CI gate.

## Suggested rollout

1. **Land R1 + R2 together** — they share the cancellation primitive; fixing one without the other still leaves a window. R2 also depends on R1's `cancelFlag`/`cancelAndDrain` primitive.
2. **R3** is independent and small — good warm-up PR.
3. **R4** is a one-PR UX fix bundled with the L10n string addition *and* the stale-test repair at line 100.
4. **Y5** is its own PR (option A vs option B is a design call; don't fold this in with R-series).
5. **Y6** is small and standalone.
6. **Y7** is an audit, not a fix — output may be a doc update only, no code change.
7. **G-series** can be opportunistic.

## Test-coverage gaps (post-fix)

After the above lands, the still-missing test coverage is:
- `KeyMonitor` — hard to unit-test (CGEventTap is system-bound); accept it.
- `TextInjector` — same (TIS / CGEvent).
- `AppleSpeechSession` fallback timer — can be tested with a fake `SFSpeechRecognizer` if we introduce a protocol seam; defer unless a regression appears.
- `ModelDownloader` URLProtocol-based tests — added by Y5.
- `LocalPolishService` state machine — added by R3.
- `LlamaContext` cancellation lifecycle — added by R1 + R2.

## Out of scope for this pass

- Switching the GGUF (Gemma 4 → something else) — product decision.
- Reworking the Settings layout — design pass, not a refactor.
- Sparkle / appcast plumbing — separate concern.

---

## Revision history

- **2026-04-28** — initial draft.
- **2026-04-28** — revised against codex review feedback. Material changes:
  - R1: corrected the user-visible failure — timeout doesn't return raw at 5 s, it blocks for 5 s + remaining-generation-time, because `withThrowingTaskGroup` waits for cancelled child tasks. Hardened the fix to require continuation resumption, not just a flag.
  - R2: corrected the mechanism — `LocalPolishService.context = nil` doesn't immediately deinit (queue closure holds `[self]`); the actual race is `tearDownProcessBackend()` running while inference is still using ggml. Fix unchanged in shape, but ordering in `applicationWillTerminate` is now load-bearing.
  - R4: fixed the proposed branch ordering (`lastCallTimedOut` must precede the `active()` ready branch); flagged that `testTimeoutFallsBackToRaw` line 100 currently asserts `consecutiveFailures == 1` against code that returns `0` — must be repaired as part of R4.
  - Y5: rewrote — Range-resume against `.partial` doesn't actually work, because `URLSessionDownloadTask` doesn't write to `.partial` mid-download. Recommended a real redesign (option A: `withResumeData:`; option B: `URLSessionDataTask` + streaming append).
  - Y7: reframed from "heavy work on main actor" (wrong — `await` releases the actor) to actor-reentrancy audit; decoupled from R1/R2 PR.
  - G12: toned down — typically delayed save, not lost keystrokes; narrow loss window only at modal-mode + Cmd-Q.
  - Added a "Prerequisite — CI executability" section: codex couldn't run `swift test` (`no such module 'XCTest'`); none of these test additions land cleanly until the toolchain works.
