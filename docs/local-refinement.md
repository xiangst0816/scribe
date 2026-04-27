# Local Refinement —— 本地小模型润色（设计文档）

> 状态：草稿 / 待实现
> 范围：在 Scribe 既有的"语音 → 转写 → 粘贴"流程上增加一道本地模型润色步骤。
> 替代关系：替换掉现有 `LLMRefiner.swift` 的远端 OpenAI 路径（CLAUDE.md 已声明该路径默认关闭、不在菜单中展示）。新实现完全本地、零下载。

---

## 1. 目标

把转写出来的口水稿（含 "嗯/啊"、重复、半句话、口语化结构等）通过 Apple Foundation Models 整理成完整通顺的句子，再粘贴到目标应用。

硬性约束：

- 默认关闭，作为 Settings 中的进阶开关。
- 用户**不选模型**，由 Scribe 决定。
- 完全本地推理，不发任何网络请求做润色。
- 当前不可用 / 加载失败 / 推理失败时，**降级到原始转写文本**，绝不让用户因为开了进阶功能而丢内容。
- **不做用户机型/系统的兼容兜底**——直接把最低系统拉到 macOS 26，老系统看到开关时给清晰提示让用户升级。

---

## 2. 平台基线

| 项 | 值 |
| --- | --- |
| 最低系统 | **macOS 26.0 (Tahoe)** |
| 架构 | Apple Silicon |
| 推理引擎 | Apple `FoundationModels` 框架（系统内置） |
| 模型 | 系统自带 ~3B 参数 on-device LLM，2-bit QAT |
| 模型管理 | 无——操作系统全权负责，Scribe 不缓存、不下载、不升级 |

需要修改的项目级配置：

- [Package.swift](Package.swift) `platforms: [.macOS(.v14)]` → `[.macOS(.v26)]`
- [Info.plist](Info.plist) `LSMinimumSystemVersion` 同步 26.0
- 五份 README 在"系统要求"章节同步更新
- Sparkle appcast 的 `sparkle:minimumSystemVersion` 同步

---

## 3. UI / 交互设计

### 3.1 Settings 开关

只有一个开关，无任何下拉/输入：

```
☐ Polish transcript with on-device model
   Cleans up filler words, false starts, and disfluencies.
   Runs entirely on your Mac. Nothing is sent to the network.
   Status: <动态文案，见 3.3>
```

第一次勾选时：

1. 调用 `LanguageModelSession` 做一次 warm-up（构造 session + 一次空跑）。
2. Warm-up 成功 → 开关定为 ✓，开始生效。Warm-up 通常 < 1 秒。
3. Warm-up 失败 → 开关回退到关，状态文案显示原因 + "Retry" 按钮。

注意：因为模型是系统内置的，正常情况下 warm-up 几乎不会失败。失败一般意味着系统层 Apple Intelligence 被禁用、机型不支持、或语言资源未就绪。

### 3.2 状态栏（菜单栏）指示

主菜单（Scribe 状态栏图标点开后）增加一项 **"Polish: <state>"**：

| state | 含义 | 菜单项行为 |
| --- | --- | --- |
| Off | 用户未启用 | 显示 "Polish: Off"（灰），点击跳到 Settings |
| Ready | 已启用、就绪 | "Polish: Ready"，点击可关闭 |
| Failed | warm-up 出错 | "Polish: Unavailable — Reload"，点击重试 |
| Degraded | 最近一次推理失败/超时已降级到原文 | "Polish: Skipped last (timeout)"，点击查看日志或重试 |

转写过程中如果触发了润色但还没返回，overlay/transcript pill 应保留一个轻量 "polishing…" 状态，避免用户以为粘贴卡住了。

### 3.3 失败处理（核心原则：永远有原文兜底）

| 阶段 | 失败方式 | 行为 |
| --- | --- | --- |
| 启用时 | warm-up 失败（机型不支持、Apple Intelligence 关闭、语言资源未就绪） | 开关回退到关，状态栏显示 Failed，**不影响转写主流程** |
| 推理时 | 单次推理超时（建议 3s 软上限） | 当次降级到原始转写文本，状态栏 Degraded 标记，连续 3 次失败后自动关闭润色并提示用户 |
| 推理时 | 推理输出为空 / 明显乱码 / 长度爆炸（>2× 原文） | 当次降级到原始转写文本 |

### 3.4 系统不支持时（macOS 26 以下，理论上不会出现，因为有最低系统门槛）

最低系统门槛已经过滤掉了 macOS 25 及更早。如果用户用 Sparkle 之类绕过最低系统强行运行，开关在 Settings 里直接置灰并写一行说明：`Requires macOS 26 (Tahoe) or later.` 不做更复杂的降级。

---

## 4. Prompt 设计

### 4.1 设计决策

- **Prompt 用英文**——支持的转写语言会越来越多（zh-CN / zh-TW / en-US / ja-JP / ko-KR），按语言切 prompt 维护成本太高。统一英文 prompt + 一个语言提示变量。
- **System prompt 是固定字符串**，不暴露给用户编辑。
- 通过模板变量 `{{language_hint}}` 注入用户当前选择的转写语言；模型据此决定输出语言。

### 4.2 语言提示映射

依据 `selectedLocaleCode`（[AppDelegate.swift](Sources/Scribe/AppDelegate.swift) 已有）：

| selectedLocaleCode | language_hint 注入值 |
| --- | --- |
| `""` (System Default / Auto) | `auto` |
| `en-US` | `English` |
| `zh-CN` | `Simplified Chinese` |
| `zh-TW` | `Traditional Chinese` |
| `ja-JP` | `Japanese` |
| `ko-KR` | `Korean` |

`auto` 时让模型按输入语言保持一致输出。

### 4.3 System prompt 草案

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

**采样参数**：温度 0.2–0.3，避免改写发散。

**长度控制**：使用 Foundation Models 的 generation options 把最大输出 token 限制为 `max(64, min(input_tokens * 2, 1024))`，防止失控。

---

## 5. 架构与代码改动

### 5.1 文件改动

```
Sources/Scribe/
├── LLMRefiner.swift                  # 删除（远端 OpenAI 路径整体下线）
├── Refinement/                       # 新目录
│   ├── PolishService.swift           # FoundationModels 封装
│   ├── PolishCoordinator.swift       # 调度 + 超时 + 降级 + 熔断
│   ├── PolishState.swift             # enum: off / ready / failed / degraded
│   └── PolishPrompt.swift            # system prompt + language_hint 映射
├── AppDelegate.swift                 # 加 "Polish: <state>" 菜单项
└── SettingsWindow.swift              # 替换原 LLM 设置 UI 为单开关
```

### 5.2 核心调用

参考实现（具体 API 名称在写代码时按 SDK 校准）：

```swift
import FoundationModels

@MainActor
final class PolishService {
    private var session: LanguageModelSession?

    func warmUp(languageHint: String) async throws {
        session = LanguageModelSession(
            instructions: PolishPrompt.system(languageHint: languageHint)
        )
        _ = try await session?.respond(to: "")  // 触发实际加载
    }

    func polish(_ raw: String) async throws -> String {
        guard let session else { throw PolishError.notReady }
        let response = try await session.respond(
            to: raw,
            options: .init(temperature: 0.25, maximumResponseTokens: 1024)
        )
        return response.content
    }
}
```

### 5.3 调用点

转写完成（[AppleSpeechSession.swift](Sources/Scribe/AppleSpeechSession.swift) 把 final transcript 交给 [TextInjector.swift](Sources/Scribe/TextInjector.swift)）后插入：

```
final transcript
   ↓
PolishCoordinator.maybePolish(text, locale)
   ↓ (success → 用润色文本；任何失败 → 用原文)
TextInjector.paste(text)
```

`maybePolish` 内部：

- 如果开关关 / state ≠ ready → 直接返回原文（同步、零延迟）。
- 否则带 3 秒软超时调 `PolishService.polish`。
- 任何 throw / 超时 / 输出异常都 fallback 到原文，并把失败计数 +1，连续 3 次自动 disable + 通知用户。

### 5.4 持久化键

新增一个 `UserDefaults` key：

```
"polish.enabled"   Bool   默认 false
```

旧的 `llmEnabled` / `llmAPIBaseURL` / `llmAPIKey` / `llmModel` 一并清理（启动时检测到就 remove）。

---

## 6. 风险与待确认

1. **Foundation Models 实际 API 名称**：写代码时按当时 SDK 校准；本文档示例代码不作准。
2. **首次 warm-up 时长**：实测后再决定要不要给一个进度态。
3. **菜单栏视觉**：`Polish: <state>` 是直接放主菜单第一/二项，还是塞进现有的某个子菜单？倾向放主菜单，便于快速看到状态。
4. **熔断恢复策略**：自动 disable 之后是不再尝试，还是下次 app 启动重试？倾向后者。
5. **最低系统门槛跳跃影响**：从 macOS 14 直接跳到 26 是个相当激进的提升。需要在 release notes 和 README 里明确写出来；老系统用户走 Sparkle 升级时会因为 `minimumSystemVersion` 被拦下，不会破坏现有安装。

---

## 7. 实现顺序

1. 把 [Package.swift](Package.swift)、[Info.plist](Info.plist)、Sparkle appcast 的最低系统提到 macOS 26.0。
2. 删除 [LLMRefiner.swift](Sources/Scribe/LLMRefiner.swift) 和 Settings 里现存的远端 LLM UI。
3. 新建 `Sources/Scribe/Refinement/` 四个文件，跑通 warm-up + 单次 polish 调用。
4. `PolishCoordinator` + 3s 超时 + 降级 + 熔断。
5. Settings 单开关 UI（带状态文案）。
6. 状态栏菜单项。
7. 五份 README 同步更新（系统要求、功能说明、隐私章节；参见 CLAUDE.md 的 pre-push checklist）。
