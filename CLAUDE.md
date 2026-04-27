# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & test

Scribe is a SwiftPM project — there is no Xcode project, only [Package.swift](Package.swift) plus a [Makefile](Makefile) that wraps `swift build` with `.app` bundling, Sparkle embedding, and ad-hoc codesign.

```bash
swift build                  # plain library/executable build (no .app bundle)
swift test                   # run XCTest suite
swift test --filter CurrentSentenceTests/testWhatever   # run a single test
make build                   # produce ./Scribe.app (release config, embeds Sparkle, ad-hoc signed)
make run                     # build and launch
make install                 # copy bundle to /Applications/Scribe.app
make clean                   # swift package clean + remove ./Scribe.app
make release VERSION=x.y.z   # build, stamp version into Info.plist, ditto-zip for Sparkle
make dmg                     # build styled DMG (requires `brew install create-dmg`)
```

For Developer ID / notarized builds, override `CODESIGN_IDENTITY` and `ENTITLEMENTS` on the `make` invocation — see the comment block at the top of the Makefile.

The website under [web/](web/) is an independent Astro project with its own `package.json`; it shares no build dependencies with the Mac app and is deployed separately via [.github/workflows/pages.yml](.github/workflows/pages.yml). Mac releases are cut by [.github/workflows/release.yml](.github/workflows/release.yml).

## Architecture

The app is a menu-bar-only (`LSUIElement = true`) push-to-talk dictation utility. Holding `Fn` records audio, releasing pastes the transcript at the cursor in any app.

Code lives in two SwiftPM targets:
- `ScribeCore` ([Sources/Scribe/](Sources/Scribe/)) — library holding all logic, so tests can `@testable import` without `main.swift` triggering `NSApplication`.
- `Scribe` executable ([Sources/ScribeApp/main.swift](Sources/ScribeApp/main.swift)) — nine-line shim that boots `NSApplication` with `AppDelegate`.

### Recording lifecycle (state machine)

[AppDelegate.swift](Sources/Scribe/AppDelegate.swift) is the single source of truth for the recording lifecycle. The state machine has five states — **all transitions go through `fnDown`, `fnUp`, `handleTermination`, or `cleanupAfterPolish`; do not introduce side-channel flag juggling.**

```
idle ──fnDown──▶ recording ──fnUp──▶ armedToStop ──(0.5s)──▶ transcribing ──[final]──▶ polishing ──polish-done──▶ idle
                     ▲                     │                                [cancel/error]──▶ idle
                     └──── fnDown ─────────┘   (re-press during trailing buffer keeps the same session)
```

- **Trailing buffer**: 0.5s after `fnUp`, audio still feeds the recognizer. Re-pressing `Fn` during this window cancels the pending stop and continues the same session — users often release a beat early.
- **`AppleSpeechSession` is single-use.** A terminated session cannot be restarted. This was [a deliberate rewrite](https://github.com/xiangst0816/scribe/commit/5dfdca5) to fix Fn going dead after errors; do not regress it by trying to reuse a session across recordings.
- `onTerminated` fires exactly once, on the main thread. After it fires, no further callbacks fire.
- **`.polishing` locks Fn out**. While the polish pipeline is running (typically 0.5–5 s on Apple Silicon, capped at the [PolishCoordinator timeout](Sources/Scribe/Refinement/PolishCoordinator.swift)), `fnDown`'s `.idle` guard rejects new presses and the loading overlay stays visible. The user explicitly asked for this behavior so they don't accidentally start a second recording while the model is still working on the first one.

### Components

| File | Role |
|---|---|
| [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) | `CGEventTap` on `.flagsChanged`, debounces the Fn flag to `onFnDown`/`onFnUp`. Requires Accessibility permission; `start()` returns `false` if the tap can't be created. |
| [AppleSpeechSession.swift](Sources/Scribe/AppleSpeechSession.swift) | Wraps one `SFSpeechRecognizer` streaming attempt. Has a 2.0s fallback timer because `SFSpeechRecognizer` occasionally never delivers `isFinal`. |
| [OverlayPanel.swift](Sources/Scribe/OverlayPanel.swift) | Borderless `NSPanel` with the frosted-glass waveform capsule + transcript pill. |
| [TextInjector.swift](Sources/Scribe/TextInjector.swift) | Clipboard + synthesized `⌘V`. Temporarily swaps to an ASCII input source so CJK IMEs don't intercept the paste, then restores the previous source. |
| [Localized.swift](Sources/Scribe/Localized.swift) | `L10n` table for menu/alert strings across en/zh-Hans/zh-Hant/ja/ko. Recognizer locale and UI locale are tracked separately but share the `selectedLocaleCode` UserDefaults key. |
| [SettingsWindow.swift](Sources/Scribe/SettingsWindow.swift) | The Polish Settings panel: master toggle + System/Local radios + status text. Listens for `.polishAvailabilityChanged` to live-refresh. |
| [Refinement/](Sources/Scribe/Refinement/) | Transcript-polishing feature; see next subsection. |

### Polish (transcript refinement)

Feature is **off by default** and gated behind a Settings master toggle. Two backends, mutually exclusive at runtime: `System` (Apple `FoundationModels`, macOS 26+ in supported regions) and `Local` (Gemma 4 E2B-it via llama.cpp, ~3.5 GB downloaded on first enable). Full design in [docs/local-refinement.md](docs/local-refinement.md), and the candidate-model trade-off in [docs/polish-model-eval.md](docs/polish-model-eval.md). Both backends are implemented; the Local one downloads its model on first enable.

| File | Role |
|---|---|
| [Refinement/PolishService.swift](Sources/Scribe/Refinement/PolishService.swift) | Protocol: `isReady` / `statusText` / `warmUp()` / `polish(_:languageHint:)` / `refreshAvailability()` plus default no-op download lifecycle hooks (`startDownload` / `cancelDownload` / `purgeModel`). Tests inject stubs. |
| [Refinement/PolishPrompt.swift](Sources/Scribe/Refinement/PolishPrompt.swift) | System prompt + `selectedLocaleCode → languageHint` map (shared by both backends so output is consistent) + a conservative preface stripper for Local outputs. |
| [Refinement/PolishCoordinator.swift](Sources/Scribe/Refinement/PolishCoordinator.swift) | Arbiter. Reads master toggle / selected backend / mirror preference from UserDefaults, pre-warms the active backend so cold-load latency doesn't eat the 3 s timeout, enforces a 3 s `withTimeout`, validates output (non-empty, ≤ 2× raw), and trips a circuit breaker after 3 consecutive failures (auto-disables the master toggle). |
| [Refinement/SystemPolishService.swift](Sources/Scribe/Refinement/SystemPolishService.swift) | `LanguageModelSession` wrapper, all calls gated by `if #available(macOS 26.0, *)` and `#if canImport(FoundationModels)`. Caches one session per language hint. |
| [Refinement/LocalPolishService.swift](Sources/Scribe/Refinement/LocalPolishService.swift) | Real llama.cpp-backed implementation. Owns a `LlamaContext` and tracks a richer `DownloadState` (`notDownloaded` / `downloading(percent)` / `verifying` / `ready` / `downloadFailed` / `loadFailed`) on top of the bare protocol surface. Builds Gemma 4 turn prompts (`<\|turn>...<turn\|>`, asymmetric pipes intentional — verified against `google/gemma-4-E4B-it/chat_template.jinja`) and strips stray turn / channel tokens (plus a defensive `<\|channel>thought…<channel\|>` block sweep) from outputs. |
| [Refinement/LlamaContext.swift](Sources/Scribe/Refinement/LlamaContext.swift) | **Not** `@MainActor`. Wraps `llama_*` C API; serialises inference onto a private `userInitiated` dispatch queue and bridges back via `withCheckedThrowingContinuation`. Silences ggml/llama log spam via `llama_log_set` once per process. |
| [Refinement/Download/ModelLocation.swift](Sources/Scribe/Refinement/Download/ModelLocation.swift) | Canonical paths under `~/Library/Application Support/Scribe/models/` for the pinned GGUF, its `.partial`, and `.partial.meta`. Names are model-agnostic (`modelURL` / `modelIsPresent`) so swapping the pinned build is a single-file change in `ModelDescriptor`. |
| [Refinement/Download/ModelMirror.swift](Sources/Scribe/Refinement/Download/ModelMirror.swift) | ModelScope / HuggingFace / hf-mirror.com URLs + `ModelMirrorPreference.fallbackChain(forLocaleCode:)` (zh-prefix → ModelScope first, otherwise HuggingFace first). `ModelDescriptor` pins the file name, expected size, and SHA-256. |
| [Refinement/Download/ModelIntegrity.swift](Sources/Scribe/Refinement/Download/ModelIntegrity.swift) | Streaming SHA-256 (1 MiB chunks in an autoreleasepool — bounded memory even for ~3.5 GB files). |
| [Refinement/Download/ModelDownloader.swift](Sources/Scribe/Refinement/Download/ModelDownloader.swift) | URLSessionDownloadDelegate. Mirror chain, HTTP `Range:` resume from `.partial`, append-on-206, atomic rename to final path, hash verify on completion. Failure matrix from [docs/local-refinement.md](docs/local-refinement.md) §4.4 (`unreachable` / `mirrorErrors([Int])` / `integrity` / `notPinned` / `diskFull` / `ioError`). Not `@MainActor`; state changes posted to main via `stateChanged`. |

UserDefaults keys owned by this module: `polish.enabled` (Bool), `polish.backend` ("system" / "local"), `polish.local.mirror` ("auto" / "modelScope" / "huggingFace" / "hfMirror"). Legacy keys from the deprecated remote-OpenAI path (`llmEnabled`, `llmAPIBaseURL`, `llmAPIKey`, `llmModel`) are scrubbed at startup by `PolishCoordinator.purgeLegacyKeys`.

### llama.cpp (binary dependency)

`llama` is consumed as a SwiftPM `binaryTarget` pointing at the official release artifact `llama-bNNNN-xcframework.zip`. Pinned in [Package.swift](Package.swift) by URL + checksum so builds are reproducible. The xcframework's macOS-arm64 slice links into the .app at ~9 MB; the framework auto-links Accelerate / Metal / Foundation / `c++` via its module map.

When bumping the llama.cpp pin: download the new `xcframework.zip`, run `swift package compute-checksum <zip>`, update both the URL and the `checksum:` value in [Package.swift](Package.swift). Don't forget to delete `.build/` so the artifact cache fetches the new bytes.

The Gemma 4 E2B-it Q4_K_M GGUF (~3.46 GB, from `bartowski/google_gemma-4-E2B-it-GGUF`) is **not** bundled in the .app — it's downloaded on first enable into `~/Library/Application Support/Scribe/models/`. The expected size and SHA-256 are pinned in `ModelDescriptor.gemma4_E2B_it_Q4_K_M`; bumping the model is a deliberate product decision. Old files (e.g. the previous `qwen2.5-1.5b-instruct-q4_k_m.gguf` from v0.3.x) are left on disk as orphans for the user to delete manually — we don't auto-prune in case they want to roll back.

The model swap from Qwen2.5-1.5B → Gemma 4 E2B happened in the v0.4.x line. See [docs/polish-model-eval.md](docs/polish-model-eval.md) §Round 1 — Qwen 1.5B failed adversarial cases for persona-leak / question-answering / multilingual-preservation that Gemma 4 E2B handles; the trade-off is ~3× the download size (1 GB → 3.5 GB).

### MainActor isolation

`AppDelegate` is `@MainActor`-annotated; under Swift 6 strict concurrency the AppKit / NSApplication-driven flows here all need to live on the main actor. `PolishCoordinator` and the backends are also `@MainActor`. `Sources/ScribeApp/main.swift` wraps the boot sequence in `MainActor.assumeIsolated { ... }` to bridge from non-isolated top-level code to `AppDelegate`'s isolated init. Do not change these annotations without understanding the propagation — adding a non-MainActor escape hatch in any of these files will cascade compile errors across the module.

### Permissions

The app needs three OS permissions: **Microphone**, **Speech Recognition**, and **Accessibility**. Accessibility specifically is required for both the global Fn tap and for synthesizing `⌘V` into other apps. `applicationDidFinishLaunching` re-attempts `keyMonitor.start()` on `didBecomeActiveNotification` so the user can grant Accessibility in System Settings without relaunching.

### On-disk state

- `~/Library/Logs/Scribe.log` — application log
- `~/Library/Preferences/com.yetone.Scribe.plist` — UserDefaults; `selectedLocaleCode` is currently the only persisted key

### Sparkle

Auto-updates use [Sparkle](https://sparkle-project.org). The framework is embedded by `make build` into `Contents/Frameworks/`, with an explicit `@loader_path/../Frameworks` rpath set in [Package.swift](Package.swift) — without that rpath, dyld can't find Sparkle at runtime. The appcast lives on the website; [scripts/update_appcast.py](scripts/update_appcast.py) generates entries.

## README localization (BLOCKING pre-push check)

This repository ships localized READMEs in English, Simplified Chinese, Traditional Chinese, Japanese, and Korean. Treat each as a native-language document, not a line-by-line translation.

**Before every push, verify the READMEs are still consistent with the implementation.** Whenever a code change touches user-visible behavior — the menu, the overlay, the recognizer, the permissions story, the install flow, the privacy story, the architecture, or the on-disk files — re-read all five READMEs and update any drifted facts. Do not push if a README contradicts what the code actually does. This is mandatory; do not defer it as a follow-up.

### Localization principles

- Keep product facts consistent across languages: what Scribe does, supported platforms, install commands, privacy behavior, repository layout, and architecture.
- Localize structure and tone where needed — the localized README should sound natural to a native technical reader. Avoid translationese; do not preserve English sentence order when it makes the target language stiff.
- Keep commands, file paths, class names, and code symbols unchanged.
- Keep the language switcher at the top synchronized across all README files.
- Prefer clear product documentation over marketing copy.

### Recommended section order

1. Short product promise → 2. What Scribe is → 3. Main features → 4. System requirements → 5. Install from source → 6. First launch → 7. Usage → 8. Privacy → 9. Repository layout → 10. App architecture → 11. Acknowledgements → 12. License

### Language-specific notes

- **Simplified Chinese** (`README.zh-Hans.md`): natural Mainland Chinese technical writing. Prefer "本地", "语音识别", "源码", "隐私说明". Avoid overly literal phrases like "端侧运行" unless the context specifically needs them.
- **Traditional Chinese** (`README.zh-Hant.md`): natural Traditional Chinese for Taiwan/Hong Kong technical readers. Prefer "本機", "語音辨識", "選單列", "建置", "應用程式". Avoid Simplified-only phrasing.
- **Japanese** (`README.ja.md`): polite but concise technical documentation style. Avoid forced English word order. Use "音声認識", "音声入力", "メニューバー", "ローカル".
- **Korean** (`README.ko.md`): natural Korean documentation style. Use "음성 인식", "메뉴 막대", "로컬", "붙여 넣기". Avoid English-style sentence stacking.

### Privacy claim — must match implementation

Speech recognition is handled by Apple's `SFSpeechRecognizer`. On Apple Silicon running Sonoma or later, common languages typically recognize on-device; otherwise audio may transit Apple's servers under Apple's Speech Recognition privacy policy. The app makes no other outbound requests for recognition. The legacy LLM refinement path is disabled by default and not shown in the menu.

### Pre-finish checks

- Every localized README has the same language links at the top.
- Install commands are identical across languages.
- Privacy claims match the implementation (above).
- Markdown tables and fenced code blocks render cleanly.
