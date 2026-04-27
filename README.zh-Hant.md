<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · **繁體中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

**按住 Fn，說話，放開。文字就會出現在目前游標的位置。**

一款常駐在 macOS 選單列的本機聽寫工具。基於 [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)，語音辨識在你的 Mac 上完成，預設不會把音訊送到雲端。

[![平台: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe 是什麼

Scribe 解決的是一個很日常、也很煩人的問題：你正在寫程式、回訊息、做筆記，突然想用語音輸入一段文字，但不想切換 App、不想叫出系統聽寫，也不想等雲端轉錄。

它會待在選單列。按住 **Fn** 開始說話，放開後，辨識出的文字會自動貼到目前取得焦點的輸入位置。Safari、VS Code、Slack、備忘錄、網頁輸入框、終端機，都可以直接用。

語音辨識由編譯成 CoreML 的 OpenAI Whisper 模型在本機完成。模型下載好之後，日常聽寫不需要網路，音訊也不會離開你的電腦。

## 主要特色

- **全域按鍵說話**：按住 `Fn` 錄音，放開後轉成文字並貼到游標處。
- **本機 Whisper 辨識**：提供快速、平衡、高品質三種模式，分別對應 `openai_whisper-base`、`openai_whisper-small_216MB`、`openai_whisper-large-v3-v20240930_626MB`。模型只需下載一次，之後可離線使用。
- **可立即使用的備援辨識**：Whisper 模型下載或載入期間，會先使用 Apple Speech。
- **多語言**：支援英文、中文（簡體/繁體）、日文、韓文。Whisper 可以自動判斷語言，也可以在選單中手動指定，短句會更穩。
- **錄音狀態提示**：錄音時螢幕底部會出現小浮層，顯示即時音量。
- **對中日韓輸入法更友善**：貼上前會暫時切到 ASCII 輸入來源，避免輸入法攔截 `⌘V`。
- **只在選單列執行**：沒有 Dock 圖示，也不會跳出主視窗。
- **應用程式本體很小**：二進位約 5 MB，Whisper 模型另外存放在 Application Support 目錄。

## 系統需求

- macOS 14.0 Sonoma 或更新版本
- 建議使用 Apple Silicon Mac，Whisper 會透過 CoreML 使用 Neural Engine
- Xcode Command Line Tools

如果尚未安裝命令列工具：

```bash
xcode-select --install
```

## 從原始碼安裝

```bash
git clone https://github.com/xiangst0816/scribe.git
cd scribe
make install        # 建置並複製到 /Applications/Scribe.app
```

只想在本機建置或除錯：

```bash
make build          # 產生 ./Scribe.app
make run            # 建置並啟動
make clean          # 清除建置產物
```

## 第一次啟動

1. 開啟 `Scribe.app`。啟動後它會出現在選單列，圖示是一支筆尖。
2. 依照系統提示授予 **麥克風**、**語音辨識** 和 **輔助使用** 權限。
   - 輔助使用權限用於全域監聽 `Fn` 鍵，以及把辨識結果貼到其他 App。
3. 預設的「平衡」模型會在背景下載，大小約 210 MB。下載進度會顯示在選單列圖示上。
4. 下載完成後，選單頂端會顯示 **平衡 · 已啟用**。之後的辨識會改走本機 Whisper。

模型下載期間也可以使用 Scribe，此時會暫時使用 Apple Speech。

## 使用方式

| 操作 | 結果 |
|---|---|
| 按住 `Fn` | 開始錄音，螢幕底部顯示音量浮層。 |
| 放開 `Fn` | 結束錄音，稍等片刻後把文字貼到目前游標處。 |
| 選單列 → **語音品質** | 在快速、平衡、高品質之間切換；尚未下載的模型會依需要下載。 |
| 選單列 → **語言** | 自動辨識語言，或固定為某一種語言。 |
| 選單列 → **啟用** | 暫時開啟或關閉全域 `Fn` 監聽，不需要退出 App。 |

### 快捷鍵

目前快捷鍵固定為 **Fn**。如果想改成其他修飾鍵，可以從 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) 入手，歡迎提交 PR。

### 本機檔案

| 路徑 | 內容 |
|---|---|
| `~/Library/Application Support/Scribe/Models/<variant>/` | 已下載的 CoreML 模型 |
| `~/Library/Logs/Scribe.log` | 應用程式日誌 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults，例如語言和語音品質設定 |

## 隱私說明

- 模型下載完成後，語音辨識本身不會發起網路請求。
- 正常使用時，音訊只會在一次按鍵錄音期間暫存在記憶體中，轉寫結束後釋放。
- 需要連網的情況只有兩類：第一次選擇某個 Whisper 模型時從 Hugging Face 下載模型；以及你手動重新啟用舊的 LLM 潤飾路徑時，請求 OpenAI 相容介面。後者預設關閉，也不會出現在選單中。

## 倉庫結構

這個倉庫同時包含 macOS App 和官網，兩部分彼此獨立。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/Scribe/                ← Swift App 原始碼
├── web/                           ← Astro 官網，部署到 Cloudflare Pages
└── .github/workflows/
    └── deploy-web.yml             ← 只在 web/ 變更時觸發官網部署
```

App 和官網沒有共用建置相依。官網的開發、建置和 Cloudflare 設定請見 [web/README.md](web/README.md)。

## 應用架構

```text
Scribe.app
├── KeyMonitor          ── 透過 CGEventTap 監聽 .flagsChanged，捕捉 Fn 狀態
├── SpeechProvider      ── 辨識引擎協定，定義 start/stop/cancel 和回呼
│   ├── AppleSpeechProvider    ── 基於 SFSpeechRecognizer 的備援辨識
│   └── WhisperSpeechProvider  ── WhisperKit + AudioProcessor，本機按鍵說話辨識
├── ModelManager        ── 模型模式、下載進度、CoreML 載入和預熱
├── OverlayPanel        ── 無邊框 NSPanel，負責錄音浮層和波形動畫
├── TextInjector        ── 剪貼簿 + ⌘V 注入文字，並處理輸入法切換
└── AppDelegate         ── 選單列 UI、狀態圖示和辨識引擎選擇
```

整個應用約 1500 行 Swift。專案沒有 Xcode project，只有 [Package.swift](Package.swift) 和一個小的 [Makefile](Makefile)，用來串起 `swift build`、`.app` 打包和 ad-hoc 簽名。

## 致謝

- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)：WhisperKit，OpenAI Whisper 的 Swift + CoreML 移植版。
- [OpenAI Whisper](https://github.com/openai/whisper)：語音辨識模型。

## 授權

[MIT](LICENSE) © Scribe contributors.
