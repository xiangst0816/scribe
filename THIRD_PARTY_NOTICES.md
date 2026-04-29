# Third-party notices

Scribe ships with code and assets from the following third-party projects.

## llama.cpp

[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — MIT License.

The macOS arm64 slice of the official `llama-bNNNN-xcframework.zip` release artifact is linked into the Scribe binary at build time and embedded as `Contents/Frameworks/llama.framework`. Pinned by URL + SHA-256 in [Package.swift](Package.swift) for reproducible builds.

## Sparkle

[sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) — MIT-style license (see [Sparkle's LICENSE](https://github.com/sparkle-project/Sparkle/blob/master/LICENSE)).

Embedded as `Contents/Frameworks/Sparkle.framework`. Powers the in-app updater.

## Lucide

[lucide-icons/lucide](https://github.com/lucide-icons/lucide) — [ISC License](https://github.com/lucide-icons/lucide/blob/main/LICENSE).

The Scribe app icon and menu-bar template images are derived from the geometry of [Lucide's `audio-waveform`](https://lucide.dev/icons/audio-waveform) glyph. The path data has been embedded into our SVG sources at [docs/logo-concepts/](docs/logo-concepts/) and rasterized into [AppIcon.icns](AppIcon.icns) and [Resources/](Resources/).

## Gemma 4 E2B-it (downloaded at runtime)

[google/gemma-4-E2B-it](https://huggingface.co/google/gemma-4-E2B-it) — [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

The Local polish backend downloads a quantized GGUF build of this model on first enable, into `~/Library/Application Support/Scribe/models/`. The model is **not** bundled inside the .app — it is fetched at runtime from a mirror chain (HuggingFace / ModelScope / hf-mirror.com). See [Sources/Scribe/Refinement/](Sources/Scribe/Refinement/).
