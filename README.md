<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

**English** · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**Hold a key. Talk. Get text — anywhere on your Mac.**

A small, focused push-to-talk dictation utility for macOS. Lives in the menu bar; pastes the recognized text wherever your cursor is.

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Why Scribe

Scribe lives in your menu bar. Press and hold the **Fn** key, speak, release — and the recognized text is pasted directly into whatever text field has focus, in any app. No network round-trip if your Mac supports on-device dictation, no cloud account, no subtitles file you have to copy out of.

Scribe uses macOS's built-in speech recognizer (`SFSpeechRecognizer`). On Apple Silicon Macs running Sonoma or later, recognition for major languages typically runs on-device; otherwise audio may transit Apple's servers per Apple's Speech Recognition privacy policy.

## Features

- **Push-to-talk anywhere** — hold `Fn`, speak, release. Works in Safari, VS Code, Slack, Notes, native text fields, web inputs, even Terminal.
- **Live transcript pill** — a frosted glass capsule above the audio waveform shows the current sentence as you speak, so you can see what's being heard before you let go.
- **Trailing buffer** — recording continues for ~500ms after you release `Fn`, so a sentence you're a beat slow finishing doesn't get cut off. Re-pressing `Fn` during the buffer extends the same recording instead of restarting.
- **Multilingual** — English, 中文 (简体/繁體), 日本語, 한국어. The menu lets you lock a language or follow the system default.
- **CJK-friendly paste** — temporarily swaps to an ASCII input source while pasting, so Chinese / Japanese / Korean IMEs don't intercept the `⌘V`.
- **Optional on-device polishing** — an advanced setting can clean up filler words and disfluencies via either Apple Intelligence (macOS 26+, supported regions) or a downloaded local model (Gemma 4 E2B, ~3.5 GB). Off by default. Polishing always runs locally — no transcript ever leaves your Mac.
- **Screen-context for polish (experimental)** — an opt-in sub-toggle under polishing. On `Fn`-down, Scribe takes one screenshot of the focused window and runs Apple's Vision text recognizer on it; the recognized text is fed to the polish step as a "what the user is looking at" hint, so proper nouns and identifiers visible on screen are spelled consistently. Off by default. Requires Screen Recording permission. Pixels never leave the Mac.
- **Menu-bar only** — no Dock icon, no window. `LSUIElement = true`.

## Requirements

- macOS 14.0 (Sonoma) or later
- A locale supported by macOS speech recognition (English, 中文, 日本語, 한국어 are all covered out of the box)
- Xcode Command Line Tools (`xcode-select --install`)

## Install from source

```bash
git clone https://github.com/xiangst0816/scribe.git
cd scribe
make install        # builds and copies to /Applications/Scribe.app
```

Or to build without installing:

```bash
make build          # produces ./Scribe.app
make run            # build and launch
make clean          # remove build artifacts
```

## First launch

1. Open `Scribe.app`. It appears in the menu bar with the Scribe icon.
2. macOS will prompt for **Microphone**, **Speech Recognition**, and **Accessibility** permissions. Grant all three.
   - Accessibility is required to detect the `Fn` key globally and to paste into other apps.
3. That's it — there's nothing to download. Hold `Fn`, speak, release.

## Usage

| Action | Result |
|---|---|
| Hold `Fn` | Begin recording. A waveform capsule appears at the bottom of the screen, with a transcript pill above it showing what you're saying. |
| Release `Fn` | A 0.5s trailing buffer captures any final words, then the text is pasted at the cursor. |
| Menu bar → **Language** | Lock a language for recognition, or pick System Default to follow the OS. |
| Menu bar → **Enabled** | Toggle the global `Fn` listener without quitting. |

### Keyboard shortcut

The hotkey is currently hard-coded to **Fn**. Change [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) if you want a different modifier — patches welcome.

### Files on disk

| Path | Purpose |
|---|---|
| `~/Library/Logs/Scribe.log` | Application log |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults (selected language) |

## Repository layout

This is a monorepo containing the Mac app and the marketing website.

```
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/
│   ├── Scribe/                    ← ScribeCore library — all the app logic
│   └── ScribeApp/main.swift       ← thin executable, just runs NSApplication
├── Tests/ScribeCoreTests/         ← XCTest unit tests
├── web/                           ← Astro marketing site (deployed to Cloudflare Pages)
└── .github/workflows/
    └── deploy-web.yml             ← path-triggered web deploy
```

The Mac app and the site share **no build dependencies** — they're independent. The website is rebuilt and redeployed only when files under `web/` change. See [web/README.md](web/README.md) for the website's setup, dev workflow, and Cloudflare configuration.

## Architecture

```
Scribe.app
├── KeyMonitor             ── CGEventTap on .flagsChanged, watches the Fn flag
├── AppleSpeechSession     ── SFSpeechRecognizer streaming, with audio-level metering
├── OverlayPanel           ── borderless NSPanel with frosted-glass capsule + live transcript pill
├── TextInjector           ── clipboard-and-⌘V paste, with IME swap dance
├── Refinement/            ── optional transcript polishing (off by default)
│   ├── PolishCoordinator      ── arbitration, 3 s timeout, circuit breaker
│   ├── SystemPolishService    ── Apple Intelligence (macOS 26+, supported regions)
│   ├── LocalPolishService     ── Gemma 4 E2B GGUF via llama.cpp + downloader
│   ├── ScreenContextCapture   ── (optional) screen-context dispatcher + log sink
│   └── OCRContextSource       ── ScreenCaptureKit + Vision OCR for the polish prompt
├── SettingsWindow         ── master toggle + System/Local backend pickers
└── AppDelegate            ── menu bar UI, status icon, recording lifecycle
```

The Mac app is split across the `ScribeCore` library and a thin executable. There's no Xcode project — only [Package.swift](Package.swift) plus a small [Makefile](Makefile) that wraps `swift build` with the `.app` bundling and ad-hoc codesign. Run the test suite with `swift test` (XCTest, requires Xcode for local runs; CI uses the `macos-15` runner).

llama.cpp ships as a binary `xcframework` consumed via SwiftPM `binaryTarget` — no CMake or Xcode required for Scribe builds. The arm64 framework is ~9 MB linked into the .app; the model weights live separately under `~/Library/Application Support/Scribe/`.

## Privacy

- **Speech recognition** is handled by Apple's `SFSpeechRecognizer`. On Apple Silicon Macs running Sonoma or later, recognition for the four supported languages typically runs on-device; under other conditions, audio may be transmitted to Apple's servers under Apple's [Speech Recognition](https://www.apple.com/legal/privacy/data/en/speech-recognition/) privacy policy.
- **Optional polishing** has two engines, both fully local at inference time:
  - *System* — Apple Intelligence's on-device language model. No download. Available on macOS 26+ in supported regions.
  - *Scribe local model* — Gemma 4 E2B-it (~3.5 GB). Downloaded once on first enable from HuggingFace or ModelScope; the URL and SHA-256 are baked into the binary. After download, all polishing runs entirely locally — no network traffic.
- Polishing is **off by default**. When enabled, the raw transcript is fed to the chosen on-device engine before pasting; on any timeout or error, Scribe falls back to the raw transcript so you don't lose the recording.
- **Screen-context for polish** is a separate experimental sub-toggle, also off by default. When enabled, Scribe takes one screenshot of the focused window at `Fn`-down and runs Apple's Vision text recognizer on it locally; the recognized text is folded into the polish prompt as a hint and the image is discarded after recognition. Requires Screen Recording permission. The image is processed in memory only — never written to disk, never transmitted. Per-capture activity is logged to `~/Library/Logs/Scribe.log` for verification.
- Audio is buffered in memory only for the duration of a single push-to-talk hold (plus the 500 ms trailing buffer), then discarded.

## Acknowledgements

- [Sparkle](https://sparkle-project.org) — auto-update framework.
- Apple's [Speech](https://developer.apple.com/documentation/speech) framework — the underlying recognizer.
- [llama.cpp](https://github.com/ggml-org/llama.cpp) — local-model inference engine (MIT).
- [Gemma 4 E2B-it](https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF) by Google (GGUF quant by bartowski) — local-polishing model (Apache 2.0).

## License

[MIT](LICENSE) © Scribe contributors.
