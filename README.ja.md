<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · **日本語** · [한국어](README.ko.md)

**Fn を押しながら話して、離す。いまのカーソル位置にそのまま文字が入ります。**

macOS のメニューバーに常駐する、ローカル処理の音声入力ツールです。[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) を使い、認識はあなたの Mac 上で行います。デフォルトでは音声をクラウドへ送りません。

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe について

Scribe が解決したいのは、とても小さいけれど毎日ひっかかる問題です。コードを書いているとき、返信を書いているとき、メモを取っているときに、少しだけ音声で入力したい。でもアプリを切り替えたくないし、システムの音声入力を呼び出したくもない。クラウドの文字起こしを待つほどでもない。

Scribe はメニューバーに常駐します。**Fn** を押しながら話し、離すと、認識されたテキストが現在フォーカスされている入力欄に自動で貼り付けられます。Safari、VS Code、Slack、メモ、Web の入力欄、ターミナルなどでそのまま使えます。

音声認識は、CoreML 向けに変換された OpenAI Whisper モデルでローカル実行されます。モデルを一度ダウンロードすれば、普段の音声入力にネットワーク接続は不要で、音声が Mac の外へ出ることもありません。

## 主な機能

- **どこでもプッシュ・トゥ・トーク**：`Fn` を押して録音し、離すと文字起こししてカーソル位置へ貼り付けます。
- **ローカル Whisper 認識**：高速、バランス、高品質の 3 モードを用意しています。それぞれ `openai_whisper-base`、`openai_whisper-small_216MB`、`openai_whisper-large-v3-v20240930_626MB` に対応し、モデルは一度だけダウンロードされます。
- **すぐ使えるフォールバック**：Whisper モデルのダウンロード中や読み込み中は Apple Speech を使います。
- **多言語対応**：英語、中国語（簡体字/繁体字）、日本語、韓国語に対応。Whisper による自動判定のほか、短い発話ではメニューから言語を固定できます。
- **録音状態の表示**：録音中は画面下部に小さなオーバーレイを表示し、リアルタイムの音量を示します。
- **CJK 入力環境に配慮した貼り付け**：貼り付け前に一時的に ASCII 入力ソースへ切り替え、IME が `⌘V` を横取りするのを避けます。
- **メニューバー専用**：Dock アイコンもメインウィンドウもありません。
- **小さなアプリ本体**：バイナリは約 5 MB。Whisper モデルは Application Support 以下に別途保存されます。

## 動作環境

- macOS 14.0 Sonoma 以降
- Apple Silicon Mac 推奨。Whisper は CoreML 経由で Neural Engine を利用します
- Xcode Command Line Tools

未インストールの場合は、次のコマンドで入れられます。

```bash
xcode-select --install
```

## ソースからインストール

```bash
git clone https://github.com/xiangst0816/scribe.git
cd scribe
make install        # ビルドして /Applications/Scribe.app にコピー
```

インストールせずにビルドやデバッグだけ行う場合：

```bash
make build          # ./Scribe.app を生成
make run            # ビルドして起動
make clean          # ビルド成果物を削除
```

## 初回起動

1. `Scribe.app` を開きます。起動するとメニューバーにペン先のアイコンが表示されます。
2. macOS の案内に従って、**マイク**、**音声認識**、**アクセシビリティ** の権限を許可します。
   - アクセシビリティ権限は、`Fn` キーをグローバルに監視し、ほかのアプリへ認識結果を貼り付けるために使います。
3. デフォルトの「バランス」モデルがバックグラウンドでダウンロードされます。サイズは約 210 MB です。進捗はメニューバーアイコンに表示されます。
4. ダウンロードが完了すると、メニュー上部に **バランス · 有効** と表示されます。以降はローカル Whisper で認識します。

モデルのダウンロード中でも Scribe は使えます。その間は一時的に Apple Speech で認識します。

## 使い方

| 操作 | 結果 |
|---|---|
| `Fn` を押し続ける | 録音を開始し、画面下部に音量オーバーレイを表示します。 |
| `Fn` を離す | 録音を終了し、少し待つと現在のカーソル位置にテキストを貼り付けます。 |
| メニューバー → **音声品質** | 高速、バランス、高品質を切り替えます。未ダウンロードのモデルは必要に応じて取得されます。 |
| メニューバー → **言語** | 言語を自動判定するか、特定の言語に固定します。 |
| メニューバー → **有効** | アプリを終了せずに、グローバルな `Fn` 監視を一時的にオン/オフします。 |

### ショートカット

現在のホットキーは **Fn** 固定です。別の修飾キーにしたい場合は [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) から変更できます。PR も歓迎します。

### ローカルに保存されるファイル

| パス | 内容 |
|---|---|
| `~/Library/Application Support/Scribe/Models/<variant>/` | ダウンロード済みの CoreML モデル |
| `~/Library/Logs/Scribe.log` | アプリケーションログ |
| `~/Library/Preferences/com.yetone.Scribe.plist` | 言語や音声品質などの UserDefaults |

## プライバシー

- モデルのダウンロード後、音声認識そのものはネットワークリクエストを行いません。
- 通常利用時、音声は 1 回のキー押下中だけメモリ上に保持され、文字起こし後に破棄されます。
- ネットワークを使うのは主に 2 つの場合です。初めて選んだ Whisper モデルを Hugging Face からダウンロードするとき。もう 1 つは、古い LLM 整形ルートを手動で再有効化し、OpenAI 互換 API を呼び出すときです。後者はデフォルトで無効で、メニューにも表示されません。

## リポジトリ構成

このリポジトリには macOS アプリと公式サイトが入っています。2 つは独立しています。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/Scribe/                ← Swift アプリのソースコード
├── web/                           ← Astro 製の公式サイト。Cloudflare Pages にデプロイ
└── .github/workflows/
    └── deploy-web.yml             ← web/ の変更時だけ公式サイトをデプロイ
```

アプリと公式サイトはビルド依存を共有していません。サイト側の開発、ビルド、Cloudflare 設定については [web/README.md](web/README.md) を参照してください。

## アプリの構成

```text
Scribe.app
├── KeyMonitor          ── CGEventTap で .flagsChanged を監視し、Fn の状態を取得
├── SpeechProvider      ── 認識エンジンのプロトコル。start/stop/cancel とコールバックを定義
│   ├── AppleSpeechProvider    ── SFSpeechRecognizer を使ったフォールバック認識
│   └── WhisperSpeechProvider  ── WhisperKit + AudioProcessor によるローカル認識
├── ModelManager        ── モデルモード、ダウンロード進捗、CoreML の読み込みとプリウォーム
├── OverlayPanel        ── ボーダーレス NSPanel。録音オーバーレイと波形アニメーションを担当
├── TextInjector        ── クリップボード + ⌘V でテキストを挿入し、入力ソース切替も処理
└── AppDelegate         ── メニューバー UI、ステータスアイコン、認識エンジンの選択
```

アプリ全体は約 1,500 行の Swift です。Xcode プロジェクトはなく、[Package.swift](Package.swift) と小さな [Makefile](Makefile) だけで、`swift build`、`.app` の作成、ad-hoc 署名をまとめています。

## 謝辞

- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)：OpenAI Whisper を Swift + CoreML で扱う WhisperKit。
- [OpenAI Whisper](https://github.com/openai/whisper)：音声認識モデル。

## ライセンス

[MIT](LICENSE) © Scribe contributors.
