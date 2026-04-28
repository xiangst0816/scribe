<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · [繁體中文](README.zh-Hant.md) · **日本語** · [한국어](README.ko.md)

**Fn を押しながら話して、離す。いまのカーソル位置にそのまま文字が入ります。**

macOS のメニューバーに常駐する、軽量なプッシュ・トゥ・トーク音声入力ツールです。OS 標準の音声認識を使うので、モデルのダウンロードや別ウィンドウの表示はありません。

[![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe について

Scribe が解決したいのは、とても小さいけれど毎日ひっかかる問題です。コードを書いているとき、返信を書いているとき、メモを取っているときに、少しだけ音声で入力したい。でもアプリを切り替えたくないし、システムの音声入力を呼び出したくもない。クラウドの文字起こしを待つほどでもない。

Scribe はメニューバーに常駐します。**Fn** を押しながら話し、離すと、認識されたテキストが現在フォーカスされている入力欄に自動で貼り付けられます。Safari、VS Code、Slack、メモ、Web の入力欄、ターミナルなどでそのまま使えます。

音声認識は OS 標準の `SFSpeechRecognizer` で行います。Apple Silicon の Mac で Sonoma 以降を使っている場合、主要な言語は通常オンデバイスで認識されます。それ以外の場合は、Apple の音声認識プライバシーポリシーに従って音声が Apple のサーバーに送信されることがあります。

## 主な機能

- **どこでもプッシュ・トゥ・トーク**：`Fn` を押して録音し、離すと文字起こししてカーソル位置へ貼り付けます。
- **リアルタイム字幕ピル**：録音中、波形カプセルの上に半透明のピルが浮かび、いま話している一文をリアルタイムに表示します。指を離す前に認識結果を確認できます。
- **末尾バッファ**：`Fn` を離した後も約 500 ミリ秒だけ録音を続けます。語尾を少し言い遅れても切れません。バッファ中に再び `Fn` を押せば、同じ録音を切らさずに延長できます。
- **多言語対応**：英語、中国語（簡体字/繁体字）、日本語、韓国語に対応。メニューから言語を固定するか、システム設定に従わせられます。
- **CJK 入力環境に配慮した貼り付け**：貼り付け前に一時的に ASCII 入力ソースへ切り替え、IME が `⌘V` を横取りするのを避けます。
- **オプションのオンデバイス整形**（既定オフ）：「整形設定」から有効化し、システム内蔵モデル（macOS 26 + Apple Intelligence の対応地域）または Scribe 同梱の Gemma 4 E2B ローカルモデル（約 3.5 GB、ダウンロード）から選べます。どちらの経路も推論はすべて Mac 内で完結し、文字起こしは Mac の外に出ません。
- **画面内容を整形のヒントに利用**（実験的・既定オフ）：整形を有効にした上で、追加で有効化できるサブトグルです。`Fn` を押した瞬間にフォーカス中のウィンドウをスクリーンショットして Apple Vision の文字認識を実行し、その結果を「ユーザーが今見ているもの」のヒントとして整形モデルに渡します。画面に映っている固有名詞、ファイル名、識別子が整形後のテキストでも一貫して綴られるようになります。画面収録の権限が必要です。スクリーンショットはメモリ上だけで処理され、ディスクには保存されず、外部にも送信されません。
- **メニューバー専用**：Dock アイコンもメインウィンドウもありません。

## 動作環境

- macOS 14.0 Sonoma 以降
- macOS の音声認識が対応している言語（英語、中国語、日本語、韓国語はそのまま使えます）
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

1. `Scribe.app` を開きます。起動するとメニューバーに Scribe のアイコンが表示されます。
2. macOS の案内に従って、**マイク**、**音声認識**、**アクセシビリティ** の権限を許可します。
   - アクセシビリティ権限は、`Fn` キーをグローバルに監視し、ほかのアプリへ認識結果を貼り付けるために使います。
3. ダウンロードするモデルはありません。許可が終われば `Fn` を押してすぐ使えます。

## 使い方

| 操作 | 結果 |
|---|---|
| `Fn` を押し続ける | 録音を開始します。画面下部に波形カプセルが表示され、その上に浮かぶピルが現在話している一文をリアルタイムに表示します。 |
| `Fn` を離す | 約 500 ミリ秒の末尾バッファののち録音を終了し、現在のカーソル位置にテキストを貼り付けます。 |
| メニューバー → **言語** | 認識する言語を固定するか、システム設定に従って自動選択します。 |
| メニューバー → **有効** | アプリを終了せずに、グローバルな `Fn` 監視を一時的にオン/オフします。 |

### ショートカット

現在のホットキーは **Fn** 固定です。別の修飾キーにしたい場合は [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) から変更できます。PR も歓迎します。

### ローカルに保存されるファイル

| パス | 内容 |
|---|---|
| `~/Library/Logs/Scribe.log` | アプリケーションログ |
| `~/Library/Preferences/com.yetone.Scribe.plist` | 選択中の言語と整形機能の設定（UserDefaults） |
| `~/Library/Application Support/Scribe/models/` | ローカル整形モデル（Local エンジンを有効化してダウンロードした場合のみ存在） |

## プライバシー

- 音声認識は Apple 標準の `SFSpeechRecognizer` を使います。Apple Silicon の Mac で Sonoma 以降の場合、対応 4 言語は通常オンデバイスで処理されます。それ以外の条件では、Apple の[音声認識プライバシーポリシー](https://www.apple.com/legal/privacy/data/ja/speech-recognition/)に従って音声が Apple のサーバーに送信されることがあります。
- オプションの整形機能（既定オフ）には 2 つのエンジンがあり、**推論はいずれも Mac 内で完結します**：
  - *システム* — macOS 内蔵の Apple Intelligence オンデバイスモデル。ダウンロード不要。macOS 26+ かつ対応地域でのみ利用可能。
  - *Scribe ローカルモデル* — Gemma 4 E2B-it（約 3.5 GB）。初回有効化時に ModelScope または HuggingFace から一度だけダウンロードします。ダウンロード URL と SHA-256 はバイナリに焼き込まれています。ダウンロード後はすべての整形が完全にローカルで実行されます。
- 整形を有効化すると、貼り付け前に文字起こしが選択したエンジンを通ります。タイムアウトやエラー時はそのまま元の文字起こしを貼り付けるため、録音内容が失われることはありません。
- **画面内容を整形のヒントに利用**もまた、既定オフの実験的サブトグルです。有効にすると、`Fn` を押した瞬間に Scribe がフォーカス中のウィンドウのスクリーンショットを 1 枚撮り、Mac 上で Apple Vision による文字認識を実行します。認識結果は整形モデルへのヒントとして渡され、画像は認識完了後に破棄されます。画面収録の権限が必要です。画像はメモリ上でのみ処理され、ディスクへは書き込まれず、外部にも送信されません。各キャプチャの内容は `~/Library/Logs/Scribe.log` に記録され、検証できます。
- 音声は 1 回のキー押下中（500 ミリ秒の末尾バッファを含む）だけメモリ上に保持され、文字起こし後に破棄されます。

## リポジトリ構成

このリポジトリには macOS アプリと公式サイトが入っています。2 つは独立しています。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/
│   ├── Scribe/                    ← ScribeCore ライブラリ。アプリのロジックすべて
│   └── ScribeApp/main.swift       ← NSApplication を起動するだけの薄い実行ファイル
├── Tests/ScribeCoreTests/         ← XCTest 単体テスト
├── web/                           ← Astro 製の公式サイト。Cloudflare Pages にデプロイ
└── .github/workflows/
    └── deploy-web.yml             ← web/ の変更時だけ公式サイトをデプロイ
```

アプリと公式サイトはビルド依存を共有していません。サイト側の開発、ビルド、Cloudflare 設定については [web/README.md](web/README.md) を参照してください。

## アプリの構成

```text
Scribe.app
├── KeyMonitor             ── CGEventTap で .flagsChanged を監視し、Fn の状態を取得
├── AppleSpeechSession     ── SFSpeechRecognizer を使ったストリーミング認識。音量計付き
├── OverlayPanel           ── ボーダーレス NSPanel。波形カプセルと上に浮かぶリアルタイム字幕ピルを担当
├── TextInjector           ── クリップボード + ⌘V でテキストを挿入し、入力ソース切替も処理
├── Refinement/            ── オプションの文字起こし整形（既定オフ）
│   ├── PolishCoordinator      ── エンジン仲裁、3 秒タイムアウト、連続失敗時のサーキットブレーカー
│   ├── SystemPolishService    ── Apple Intelligence（macOS 26+、対応地域のみ）
│   ├── LocalPolishService     ── llama.cpp 経由で Gemma 4 E2B GGUF を呼び出し + ダウンロード層
│   ├── ScreenContextCapture   ── （任意）画面コンテキストの分配とログ書き込み
│   └── OCRContextSource       ── ScreenCaptureKit でスクリーンショットを撮り Vision OCR で文字認識して整形モデルに渡す
├── SettingsWindow         ── 整形のマスタートグル + System/Local エンジン切替
└── AppDelegate            ── メニューバー UI、ステータスアイコン、録音ライフサイクル
```

アプリのコードは `ScribeCore` ライブラリと薄い実行ファイルに分かれています。Xcode プロジェクトはなく、[Package.swift](Package.swift) と小さな [Makefile](Makefile) だけで、`swift build`、`.app` の作成、ad-hoc 署名をまとめています。テストは `swift test` で実行できます（XCTest は Xcode が必要。CI は `macos-15` ランナーを使用）。

llama.cpp は SwiftPM の `binaryTarget` で公式リリースの `xcframework` を取り込みます。ローカルビルドに CMake や Xcode は不要です。.app への組み込みサイズは約 9 MB で、モデルの重みは別途 `~/Library/Application Support/Scribe/` に保存されます。

## 謝辞

- [Sparkle](https://sparkle-project.org)：自動アップデートフレームワーク。
- [llama.cpp](https://github.com/ggml-org/llama.cpp)：ローカルモデル推論エンジン（MIT）。
- [Gemma 4 E2B-it](https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF)（Google、GGUF 量子化は bartowski 提供）：ローカル整形モデル（Apache 2.0）。
- Apple [Speech](https://developer.apple.com/documentation/speech) フレームワーク：認識のコア。

## ライセンス

[MIT](LICENSE) © Scribe contributors.
