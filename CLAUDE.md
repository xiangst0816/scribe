# Multilingual README Guidelines

This repository includes localized README files for English, Simplified Chinese, Traditional Chinese, Japanese, and Korean. When editing them, treat each file as a native-language document, not as a line-by-line translation of `README.md`.

## Pre-push checklist (BLOCKING)

**Before every push, verify the READMEs are still consistent with the implementation.** Whenever a code change touches user-visible behavior — the menu, the overlay, the recognizer, the permissions story, the install flow, the privacy story, the architecture, or the on-disk files — re-read all five READMEs and update any drifted facts. Do not push if a README contradicts what the code actually does. This is mandatory; do not defer it as a follow-up.

## Core Principles

- Keep product facts consistent across languages: what Scribe does, supported platforms, install commands, privacy behavior, repository layout, and architecture.
- Localize structure and tone where needed. The localized README should sound natural to a native technical reader in that language.
- Avoid translationese. Do not preserve English sentence order when it makes the target language stiff or unnatural.
- Prefer clear product documentation over marketing copy. Scribe is a practical menu bar utility; explain the workflow plainly.
- Keep commands, file paths, class names, and code symbols unchanged.
- Keep the language switcher at the top synchronized across all README files.

## Recommended Structure

Use this general order unless there is a strong reason not to:

1. Short product promise
2. What Scribe is
3. Main features
4. System requirements
5. Install from source
6. First launch
7. Usage
8. Privacy
9. Repository layout
10. App architecture
11. Acknowledgements
12. License

This order works better for readers who want to quickly understand the app before scanning setup and implementation details.

## Language Notes

- Simplified Chinese (`README.zh-Hans.md`): use natural Mainland Chinese technical writing. Prefer terms like "本地", "语音识别", "源码", "隐私说明", and avoid overly literal phrases such as "端侧运行" unless the context specifically needs them.
- Traditional Chinese (`README.zh-Hant.md`): use natural Traditional Chinese for Taiwan/Hong Kong technical readers. Prefer "本機", "語音辨識", "選單列", "建置", and "應用程式". Avoid Simplified-only phrasing.
- Japanese (`README.ja.md`): write in polite but concise Japanese technical documentation style. Avoid forced English word order. Use terms like "音声認識", "音声入力", "メニューバー", and "ローカル".
- Korean (`README.ko.md`): write in natural Korean documentation style. Use "음성 인식", "메뉴 막대", "로컬", "붙여 넣기", and avoid English-style sentence stacking.

## Consistency Checks

Before finishing README localization work:

- Confirm every localized README has the same language links.
- Confirm install commands are identical across languages.
- Confirm privacy claims match the implementation: speech recognition is handled by Apple's `SFSpeechRecognizer`. On Apple Silicon running Sonoma or later, common languages typically recognize on-device; otherwise audio may transit Apple's servers under Apple's Speech Recognition privacy policy. The app makes no other outbound requests for recognition. The legacy LLM refinement path is disabled by default and not shown in the menu.
- Confirm Markdown tables and fenced code blocks render cleanly.
