<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · [简体中文](README.zh-Hans.md) · **繁體中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

**按住 Fn，說話，放開。文字就會出現在目前游標的位置。**

一款常駐 macOS 選單列的輕量按鍵說話工具。使用系統內建的語音辨識，不需要下載模型，也不會跳出額外視窗。

[![平台: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe 是什麼

Scribe 解決的是一個很日常、也很煩人的問題：你正在寫程式、回訊息、做筆記，突然想用語音輸入一段文字，但不想切換 App、不想叫出系統聽寫，也不想等雲端轉錄。

它會待在選單列。按住 **Fn** 開始說話，放開後，辨識出的文字會自動貼到目前取得焦點的輸入位置。Safari、VS Code、Slack、備忘錄、網頁輸入框、終端機，都可以直接用。

語音辨識使用系統內建的 `SFSpeechRecognizer`。在 Apple Silicon 的 Mac 上跑 Sonoma 或更新版本時，常用語言通常在本機辨識；其他情況下，音訊可能會依 Apple 的語音辨識隱私政策送到蘋果伺服器。

## 主要特色

- **全域按鍵說話**：按住 `Fn` 錄音，放開後轉成文字並貼到游標處。
- **即時字幕浮條**：錄音時音量膠囊上方會浮出一條霧面玻璃質感的小條，顯示你目前正在說的這一句，松手前就能看到辨識結果。
- **尾端緩衝**：放開 `Fn` 後還會再錄約 500 毫秒，避免句尾說慢一點就被截掉。緩衝期間再按一次 `Fn` 就能無縫接著錄。
- **多語言**：英文、中文（簡體/繁體）、日文、韓文。可以在選單裡固定一種語言，也可以跟隨系統設定。
- **對中日韓輸入法更友善**：貼上前會暫時切到 ASCII 輸入來源，避免輸入法攔截 `⌘V`。
- **只在選單列執行**：沒有 Dock 圖示，也不會跳出主視窗。

## 系統需求

- macOS 14.0 Sonoma 或更新版本
- 系統支援的辨識語言（英文、中文、日文、韓文皆內建可用）
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

1. 開啟 `Scribe.app`。啟動後它會帶著 Scribe 圖示出現在選單列。
2. 依照系統提示授予 **麥克風**、**語音辨識** 和 **輔助使用** 權限。
   - 輔助使用權限用於全域監聽 `Fn` 鍵，以及把辨識結果貼到其他 App。
3. 沒有要下載的模型，授權完成後按 `Fn` 就能用。

## 使用方式

| 操作 | 結果 |
|---|---|
| 按住 `Fn` | 開始錄音。螢幕底部出現波形膠囊，上方浮條即時顯示你正在說的這一句。 |
| 放開 `Fn` | 約 500 毫秒尾端緩衝後結束錄音，把文字貼到目前游標處。 |
| 選單列 → **語言** | 固定為某一種辨識語言，或跟隨系統設定自動選擇。 |
| 選單列 → **啟用** | 暫時開啟或關閉全域 `Fn` 監聽，不需要退出 App。 |

### 快捷鍵

目前快捷鍵固定為 **Fn**。如果想改成其他修飾鍵，可以從 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) 入手，歡迎提交 PR。

### 本機檔案

| 路徑 | 內容 |
|---|---|
| `~/Library/Logs/Scribe.log` | 應用程式日誌 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults（已選語言） |

## 隱私說明

- 語音辨識使用 Apple 內建的 `SFSpeechRecognizer`。在 Apple Silicon 的 Mac 上跑 Sonoma 或更新版本時，四種主要語言通常在本機辨識；其他情況下，音訊可能會依 Apple 的[語音辨識隱私政策](https://www.apple.com/legal/privacy/data/zh-tw/speech-recognition/)送到蘋果伺服器。
- Scribe 本身不會發起其他對外網路請求。唯一的例外是預設關閉的 LLM 潤飾路徑，只有在你手動重新啟用後才會呼叫 OpenAI 相容介面，選單中也不會顯示。
- 音訊只會在一次按鍵錄音期間（含 500 毫秒尾端緩衝）暫存於記憶體，轉寫結束後釋放。

## 倉庫結構

這個倉庫同時包含 macOS App 和官網，兩部分彼此獨立。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/
│   ├── Scribe/                    ← ScribeCore 函式庫，所有應用程式邏輯
│   └── ScribeApp/main.swift       ← 極簡可執行入口，只跑 NSApplication
├── Tests/ScribeCoreTests/         ← XCTest 單元測試
├── web/                           ← Astro 官網，部署到 Cloudflare Pages
└── .github/workflows/
    └── deploy-web.yml             ← 只在 web/ 變更時觸發官網部署
```

App 和官網沒有共用建置相依。官網的開發、建置和 Cloudflare 設定請見 [web/README.md](web/README.md)。

## 應用架構

```text
Scribe.app
├── KeyMonitor             ── 透過 CGEventTap 監聽 .flagsChanged，捕捉 Fn 狀態
├── SpeechProvider         ── 辨識引擎協定，定義 start/stop/cancel 和 onAudioLevel/onPartialResult/onFinalResult 回呼
│   └── AppleSpeechProvider    ── 基於 SFSpeechRecognizer 的串流辨識，附帶音量計
├── OverlayPanel           ── 無邊框 NSPanel，提供波形膠囊和上方的即時字幕浮條
├── TextInjector           ── 剪貼簿 + ⌘V 注入文字，並處理輸入法切換
└── AppDelegate            ── 選單列 UI、狀態圖示和錄音生命週期
```

整個應用程式約幾百行 Swift，分成 `ScribeCore` 函式庫和一個極簡可執行入口。專案沒有 Xcode project，只有 [Package.swift](Package.swift) 和一個小的 [Makefile](Makefile)，用來串起 `swift build`、`.app` 打包和 ad-hoc 簽名。執行測試用 `swift test`。

## 致謝

- [Sparkle](https://sparkle-project.org)：自動更新框架。
- Apple [Speech](https://developer.apple.com/documentation/speech) 框架：底層辨識能力。

## 授權

[MIT](LICENSE) © Scribe contributors.
