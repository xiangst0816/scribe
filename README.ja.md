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
| `~/Library/Preferences/com.yetone.Scribe.plist` | 選択中の言語などの UserDefaults |

## プライバシー

- 音声認識は Apple 標準の `SFSpeechRecognizer` を使います。Apple Silicon の Mac で Sonoma 以降の場合、対応 4 言語は通常オンデバイスで処理されます。それ以外の条件では、Apple の[音声認識プライバシーポリシー](https://www.apple.com/legal/privacy/data/ja/speech-recognition/)に従って音声が Apple のサーバーに送信されることがあります。
- Scribe 自体はそれ以外の外部ネットワークアクセスを行いません。例外として、デフォルトでは無効化されている LLM 整形ルートを手動で再有効化した場合のみ、OpenAI 互換 API を呼び出します。これはメニューには表示されません。
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
├── SpeechProvider         ── 認識エンジンのプロトコル。start/stop/cancel と onAudioLevel/onPartialResult/onFinalResult を定義
│   └── AppleSpeechProvider    ── SFSpeechRecognizer を使ったストリーミング認識。音量計付き
├── OverlayPanel           ── ボーダーレス NSPanel。波形カプセルと上に浮かぶリアルタイム字幕ピルを担当
├── TextInjector           ── クリップボード + ⌘V でテキストを挿入し、入力ソース切替も処理
└── AppDelegate            ── メニューバー UI、ステータスアイコン、録音ライフサイクル
```

アプリ全体は数百行の Swift で、`ScribeCore` ライブラリと薄い実行ファイルに分かれています。Xcode プロジェクトはなく、[Package.swift](Package.swift) と小さな [Makefile](Makefile) だけで、`swift build`、`.app` の作成、ad-hoc 署名をまとめています。テストは `swift test` で実行できます。

## 謝辞

- [Sparkle](https://sparkle-project.org)：自動アップデートフレームワーク。
- Apple [Speech](https://developer.apple.com/documentation/speech) フレームワーク：認識のコア。

## ライセンス

[MIT](LICENSE) © Scribe contributors.
