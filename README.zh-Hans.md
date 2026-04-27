<div align="center">

<img src="web/public/icon.png" alt="Scribe" width="128" height="128" />

# Scribe

[English](README.md) · **简体中文** · [繁體中文](README.zh-Hant.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**按住 Fn，说话，松手。文字会直接出现在当前光标处。**

一款运行在 macOS 菜单栏里的本地听写工具。基于 [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift)，识别过程在你的 Mac 上完成，默认不把音频发到云端。

[![平台: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos/)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Scribe 是什么

Scribe 解决的是一个很具体的问题：你正在写代码、回消息、记笔记，突然想用语音输入一段话，但不想切应用、不想打开系统听写，也不想等云端转写。

它常驻在菜单栏。按住 **Fn** 键开始说，松开后，识别出的文字会自动粘贴到当前获得焦点的输入位置。Safari、VS Code、Slack、备忘录、网页输入框、终端，都可以直接用。

识别由编译成 CoreML 的 OpenAI Whisper 模型在本机完成。模型下载好以后，日常听写不需要联网，音频也不会离开你的电脑。

## 主要特点

- **全局按键说话**：按住 `Fn` 录音，松开后转写并粘贴到光标处。
- **本地 Whisper 识别**：提供快速、均衡、高质量三档，分别对应 `openai_whisper-base`、`openai_whisper-small_216MB`、`openai_whisper-large-v3-v20240930_626MB`。模型只需下载一次，之后离线使用。
- **可立即使用的兜底识别**：Whisper 模型下载或加载期间，会先使用 Apple Speech。
- **多语言**：支持英语、中文（简体/繁体）、日语、韩语。Whisper 可以自动判断语言，也可以在菜单里手动指定，短句更稳。
- **录音状态提示**：录音时屏幕底部会出现一个小浮层，显示实时音量。
- **对中日韩输入法更友好**：粘贴前会临时切到 ASCII 输入源，避免输入法拦截 `⌘V`。
- **只在菜单栏运行**：没有 Dock 图标，也不会弹出主窗口。
- **应用本体很小**：二进制约 5 MB，Whisper 模型单独放在 Application Support 目录里。

## 系统要求

- macOS 14.0 Sonoma 或更高版本
- 推荐 Apple Silicon Mac，Whisper 会通过 CoreML 使用 Neural Engine
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

1. 打开 `Scribe.app`。启动后它会出现在菜单栏，图标是一支笔尖。
2. 按系统提示授予 **麦克风**、**语音识别** 和 **辅助功能** 权限。
   - 辅助功能权限用于全局监听 `Fn` 键，以及把识别结果粘贴到其他应用里。
3. 默认的“均衡”模型会在后台下载，大小约 210 MB。下载进度会显示在菜单栏图标上。
4. 下载完成后，菜单顶部会显示 **均衡 · 已启用**。之后的识别会走本地 Whisper。

模型下载期间也可以使用 Scribe，这时会临时走 Apple Speech。

## 使用方式

| 操作 | 结果 |
|---|---|
| 按住 `Fn` | 开始录音，屏幕底部显示音量浮层。 |
| 松开 `Fn` | 结束录音，稍等片刻后把文字粘贴到当前光标处。 |
| 菜单栏 → **语音质量** | 在快速、均衡、高质量之间切换；未下载的模型会按需下载。 |
| 菜单栏 → **语言** | 自动识别语言，或固定为某一种语言。 |
| 菜单栏 → **启用** | 临时开启或关闭全局 `Fn` 监听，不需要退出应用。 |

### 快捷键

目前热键固定为 **Fn**。如果想改成其他修饰键，可以从 [KeyMonitor.swift](Sources/Scribe/KeyMonitor.swift) 入手，欢迎提交 PR。

### 本地文件

| 路径 | 内容 |
|---|---|
| `~/Library/Application Support/Scribe/Models/<variant>/` | 已下载的 CoreML 模型 |
| `~/Library/Logs/Scribe.log` | 应用日志 |
| `~/Library/Preferences/com.yetone.Scribe.plist` | UserDefaults，例如语言和语音质量设置 |

## 隐私说明

- 模型下载完成后，语音识别本身不会发起网络请求。
- 正常使用时，音频只会在一次按键录音期间暂存在内存中，转写结束后释放。
- 需要联网的情况只有两类：第一次选择某个 Whisper 模型时从 Hugging Face 下载模型；以及你手动重新启用旧的 LLM 润色路径时，请求 OpenAI 兼容接口。后者默认关闭，也不会出现在菜单里。

## 仓库结构

这个仓库同时包含 macOS 应用和官网，两部分相互独立。

```text
scribe/
├── Package.swift, Makefile, Info.plist, AppIcon.icns
├── Sources/Scribe/                ← Swift 应用源码
├── web/                           ← Astro 官网，部署到 Cloudflare Pages
└── .github/workflows/
    └── deploy-web.yml             ← 只在 web/ 变化时触发官网部署
```

应用和官网没有共享构建依赖。官网的开发、构建和 Cloudflare 配置见 [web/README.md](web/README.md)。

## 应用架构

```text
Scribe.app
├── KeyMonitor          ── 通过 CGEventTap 监听 .flagsChanged，捕捉 Fn 状态
├── SpeechProvider      ── 识别引擎协议，定义 start/stop/cancel 和回调
│   ├── AppleSpeechProvider    ── 基于 SFSpeechRecognizer 的兜底识别
│   └── WhisperSpeechProvider  ── WhisperKit + AudioProcessor，本地按键说话识别
├── ModelManager        ── 模型档位、下载进度、CoreML 加载和预热
├── OverlayPanel        ── 无边框 NSPanel，负责录音浮层和波形动画
├── TextInjector        ── 剪贴板 + ⌘V 注入文本，并处理输入法切换
└── AppDelegate         ── 菜单栏 UI、状态图标和识别引擎选择
```

整个应用大约 1500 行 Swift。项目没有 Xcode 工程，只有 [Package.swift](Package.swift) 和一个小的 [Makefile](Makefile)，用来串起 `swift build`、`.app` 打包和 ad-hoc 签名。

## 致谢

- [argmaxinc/argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)：WhisperKit，OpenAI Whisper 的 Swift + CoreML 移植版。
- [OpenAI Whisper](https://github.com/openai/whisper)：语音识别模型。

## 许可证

[MIT](LICENSE) © Scribe contributors.
