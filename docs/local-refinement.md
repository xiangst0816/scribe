# Local Refinement —— 本地小模型润色（设计文档）

> 状态：草稿 / 待实现
> 范围：在 Scribe 既有的"语音 → 转写 → 粘贴"流程上增加一道**纯本地**的模型润色步骤。
> 替代关系：替换掉现有 [LLMRefiner.swift](../Sources/Scribe/LLMRefiner.swift) 的远端 OpenAI 路径（CLAUDE.md 已声明该路径默认关闭、不在菜单中展示）。新实现完全本地，**绝不联网做推理**。

---

## 1. 目标与定位

把转写出来的口水稿（含"嗯/啊"、重复、半句话、口语化结构等）通过本地模型整理成完整通顺的句子，再粘贴到目标应用。

### 1.1 这是个高级功能

- **默认关闭**，藏在 Settings 里。常规用户根本不会打开它。
- 打开它的用户接受为此承担一些代价（系统限制、首次下载、首次 warm-up 等待）。
- 关掉时整个流程不变——粘贴直接走原始转写文本。

### 1.2 两个 backend，二选一

用户**只在 Settings 里选 backend**，运行时不暴露任何模型选择 / 切换 / API key / endpoint。

| Backend | 引擎 | 模型 | 来源 | 何时可用 |
| --- | --- | --- | --- | --- |
| **System (Apple Intelligence)** | `FoundationModels` | 系统内置 ~3B on-device LLM | 操作系统 | macOS 26.0+ 且 `SystemLanguageModel.default.availability == .available`（区域、机型、Apple Intelligence 状态全部满足） |
| **Local (Scribe model)** | llama.cpp | Qwen2.5-1.5B-Instruct Q4_K_M（~0.95 GB） | 用户首次启用时下载到 `~/Library/Application Support/Scribe/models/` | 任何 Apple Silicon Mac（不限 macOS 版本、不限区域） |

### 1.3 硬性约束

- **完全本地推理**，不发任何网络请求做润色。Local backend 仅在"下载模型文件"这一次性动作时联网；推理**永远**离线。
- 用户**不选模型 / 不调采样参数 / 不写 prompt**。每个 backend 内部参数固定。
- 当前不可用 / 加载失败 / 推理失败时，**降级到原始转写文本**，绝不让用户因为开了进阶功能而丢内容。

---

## 2. 平台基线

### 2.1 系统 / 架构

| 项 | 值 |
| --- | --- |
| 最低系统 | **macOS 14**（保持当前基线）。System backend 仅在 macOS 26+ 才暴露；Local backend 在 14+ 都能用 |
| 架构 | **Apple Silicon only**。Intel Mac 上整个 Polish 模块不显示，文案：`Polish requires Apple Silicon` |

> 说明：项目此前的 [docs/local-refinement.md](../docs/local-refinement.md) 旧版假定要把基线提到 macOS 26。本文修正为**保持 macOS 14**——Local backend 的存在意义就是让不在 Apple Intelligence 可用区或老系统的用户也能用。Apple FM 仅在 `macOS 26+` 编译入口编译进来。

### 2.2 依赖

| 依赖 | 用途 | 许可 |
| --- | --- | --- |
| `Sparkle`（已有） | 自动更新 | MIT |
| `FoundationModels`（系统） | System backend，仅 macOS 26+ 链接 | 系统框架 |
| `llama.cpp` | Local backend 推理引擎 | MIT |
| Qwen2.5-1.5B-Instruct Q4_K_M GGUF | Local backend 模型权重，**运行时下载，不打包进 .app** | Apache 2.0 |

### 2.3 为什么 Local backend 选 Qwen2.5-1.5B

- **Qwen2.5-0.5B**：体积更小（~400 MB），但指令遵循质量明显跌一档，"只输出润色后文本"约束容易破功 → 否决。
- **Llama-3.2-1B / 3B**：英语优秀，中文一般。在 zh-CN / zh-TW 用户群里体验差 → 否决。
- **Gemma-2-2B / Phi-3.5-mini**：CJK 中等，没有 Qwen 系出身好。
- **MoE 类（Mixtral 等）**：激活量大，单 token 延迟超 3s 软上限 → 否决。
- **机内已有的 Chinese-Llama-2-7B / CodeLlama-7B**（开发者现机数据）：Llama-2 时代指令跟随弱；7B 在 M2 上单 token ~80–150 ms，30-token 输出贴 3s 边缘 → 否决。

### 2.4 为什么 Local 引擎选 llama.cpp，不选 MLX-Swift

MLX 体验更原生，但 Qwen2.5 的官方 GGUF 不能直接喂——要重新转 MLX 权重并量化，工作量大且量化质量需要单独验证。llama.cpp 直接吃官方 GGUF，最快可用。MLX 留作后续优化。

---

## 3. UI / 交互设计

### 3.1 Settings 面板

整个 Polish 是一个**高级开关**，里面**单选**一个 backend：

```
┌─ Polish transcript (advanced) ─────────────────────────────┐
│                                                            │
│  ☐ Enable transcript polishing                             │
│    Cleans up filler words, false starts, and disfluencies. │
│    Runs entirely on your Mac.                              │
│                                                            │
│    Engine:                                                 │
│    ◉ System on-device model (Apple Intelligence)           │
│      No download. Fastest. Recommended when available.     │
│      Status: Unavailable on this device — region not       │
│      supported  (灰色 / disabled)                          │
│                                                            │
│    ○ Scribe local model (Qwen2.5-1.5B, downloads ~1 GB)    │
│      Works on any Apple Silicon Mac.                       │
│      Status: Not downloaded         [ Download… ]          │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

行为细则：

- **主开关 `Enable transcript polishing` 关着的时候**，下面两个 radio 都不影响最终行为——粘贴永远走原文。但 radio 选择仍然被记住，下次重新开启时沿用。
- **System 选项**：仅在 macOS 26+ 编译/显示。`SystemLanguageModel.default.availability` 不是 `.available` 时灰掉，状态行写明原因（`region not supported` / `Apple Intelligence not enabled` / `model not ready`）。点击灰掉的选项不响应。
- **Local 选项**：永远可见、永远可点（Apple Silicon 前提下）。点 Download 触发 §4 流程。
- **默认选中哪个**：第一次启用时，若 System 可用则选 System，否则选 Local 并把焦点放到 Download 按钮上。

> 关键：System 灰掉时不要把它隐藏。让用户清楚"这台机器/这个系统下，Apple 那条路不通，所以你只能/我们已经默认走 Local"。隐藏会让用户误以为 Scribe 根本没这个能力。

### 3.2 第一次启用 Local 的流程

用户在主开关已勾上、选了 Local radio、点 Download 之后：

1. **确认对话框**——告知模型大小（~1 GB）、来源（当前镜像 URL）、磁盘占用位置（`~/Library/Application Support/Scribe/models/`）、是否继续。  
   这一步**不能省**：Scribe 既有的隐私文案是"不下载任何模型"，引入下载是产品形态变化，必须用户显式同意。
2. 同意 → 进入 §4 下载状态机，进度条常驻 Settings + 状态栏小角标。
3. 完成 + 校验通过 → warm-up 一次推理。warm-up 通过 → 状态变 Ready，主开关生效。
4. 任何环节失败 → 主开关回到 off（**或保持 on 但 backend 不可用，看具体场景**，见 §4.4），Settings 显示具体失败原因 + Retry。

### 3.3 状态栏菜单 `Polish: <state>`

主菜单（状态栏点开）增加一行 **Polish: \<state\>**：

| state | 含义 | 点击行为 |
| --- | --- | --- |
| Off | 主开关未启用 | 跳到 Settings |
| Ready (System) | 走 Apple FM | 跳到 Settings 可关闭 |
| Ready (Local) | 走 Qwen2.5。**显式带 "Local" 字样**，让用户随时清楚当前是哪条路径 | 跳到 Settings |
| Downloading… 42% | 下载中 | 跳到 Settings 进度面板 |
| Download failed | 下载失败 | Retry |
| Verifying… | SHA-256 校验中 | （不响应） |
| Unavailable — Reload | warm-up 或加载失败 | Retry |
| Skipped last (timeout) | 单次推理超时已降级到原文 | 查看日志 / Retry |

### 3.4 失败的统一原则

不论走哪条 backend，最终都"降级到原始转写文本"。Local 多一层"模型文件层面的失败"（下载、校验、加载），都吸收到 `PolishCoordinator` 内部，对外仍然只表现为 "polish 出错 → 用原文"。

| 阶段 | 失败方式 | 行为 |
| --- | --- | --- |
| 启用 System | warm-up 失败（机型不支持、Apple Intelligence 关闭、语言资源未就绪） | radio 显示具体原因；主开关已开则用户被引导切到 Local；不影响转写主流程 |
| 启用 Local | 下载/校验/加载失败 | 见 §4 失败矩阵；主开关回 off，状态栏显示失败原因 |
| 推理时（任一 backend） | 单次推理超时（3 s 软上限） | 当次降级到原始转写文本，状态栏 Skipped 标记，连续 3 次失败自动关闭 polish 并通知用户 |
| 推理时（任一 backend） | 推理输出为空 / 明显乱码 / 长度爆炸（>2× 原文） | 当次降级到原始转写文本 |

---

## 4. 模型下载与文件管理（Local backend 专属）

### 4.1 存储位置

```
~/Library/Application Support/Scribe/
  └── models/
      ├── qwen2.5-1.5b-instruct-q4_k_m.gguf            (~950 MB，最终文件)
      ├── qwen2.5-1.5b-instruct-q4_k_m.gguf.partial    (下载中临时文件)
      └── qwen2.5-1.5b-instruct-q4_k_m.partial.meta    ({ url, expected_size, expected_sha256, started_at, completed_bytes })
```

**为什么不是 `~/Library/Caches/`**：Caches 可被系统在低磁盘条件下清空；用户明确同意下载的资源不该被悄悄删除。

**为什么不打包进 .app**：

- 当前 release zip ~10 MB，加上 1 GB 模型会让 Sparkle delta 升级失效（每次小升级都重传 1 GB）。
- 大多数用户走 System backend 或干脆不开 polish，不需要这个文件。
- "高级功能 → 用户主动下载"是合理的产品路径。

### 4.2 下载源 & 镜像策略

按用户区域优先排列，**自动 fallback**：

| 优先级 | 镜像 | 何时使用 |
| --- | --- | --- |
| 1 | **ModelScope**（`modelscope.cn/...`） | `selectedLocaleCode` 是 `zh-CN` 或 `zh-TW`，或用户在 Settings 显式选 |
| 2 | **HuggingFace**（`huggingface.co/...`） | 默认（非中文区域） |
| 3 | **HF mirror**（`hf-mirror.com/...`） | 1/2 都失败时的兜底 |

**期望的 SHA-256 写死在二进制里**——无论从哪个镜像下，hash 必须匹配同一个 `expected_hash`。镜像污染、CDN 劫持都会被这层挡掉。

Settings 提供 **Mirror** 下拉（Auto / ModelScope / HuggingFace / HF Mirror），默认 Auto。

### 4.3 下载状态机

```
NotDownloaded
    │  (用户在确认对话框点 Continue)
    ▼
Downloading(bytesReceived, total)
    │
    ├── 网络完成 ──▶ Verifying
    │                  │
    │                  ├── hash 匹配 ──▶ Verified ──▶ Ready
    │                  └── hash 不匹配 ──▶ 删除文件 ──▶ DownloadFailed(.integrity)
    │
    ├── 网络中断 ──▶ DownloadFailed(.network)（保留 .partial）
    │       │
    │       └── 下次启动 / Retry：HTTP Range 续传
    │
    ├── 磁盘满 ──▶ DownloadFailed(.diskFull)（保留 .partial）
    ├── 用户取消 ──▶ NotDownloaded（删除 .partial）
    └── 镜像 4xx/5xx ──▶ 切下一个镜像 ──▶ Downloading
```

### 4.4 失败矩阵（必须在实现前覆盖）

| 失败场景 | 触发条件 | 处理 |
| --- | --- | --- |
| **DNS 解析失败** | 镜像域名不通 | 切下一个镜像；全部不通 → `DownloadFailed(.unreachable)`，提示用户检查网络 |
| **TCP 超时** | 30 s 内无任何字节流入 | 同上 |
| **HTTP 403 / 404** | 镜像挂了 / URL 变了 | 切下一个镜像 |
| **HTTP 5xx** | 镜像故障 | 指数退避 3 次（1 s / 4 s / 16 s）后切镜像 |
| **连接断流（GFW / NAT）** | 中途连接被 RST | HTTP Range 续传；连续 3 次断在同一字节附近 → 切镜像 |
| **限速 / 极慢** | <50 KB/s 持续 60 s | 弹提示让用户决定继续 / 取消，**不擅自终止**（国内非校园网正常下行就慢） |
| **磁盘满** | `write()` 返回 ENOSPC | 暂停，弹"释放磁盘空间后 Retry"对话框，**保留 `.partial`** |
| **进程被杀** | 用户 force quit / 系统重启 | 启动时若检测到 `.partial.meta` 且时间戳 < 7 天，恢复 `Downloading` 状态待 Retry；超时则清空重下 |
| **Hash 不匹配** | 下载完整但 SHA-256 不对 | **不重试，不修复**——直接删完整 + `.partial`，进入 `DownloadFailed(.integrity)`。这种情况要么镜像被污染要么文件版本变了，自动重试无意义 |
| **加载失败** | `llama_load_model_from_file()` 返回错 | `LoadFailed(.corrupt)`，弹"模型文件损坏，删除并重新下载？"对话框 |
| **文件被外部删除** | 用户 / 清理工具误删 | 启动时探测；状态回到 `NotDownloaded`，等用户重新启用 |
| **下载途中 app 被关闭** | — | URLSession 持久化 resume data；下次启动检测到 `.partial.meta` 即恢复 |

### 4.5 续传细节

- 用 HTTP `Range: bytes=N-` 头。下载到 `<filename>.partial`，完成时**原子 `rename()`** 为最终名，再做校验。
- `.partial.meta` 必须配套：`{ url, expected_size, expected_sha256, started_at, completed_bytes }`。续传前比较 `expected_sha256` / `expected_size` 跟当前期望值；不一致就清空重下（说明用户升级了 app，目标模型版本变了）。
- **不引入第三方下载库**（aria2 / curl-multi）。`URLSession` + `URLSessionDownloadTask` 的 resume data 支持，足够。

### 4.6 校验

```swift
// 完成后
let actual = sha256(fileURL)
guard actual == expectedHash else {
    try? FileManager.default.removeItem(at: fileURL)
    throw .integrity
}
```

校验不是 best-effort——hash 对不上就当作没下载，绝不放行。

---

## 5. Prompt 设计

**两个 backend 共用同一份 system prompt 和 language_hint 映射**——输出语义一致是产品上的必要性（用户在 Settings 切换 backend 时不应感觉到行为差异）。

### 5.1 设计决策

- **Prompt 用英文**——支持的转写语言会越来越多（zh-CN / zh-TW / en-US / ja-JP / ko-KR），按语言切 prompt 维护成本太高。统一英文 prompt + 一个语言提示变量。
- **System prompt 是固定字符串**，不暴露给用户编辑。
- 通过模板变量 `{{language_hint}}` 注入用户当前选择的转写语言；模型据此决定输出语言。

### 5.2 语言提示映射

依据 `selectedLocaleCode`（[AppDelegate.swift](../Sources/Scribe/AppDelegate.swift) 已有）：

| selectedLocaleCode | language_hint 注入值 |
| --- | --- |
| `""`（System Default / Auto） | `auto` |
| `en-US` | `English` |
| `zh-CN` | `Simplified Chinese` |
| `zh-TW` | `Traditional Chinese` |
| `ja-JP` | `Japanese` |
| `ko-KR` | `Korean` |

`auto` 时让模型按输入语言保持一致输出。

### 5.3 System prompt 草案

```
You are a transcript polisher. The user dictated speech; an automatic
speech recognizer produced the raw text below. Raw transcripts often
contain filler words, false starts, repetitions, run-on sentences, and
informal disfluencies typical of spoken language.

Your job:
- Rewrite the raw text into clean, complete, well-formed sentences.
- Preserve the speaker's original meaning, intent, terminology, and tone.
- Keep proper nouns, code identifiers, numbers, and quoted strings exactly as written.
- Do not add information that was not said.
- Do not editorialize, summarize, or shorten beyond removing disfluencies.
- Do not translate.

Output language rules:
- The user's selected dictation language is: {{language_hint}}
- If {{language_hint}} is "auto", detect the language of the raw text and
  output in that same language.
- Otherwise, output in {{language_hint}}, regardless of any stray words
  in other languages in the raw text.

Output ONLY the polished text. No preface, no quotes, no commentary,
no markdown.
```

### 5.4 各 backend 的差异

| 项 | System (Apple FM) | Local (Qwen2.5) |
| --- | --- | --- |
| 模板载体 | `LanguageModelSession(instructions: String?)` | llama.cpp + Qwen ChatML |
| Sampling | `temperature: 0.25, maximumResponseTokens: 1024` | `temperature: 0.25, top_p: 0.9, max_tokens: 256, repeat_penalty: 1.1` |
| 长度上限 | `min(input_tokens * 2, 1024)` | `min(input_tokens * 2, 256)`（小模型生成越长越容易跑题） |

**Qwen ChatML 模板**（写代码时按 SDK 校准）：

```
<|im_start|>system
{{system_prompt}}<|im_end|>
<|im_start|>user
{{raw_transcript}}<|im_end|>
<|im_start|>assistant
```

stop tokens: `<|im_end|>`、`<|im_start|>`、EOS。

---

## 6. 架构与代码改动

### 6.1 文件改动

```
Sources/Scribe/
├── LLMRefiner.swift                   # 删除（远端 OpenAI 路径整体下线）
├── Refinement/
│   ├── PolishService.swift            # 协议
│   ├── PolishCoordinator.swift        # 仲裁 System vs Local + 超时 / 降级 / 熔断
│   ├── PolishPrompt.swift             # system prompt + language_hint 映射（共用）
│   ├── PolishState.swift              # enum: off / ready(backend) / downloading(progress) / verifying / failed(reason) / degraded
│   ├── SystemPolishService.swift      # 仅 macOS 26+，FoundationModels 包装
│   └── LocalPolishService.swift       # llama.cpp 包装
├── Refinement/Download/
│   ├── ModelDownloader.swift          # URLSession + Range + resume
│   ├── ModelMirror.swift              # 镜像列表 + 选择策略
│   ├── ModelIntegrity.swift           # SHA-256
│   └── ModelLocation.swift            # 路径解析、原子 rename、清理 .partial
├── AppDelegate.swift                  # 加 "Polish: <state>" 菜单项
└── SettingsWindow.swift               # 见 §3.1
```

### 6.2 仲裁接口

```swift
protocol PolishService {
    var availability: PolishAvailability { get }
    func warmUp() async throws
    func polish(_ raw: String, languageHint: String) async throws -> String
}

enum PolishBackend { case system, local }

@MainActor
final class PolishCoordinator {
    private let system: PolishService?      // nil on macOS < 26
    private let local: PolishService        // 始终存在；availability 反映文件状态

    var selectedBackend: PolishBackend      // 用户在 Settings 选的；持久化
    var isEnabled: Bool                     // 主开关；持久化

    func active() -> PolishService? {
        guard isEnabled else { return nil }
        switch selectedBackend {
        case .system: return system?.availability == .ready ? system : nil
        case .local:  return local.availability == .ready ? local : nil
        }
    }

    func maybePolish(_ raw: String, locale: Locale) async -> String {
        guard let svc = active() else { return raw }
        do {
            return try await withTimeout(seconds: 3) {
                try await svc.polish(raw, languageHint: PolishPrompt.hint(locale))
            }
        } catch {
            recordFailure()       // 连续 3 次自动 disable 主开关并通知用户
            return raw
        }
    }
}
```

仲裁逻辑显式地由 `selectedBackend` 决定——**不在运行时自动从 Local 切回 System** 或反之。这样用户预期是稳定的：他选了哪个就用哪个，"另一个"只在 Settings 里展示状态。

### 6.3 调用点

转写完成后插入：

```
final transcript
   ↓
PolishCoordinator.maybePolish(text, locale)
   ↓ (success → 用润色文本；任何失败 → 用原文)
TextInjector.inject(text)
```

参考 [AppDelegate.swift:145-154](../Sources/Scribe/AppDelegate.swift) 的 `deliverFinal(_:)`。

### 6.4 持久化键

```
"polish.enabled"           Bool     默认 false
"polish.backend"           String   "system" / "local"，默认按首次启用时可用性
"polish.local.mirror"      String   "auto" / "modelscope" / "huggingface" / "hfmirror"，默认 "auto"
```

旧的 `llmEnabled` / `llmAPIBaseURL` / `llmAPIKey` / `llmModel` 一并清理（启动时检测到就 `removeObject(forKey:)`）。

---

## 7. 隐私与文档同步

启用 Local backend 会触发**一次性**的网络请求（从镜像下载模型），这是 Scribe 当前隐私文案的一个新增项。需要同步更新：

1. **五份 README** "Privacy" 章节加一段：
   > Scribe optionally polishes transcripts with an on-device language model. There are two engines, both fully local at inference time:
   > - **System** (Apple Intelligence) — uses macOS's built-in language model. No download. Available on macOS 26+ in Apple Intelligence regions.
   > - **Scribe local model** — downloads Qwen2.5-1.5B (~1 GB) once from HuggingFace or ModelScope to `~/Library/Application Support/Scribe/`. After download, all polishing runs entirely locally. Both the download URL and SHA-256 are baked into the binary; no other network traffic is involved.
2. **CLAUDE.md** 架构章节：补 `Refinement/` 目录 + 双 backend 仲裁 + 下载子模块。
3. **`Scribe.entitlements`**：当前无 outgoing network。引入 Local backend 后**仅在用户主动启用时**需要网络出站。如果将来开启 sandboxing，须加 `com.apple.security.network.client`。
4. **Acknowledgements**（README + 应用菜单）：补 llama.cpp（MIT）和 Qwen2.5-1.5B-Instruct（Apache 2.0）的归属与许可。

---

## 8. 风险与待确认

1. **Foundation Models 实际 API 名称已校准**：经 SDK 实测 `SystemLanguageModel.default.availability` / `LanguageModelSession(instructions:)` / `session.respond(to:options:)` 都可用。但开发者机当前 `availability == .unavailable(.deviceNotEligible)`，无法在本机端到端验证 System backend——需要切区域或换机验证。
2. **llama.cpp 在 SwiftPM + macOS 14 上的可建性**：官方 `llama.swiftpm` 是否能直接 `swift build`，需实测。若不行就 vendored 静态库 + 手写 C-bridging。
3. **首次下载体验**：1 GB 在国内非校园网平均 ~5 分钟。决定下载窗口是常驻 Settings 进度条 + 状态栏小角标，还是浮窗——倾向前者。
4. **Sparkle delta 升级**：模型不打包进 .app，所以 Sparkle 升级不会触发模型重下；但模型升级（Qwen2.5 → Qwen3）需要单独的版本号字段（写在 `.partial.meta` 同级的 `model.version` 里），由 app 启动时比对决定要不要重下。
5. **Qwen 输出污染**：小模型偶发输出 "Sure, here's the polished text:" 之类前言。处理顺序：先用 prompt 堵住（已在 §5.3 中"Output ONLY the polished text"），实测仍有则做轻量 strip——**只剥常见模式**，绝不要正则把真内容也吃掉。
6. **熔断恢复策略**：连续 3 次失败自动关掉主开关之后，下次 app 启动是否重新尝试？倾向**重新尝试**——避免一次抖动让用户永久失去功能。
7. **生命周期**：用户切了 macOS 区域、System backend 突然变可用时，Local 已下载的模型怎么办？倾向**保留**——尊重用户已下载的事实，仅在 Settings 给出 "System engine is now available — switch and (optionally) remove local model?" 提示。
8. **网络出站权限**：当前 .app 未沙盒化所以可直接联网。一旦未来要走 Mac App Store 或开沙盒，要单独梳理 entitlements 和审核流程（App Store 对"首次下载大模型"的审核态度需先调研）。

---

## 9. 实现顺序

1. **协议骨架**：建 `Sources/Scribe/Refinement/`，写 `PolishService` 协议、`PolishCoordinator`（含 3 s 超时、连续失败熔断），先用 stub `PolishService` 跑通 `swift test` 端到端"transcript → polish → paste"链路。
2. **System backend**：写 `SystemPolishService`，在 macOS 26+ 编译入口下接 `LanguageModelSession`。在能验证的设备上跑通一次端到端 polish。
3. **下载层**：实现 `ModelDownloader` + `ModelIntegrity` + `ModelLocation`，覆盖 §4.3 状态机和 §4.4 失败矩阵中**网络 / 续传 / 磁盘满 / hash 校验**四类（其余可后续补）。先用一个小测试文件（~10 MB）跑通，再换真模型。
4. **Local backend**：SwiftPM 引入 llama.cpp，写 `LocalPolishService` 直接读固定路径下的 GGUF（先**手动 cp** 模型文件，跳过下载）。`swift test` 跑通一次 polish。
5. **拼装**：让 `LocalPolishService` 通过 §3 描述的下载流程拿模型；warm-up 接通；连续 3 次推理失败的熔断生效。
6. **Settings 双 radio + 主开关 UI** + 状态栏 `Polish: <state>` 菜单项 + 镜像下拉。
7. **删除旧路径**：移除 [LLMRefiner.swift](../Sources/Scribe/LLMRefiner.swift) 和 Settings 里残存的远端 LLM UI；启动时清旧 UserDefaults 键。
8. **文档同步**：五份 README 和 CLAUDE.md（参考 CLAUDE.md 的 pre-push checklist）；Acknowledgements 加 llama.cpp + Qwen2.5。

---

## 10. 不在范围内（避免设计扩散）

- 多模型选择 UI：永远只 Qwen2.5-1.5B-Instruct Q4_K_M 一个 SKU。
- 自定义 prompt：不暴露给用户改。
- Streaming 输出：润色是一次性的，不需要流式。
- 分布式下载 / P2P：1 GB 单连接续传足矣。
- Intel Mac 的 polish 支持。
- 同时跑 System 和 Local 做对比的"AB 测试"模式：违反"用户不选模型"原则。
- 任何远端 API 路径（OpenAI 兼容或其他）：硬性约束 §1.3，绝不联网做推理。
