# Scribe 可挖掘的 Apple 系统 AI 能力（探索文档）

> 状态：探索 / 未排期
> 范围：Scribe 升级到 macOS 26 后的 AI 化方向，列出系统内置可用的能力 + 落地到 Scribe 的具体玩法。
> 与当前 PR 无关，只作为后续 roadmap 参考。

## 前提

- 最低系统：macOS 26.0 (Tahoe)
- 架构：Apple Silicon
- 原则：**全 Apple 栈**，不引入第三方模型/运行时；每一项都做成 Settings 里的独立进阶开关，按需启用。

---

## 一档：高价值，应优先纳入 roadmap

### 1. Foundation Models framework

系统内置 ~3B on-device LLM。本次 PR 会用它做"润色"，但同一个 framework 还能解锁很多挡位。

**可以做的事**

- **语气挡（多档输出）**：同一份转写一秒切多档——`Casual` / `Professional` / `Email` / `Slack` / `Code Comment` / `Commit Message`。修饰键 + 录音热键即可切换，不进菜单。
- **结构化抽取**：用 Foundation Models 的 `@Generable` + guided generation，让模型直接吐 Swift 结构体（不用解析自由文本）。
  - 口述 TODO → `[Task]` 直接写进 Reminders
  - 口述会议笔记 → `{summary, decisions, actionItems}` JSON
  - 口述代码片段 → 自动加 `\`\`\`` 围栏 + 语言标记
- **会话式追问**：常驻一个 `LanguageModelSession`。粘贴后按额外修饰键再说一句"再短一点 / 翻成英文 / 加点 emoji"，原样应用到刚粘出去的文本（用 `NSAccessibility` 替换选区）。
- **TL;DR 挡**：长口述结束后给一句话摘要，配合 Notes / Email 场景。

### 2. Translation framework（macOS 14+）

苹果原生本地翻译，离线、独立模型，质量比通用 LLM 翻译稳。首次用某语言对会按需拉语言包，全程系统管理。

**可以做的事**

- **翻译挡**：和润色挡正交、可叠加。中文口述 → 英文粘贴；英文口述 → 日文粘贴。
- 比让 Foundation Models "顺便翻译"更快更准——专用模型在标准翻译任务上一般优于通用 LLM。

### 3. `SFSpeechLanguageModel` —— 自定义语言模型偏置

Scribe 现在的 `SFSpeechRecognizer` 完全没用到这层，**这是零成本的识别准确率提升**。

**可以做的事**

- **领域词表**：用户在 Settings 里维护一份"个人词表"（人名、项目名、库名、自创术语），转写前作为偏置喂给识别器。`Yetone`、`SwiftUI`、`Cloudflare`、`Hsiang` 这种长期被识别错的词立刻不再错。
- **`contextualStrings` 上下文偏置**：检测前台 app 类型动态切偏置——
  - Xcode → 注入 Swift / Objective-C 关键字 + 当前 workspace 的符号
  - Mail → 注入最近通讯录联系人
  - Terminal → 注入常用命令名
- 无需训练、无需任何模型管理，纯文本数组。

### 4. Natural Language framework（一直就有）

轻量、零延迟、纯函数。当前 Scribe 完全没用，几个地方可以立刻用上：

**可以做的事**

- **`NLLanguageRecognizer`**：Auto 挡的"输出语言跟随输入"用它做硬规则——比让 Foundation Models 推断语言更便宜、更稳、零延迟。
- **`NLTokenizer`（句子粒度）**：把超长口述分句后再分批送进 Foundation Models，避免单次 prompt 过长拖慢 TTFT。
- **`NLTagger` (NER)**：识别口述中的人名 / 地名 / 组织 / 日期，overlay 上做轻量高亮，让用户瞄一眼就能确认是否听对了。

---

## 二档：方向清晰，值得规划

### 5. Writing Tools 系统集成（Apple Intelligence）

任何 NSTextView 在 macOS 上都自带 Writing Tools 菜单（Proofread / Rewrite / Friendly / Professional / Concise / Summarize / Key Points / List / Table）。

**可以做的事**

- 粘贴完成后**自动 select 刚插入的文本**，让用户右键就能调系统级 Writing Tools。等于把苹果产品级能力当后端用，零代码。
- 进阶：在 Scribe 内部直接以编程方式调用 Writing Tools API 加工，相当于多一档"系统改写"。

### 6. App Intents

把 Scribe 的能力暴露为 Intent，Siri / Spotlight / Shortcuts 自动化都能调用。

**可以做的事**

- `DictateAndPaste`、`DictateAsEmail`、`DictateInLanguage(target: Locale)`、`DictateAndExtractTodos` 等 Intent。
- Shortcuts 串联："按住录音键 → Scribe 转写 → 自动翻译成英文 → 追加到 Notes 笔记"。
- macOS 26 的 Action Button / 焦点动作可以触发 Intent。

### 7. AVSpeechSynthesizer（TTS）

苹果 Personal Voice / Siri Voice 之后，TTS 质量已经可用。

**可以做的事**

- **回读校对**：粘贴前用 TTS 读一遍润色后的文本，长口述场景下用耳朵确认更轻松。
- **盲打反馈**：识别低置信度 token 时给一个轻量音效或语音提示。
- 完全可选，做成 Settings 里的"Speak before paste"。

### 8. Sound Analysis (`SoundAnalysis`)

系统自带的音频分类器，能区分人声、键盘、风扇、音乐、咳嗽等。

**可以做的事**

- **环境提示**：检测到键盘 / 风扇 / 音乐过响时状态栏给警告"Recording in noisy environment"。
- **智能 silence detection**：替代固定时长的 silence timeout，用"是否还在说话"的判断更智能地决定何时收尾——口述节奏不同的人体验差距很大。

---

## 三档：探索向，知道有就行

### 9. Vision / VisionKit Live Text + Visual Intelligence (macOS 26)

**可以做的事**：当前前台窗口截图 → OCR → 喂进 Foundation Models 当 context。例如在邮件预览界面口述回复时，Scribe 知道你在回哪封邮件。价值高但隐私和复杂度也高，得专门设计开关和提示。

### 10. Core ML / Create ML

短期不必。除非自训特定模型（如"是否口语化"分类器），上面的 framework 已经覆盖 95% 场景。

### 11. MLX / MLX-Swift

升级到 macOS 26 后基本不必——Foundation Models 已经覆盖大部分文本任务。保留作为"特殊领域大模型"的兜底通路。

---

## 推荐 Roadmap（按落地性排序）

1. **润色挡**（本次 PR，已设计）
2. **领域词表偏置**（`SFSpeechLanguageModel`）—— 投入小、收益立竿见影
3. **语言检测**（`NLLanguageRecognizer`）—— 让 Auto 挡更稳，顺手活
4. **翻译挡**（`Translation`）—— 和润色挡正交，独立开关
5. **语气挡**（Foundation Models 多 prompt）—— 复用润色基建
6. **结构化抽取 + App Intents**（Foundation Models guided generation + AppIntent）—— 进入 Shortcuts 生态
7. **上下文感知**（前台 app + `contextualStrings` + Live Text）
8. **回读校对**（AVSpeechSynthesizer）
9. **环境/收尾智能化**（`SoundAnalysis`）

每一项都可以独立 PR，互不阻塞。后续真要做时再各自开设计文档。
