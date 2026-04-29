<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · **简体中文** · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**按住 Fn，说话，松手。文字会直接出现在当前光标处。**

一款常驻 macOS 菜单栏的轻量按键说话工具。基于系统自带的语音识别，不需要下载模型，也不会弹出额外窗口。可选打开本地小模型，把口水稿润色成完整句子；模型按需下载，推理始终在本机进行。

[![平台: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe 是什么

Scribe 解决的是一个很具体的问题：你正在写代码、回消息、记笔记，突然想用语音输入一段话，但不想切应用、不想打开系统听写，也不想等云端转写。

它常驻在菜单栏。按住 **Fn** 键开始说，松开后，识别出的文字会自动粘贴到当前获得焦点的输入位置。Safari、VS Code、Slack、备忘录、网页输入框、终端，都可以直接用。

语音识别由系统自带的 `SFSpeechRecognizer` 完成。在 Apple Silicon 的 Mac 上跑 Sonoma 及更新版本时，常用语言通常在本机识别；其他情况下，音频可能会按 Apple 的语音识别隐私政策走苹果服务器。

## 主要特点

- **全局按键说话**：按住 `Fn` 录音，松开后转写并粘贴到光标处。
- **实时字幕浮条**：录音时音量胶囊上方会浮出一条玻璃质感的小条，显示你当前正在说的这一句，让你松手前就能看到识别效果。
- **尾部缓冲**：松开 `Fn` 后还会再录约 500 毫秒，避免你句尾说慢一点就被截断。缓冲期间再按一次 `Fn` 可以无缝接着录。
- **多语言**：英文、中文（简体/繁体）、日文、韩文。可以在菜单里固定一种语言，也可以跟随系统设置。
- **对中日韩输入法更友好**：粘贴前会临时切到 ASCII 输入源，避免输入法拦截 `⌘V`。
- **可选本地润色**（默认关）：在「润色设置」里打开后，可以选择系统内置模型（macOS 26 + Apple Intelligence 可用区）或 Scribe 自带的 Gemma 4 E2B 本地模型（约 3.5 GB，按需下载）。两条路径都完全在本机推理，转写文本不会离开你的 Mac。
- **只在菜单栏运行**：没有 Dock 图标，也不会弹出主窗口。

## 系统要求

- macOS 14.0 Sonoma 或更高版本
- 系统支持的识别语言（英文、中文、日文、韩文都开箱可用）
- Xcode Command Line Tools

如果还没安装命令行工具：

```bash
xcode-select --install
```

## 从源码安装

```bash
git clone https://github.com/xiangst0816/scribe.git
cd scribe
make install        # 构建并复制到 /Applications/Scribe.app
```

只想本地构建或调试：

```bash
make build          # 生成 ./Scribe.app
make run            # 构建并启动
make clean          # 清理构建产物
```

## 第一次启动

1. 打开 `Scribe.app`。启动后它会带着 Scribe 图标出现在菜单栏。
2. 按系统提示授予 **麦克风**、**语音识别** 和 **辅助功能** 权限。
   - 辅助功能权限用于全局监听 `Fn` 键，以及把识别结果粘贴到其他应用里。
3. 没有需要下载的模型，授权完就可以按 `Fn` 用了。

## 使用方式

| 操作 | 结果 |
|---|---|
| 按住 `Fn` | 开始录音。屏幕底部出现波形胶囊，上方浮条会实时显示你正在说的这一句。 |
| 松开 `Fn` | 经过约 500 毫秒尾部缓冲后停止录音，把文字粘贴到当前光标处。 |
| 菜单栏 → **语言** | 固定为某一种识别语言，或跟随系统设置自动选择。 |
| 菜单栏 → **启用** | 临时开启或关闭全局 `Fn` 监听，不需要退出应用。 |

### 快捷键

目前热键固定为 **Fn**。如果想改成其他修饰键，可以从 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) 入手，欢迎提交 PR。

### 本地文件

| 路径 | 内容 |
|---|---|
| `~/Library/Logs/Scribe.log` | 应用日志 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults（已选语言、润色开关） |
| `~/Library/Application Support/Scribe/models/` | 本地润色模型（仅当你启用 Local 引擎并完成下载后才会出现） |

## 隐私说明

- 语音识别走的是 Apple 自带的 `SFSpeechRecognizer`。Apple Silicon 上 Sonoma 及更新版本，四种主语言通常在本机识别；其他情况下音频可能会按 Apple 的[语音识别隐私政策](https://www.apple.com/legal/privacy/data/zh-cn/speech-recognition/)发往苹果服务器。
- 可选的转写润色（默认关）有两条引擎路径，**推理都在本机进行**：
  - *系统内置* — 使用 macOS 自带的 Apple Intelligence 端侧模型，不需要下载，仅在 macOS 26+ 且当前地区支持时可用。
  - *Scribe 本地模型* — Gemma 4 E2B-it（约 3.5 GB）。第一次启用时从 ModelScope 或 HuggingFace 下载一次；下载 URL 和 SHA-256 校验值都写死在二进制里。下载完成后所有润色都完全离线运行。
- 润色启用后，转写文本会先经过你选择的引擎再粘贴；任何超时或错误都会立即降级到原文，不会让录音丢失。
- 音频只在一次按键录音期间（含 500 毫秒尾部缓冲）暂存在内存中，转写结束后释放。

## 仓库结构

这个仓库同时包含 macOS 应用和官网，两部分相互独立。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/
│   ├── Scribe/                    ← ScribeCore 库，所有应用逻辑
│   └── ScribeApp/main.swift       ← 极简可执行入口，只跑 NSApplication
├── Tests/ScribeCoreTests/         ← XCTest 单元测试
├── web/                           ← Astro 官网，部署到 Cloudflare Pages
└── .github/workflows/
    └── deploy-web.yml             ← 只在 web/ 变化时触发官网部署
```

应用和官网没有共享构建依赖。官网的开发、构建和 Cloudflare 配置见 [web/README.md](web/README.md)。

## 应用架构

```text
Scribe.app
├── KeyMonitor             ── 通过 CGEventTap 监听 .flagsChanged，捕捉 Fn 状态
├── AppleSpeechSession     ── 基于 SFSpeechRecognizer 的流式识别，附带音量计
├── OverlayPanel           ── 无边框 NSPanel，提供波形胶囊和上方的实时字幕浮条
├── TextInjector           ── 剪贴板 + ⌘V 注入文本，并处理输入法切换
├── Refinement/            ── 可选的转写润色（默认关）
│   ├── PolishCoordinator      ── 引擎仲裁、3 秒超时、连续失败熔断
│   ├── SystemPolishService    ── Apple Intelligence（macOS 26+，受地区限制）
│   └── LocalPolishService     ── 通过 llama.cpp 调 Gemma 4 E2B GGUF + 下载层
├── SettingsWindow         ── 润色总开关 + 系统/本地引擎二选一
└── AppDelegate            ── 菜单栏 UI、状态图标和录音生命周期
```

应用代码拆成 `ScribeCore` 库和一个极简可执行入口。项目没有 Xcode 工程，只有 [Package.swift](Package.swift) 和一个小的 [Makefile](Makefile)，用来串起 `swift build`、`.app` 打包和 ad-hoc 签名。运行测试用 `swift test`（XCTest 需要 Xcode；CI 在 `macos-15` runner 上跑）。

llama.cpp 通过 SwiftPM 的 `binaryTarget` 引入官方发布的 `xcframework`，本地构建不需要 CMake 或 Xcode。链接到 .app 后只增加约 9 MB；模型权重单独存放在 `~/Library/Application Support/Scribe/`。

## 致谢

- [Sparkle](https://sparkle-project.org)：自动更新框架。
- Apple [Speech](https://developer.apple.com/documentation/speech) 框架：底层识别能力。
- [llama.cpp](https://github.com/ggml-org/llama.cpp)：本地模型推理引擎（MIT）。
- [Gemma 4 E2B-it](https://huggingface.co/bartowski/google_gemma-4-E2B-it-GGUF)（Google，GGUF 量化由 bartowski 提供）：本地润色模型（Apache 2.0）。

## 许可证

[MIT](LICENSE) © Scribe contributors.
