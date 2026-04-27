<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

**English** · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**Hold a key. Talk. Get text — anywhere on your Mac.**

Local, private, push-to-talk dictation for macOS — powered by [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) running entirely on-device.

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Why Scribe

Scribe lives in your menu bar. Press and hold the **Fn** key, speak, release — and the recognized text is pasted directly into whatever text field has focus, in any app. No network round-trip, no cloud account, no subtitles file you have to copy out of.

Speech recognition runs locally via OpenAI Whisper models compiled to CoreML, so audio never leaves your Mac.

## Features

- **Push-to-talk anywhere** — hold `Fn`, speak, release. Works in Safari, VS Code, Slack, Notes, native text fields, web inputs, even Terminal.
- **Local Whisper inference** — three quality tiers (Fast / Balanced / High Quality) backed by `openai_whisper-base / small_216MB / large-v3-v20240930_626MB`. Models download once, run offline thereafter.
- **Apple Speech fallback** — usable instantly while a Whisper model is downloading or loading.
- **Multilingual** — English, 中文 (简体/繁體), 日本語, 한국어. Whisper detects automatically; the menu lets you lock a language for short utterances.
- **Live audio level overlay** — a small glassmorphic capsule near the bottom of the screen shows you it's listening.
- **CJK-friendly paste** — temporarily swaps to an ASCII input source while pasting, so Chinese / Japanese / Korean IMEs don't intercept the `⌘V`.
- **Menu-bar only** — no Dock icon, no window. `LSUIElement = true`.
- **~5 MB binary** — Whisper models live next to the app in Application Support; the binary itself is tiny.

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon recommended (Whisper runs on the Neural Engine via CoreML)
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
3. The Balanced model (~210 MB) starts downloading in the background. The menu bar icon shows progress; in the meantime Apple's built-in speech recognizer handles transcription.
4. Once downloaded, the menu top will read **Balanced · Active**. From now on, everything runs locally.

## Usage

| Action | Result |
|---|---|
| Hold `Fn` | Begin recording. A "Listening…" capsule appears with a live waveform. |
| Release `Fn` | "Transcribing…" briefly, then the text is pasted at the cursor. |
| Menu bar → **Voice Quality** | Switch among Fast / Balanced / High Quality. Switching downloads the model on demand. |
| Menu bar → **Language** | Lock a language for Whisper, or pick System Default for auto-detect. |
| Menu bar → **Enabled** | Toggle the global `Fn` listener without quitting. |

### Keyboard shortcut

The hotkey is currently hard-coded to **Fn**. Change `KeyMonitor.swift` if you want a different modifier — patches welcome.

### Files on disk

| Path | Purpose |
|---|---|
| `~/Library/Application Support/Scribe/Models/<variant>/` | Downloaded CoreML model bundles |
| `~/Library/Logs/Scribe.log` | Application log |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults (selected language, selected quality) |

## Repository layout

This is a monorepo containing the Mac app and the marketing website.

```
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/Scribe/                ← Swift app source
├── web/                           ← Astro marketing site (deployed to Cloudflare Pages)
└── .github/workflows/
    └── deploy-web.yml             ← path-triggered web deploy
```

The Mac app and the site share **no build dependencies** — they're independent. The website is rebuilt and redeployed only when files under `web/` change. See [web/README.md](web/README.md) for the website's setup, dev workflow, and Cloudflare configuration.

## Architecture

```
Scribe.app
├── KeyMonitor          ── CGEventTap on .flagsChanged, watches the Fn flag
├── SpeechProvider      ── protocol — start/stop/cancel + onAudioLevel/onFinalResult
│   ├── AppleSpeechProvider    ── SFSpeechRecognizer streaming, used as fallback
│   └── WhisperSpeechProvider  ── WhisperKit + AudioProcessor, push-to-talk transcription
├── ModelManager        ── tier mapping, HF download with progress, CoreML load/prewarm
├── OverlayPanel        ── borderless NSPanel + waveform animation
├── TextInjector        ── clipboard-and-⌘V paste, with IME swap dance
└── AppDelegate         ── menu bar UI, status icon, provider selection
```

The whole app is around 1,500 lines of Swift. There's no Xcode project — only [Package.swift](Package.swift) plus a small [Makefile](Makefile) that wraps `swift build` with the `.app` bundling and ad-hoc codesign.

## Privacy

- **No network requests** are made for speech recognition once a model is downloaded.
- The only outbound network calls are: (a) HuggingFace, when downloading a model variant the first time you select it, and (b) optionally the OpenAI-compatible LLM endpoint, if you re-enable the legacy LLM-refinement code path (disabled by default and absent from the menu).
- Audio is buffered in memory only for the duration of a single push-to-talk hold, then discarded.

## Acknowledgements

- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) — WhisperKit, the Swift+CoreML port of OpenAI Whisper.
- [OpenAI Whisper](https://github.com/openai/whisper) — the speech recognition models.

## License

[MIT](LICENSE) © Scribe contributors.
