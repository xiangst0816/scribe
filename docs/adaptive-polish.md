# Adaptive Polish —— 学习用户口吻的润色（设计文档）

> 状态：评审过 / Phase 5.0 即将实施
> 范围：在 [local-refinement.md](local-refinement.md) v1（静态 system prompt）基础上，让 Local backend 的 prompt 能逐步**理解用户是谁、领域是什么**——而不是记词表。
> 关系：仅作用于 **Local backend (Qwen2.5-1.5B)**。System backend（Apple Intelligence）已经在 OS 层做用户级个性化，不再叠加。

## 评审决议（已与用户对齐）

| 议题 | 决议 |
| --- | --- |
| Layer 2 学什么 | **不是词表 / 白名单**——是 *用户是谁*：领域、角色、混语习惯。Qwen 据此推测听写本意，例如把误识别的「系统提示词」保留为中文，不要回译成 "system prompt"。 |
| 触发频率 N | **5 句**。每收到 5 条新转写，后台跑一次 digest |
| Layer 2 容量 | 硬上限 **1000 字符** |
| Layer 3 容量 | **最多 5 条，每条 ≤ 100 字符** |
| 存放位置 | 与模型同目录：`~/Library/Application Support/Scribe/`（不放 `style/` 子目录） |
| Reset 按钮 | **本期不做**。Settings 面板只展示文件路径 + 一键在 Finder 打开就够了 |
| 动态语气 / per-app | **Phase 5.3 再说**。先把通用部分做扎实 |
| 优先级 | **先做 Phase 5.0**（静态 prompt 升级），其他下次再说 |

### 指导原则：**信任模型，让它预测**

Polish 是**高级模式**，目标不是把 prompt 写得保守 / 防御性 / 不出错，而是**把模型的能力用满**——让它根据「用户是谁」+「最近说过什么」+「当前这句话的语境」来**推测出语义本意**，再写成通顺的句子。

具体含义：

- 不要担心 prompt 长一点。Qwen 1.5B 有 32K context，多 200 token 的 examples 只多几百 ms。
- 不要靠规则启发式（句长、缩写率…）来生成 Layer 2——那些做出来的是「统计画像」，不是「这个人是谁」。该用 LLM 自总结，让 Qwen 自己看 raw 转写后描述用户。
- 这条原则**不绑定 Qwen**——我们后面如果换更强的本地模型（更大的 Qwen，或 MLX-Swift 跑别的），同一份 prompt 设计应该平滑收益更多。

---

## 0. 这次要回答的核心问题

1. **「学」什么？**——固定模板里哪些位置应该被用户的口吻替换。
2. **「学」从哪来？**——是从原始转写文本里学，还是从润色后的输出里学，还是两者都看。
3. **存在哪？**——隐私敏感，需要明确文件位置 + 用户可控开关。
4. **什么时候学？**——同步在 polish 之后？后台任务？显式触发？
5. **怎么避免越学越偏？**——污染检测、容量上限、用户「重置」按钮。

---

## 1. 提议的三层结构

按用户拍板的 **L1 / L2 / L3** 框架（不再用之前文档里 A/B/C 的混杂记法）：

```
┌──────────────────────────────────────────────┐
│  L1 — 程序固定（in code，不可变）            │
│   • 角色（你是 transcript polisher）         │
│   • 硬规则 + 输出格式约束                    │
│   • {{language_hint}} 占位符（运行时按       │
│     selectedLocaleCode 替换 — 这只是 L1 内的 │
│     参数化，不另起一层）                     │
│   • 内置 few-shot 示例                       │
└──────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────┐
│  R — 运行时上下文（占位，本期不填）          │
│   • 前台 app 名 → 语气暗示（Phase 5.3）      │
│   • 当前时段（可选，待评估）                 │
│   • 拼装时若为空整段省略                     │
└──────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────┐
│  L2 — 用户是谁（user persona）               │
│   • Settings 里 textarea 用户手写            │
│   • Phase 5.2 起：Qwen 自总结从 L3 推导      │
│   • 容量 ≤ 1000 字符                         │
└──────────────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────┐
│  L3 — 最近的对话                             │
│   • 滚动 5 条，每条 ≤ 100 字符               │
│   • 存的是「**最终文本**」：                 │
│       - polish 开 → 存 polish 输出           │
│       - polish 关 → 存 raw 转写              │
│   • 模型据此推测当前用户「这种写法的人」    │
│     可能想说什么                             │
└──────────────────────────────────────────────┘
```

**拼装结果**（本期 R 段为空整段省略，L2 / L3 可独立为空）：

```
[L1 文本]

[R: runtime context]            ← 占位，本期注释掉、不参与拼装
   (e.g. "User is currently dictating into Mail app …")

About the user (who they are):  ← L2 段，若文件为空则整段省略
[L2 文本]

User's recent finished writing (for context):  ← L3 段，若空则整段省略
- "<最近第 1 条最终文本>"
- "<最近第 2 条最终文本>"
- ...

Output ONLY the polished text. No preface, no markdown.
```

### 1.1 各层的归属

| 层 | 存放位置 | 谁能修改 |
| --- | --- | --- |
| L1 程序固定 | Swift 源码 (`PolishPrompt.system`) | 仅 Scribe 开发者，随版本升级 |
| R 运行时上下文 | 拼装函数参数 | Phase 5.3 才填，本期跳过 |
| L2 用户是谁 | `~/Library/Application Support/Scribe/persona.txt` | 用户可见、可手写；Phase 5.2 起 Qwen 也写 |
| L3 最近对话 | `~/Library/Application Support/Scribe/recent.jsonl`（5 条滚动） | 程序自动维护；用户可在 Finder 看 |

L1 在内存里 + L2 / L3 启动时读一次缓存。L3 在每次成功 polish 之后追加一行（5 条满了删最旧的）。L2 由后台 digest 任务写入（Phase 5.2 起）或 Settings textarea 手动写入。

---

## 2. 怎么学（Layer C 的产生方式）

四种候选，按取舍递减：

| 方案 | 怎么做 | 优 | 劣 |
| --- | --- | --- | --- |
| **(a) 规则启发式** | 统计 filler 频率、句长分布、是否有 code-switch、是否多用 em-dash 等 | 完全可控、零 LLM 开销、可解释 | 学到的特征粒度粗，写不出 "user prefers 'totally' over 'absolutely'" 这种 |
| **(b) Qwen 自总结** | 喂给 Qwen 最近 N 条 *raw + polished* 对，问它 "What's this user's voice?" | 与润色用同一个模型，行为一致 | 1.5B 总结质量有限；每 N 条多一次推理；可能产生噪声 |
| **(c) Apple FM 自总结** | 同上但用 Apple FM | 总结质量更好 | 仅在 macOS 26+ 可用区可用，跟「Local backend 才需要这个」的目标矛盾 |
| **(d) 用户手写** | Settings 里直接给个 textarea 让用户描述自己的口吻 | 最准、零自动化风险 | 用户多半懒得写 |

**建议组合**：**(a) + (d)**。

- (a) 是免费 + 总在跑的兜底；启动后立刻能产出初步档案。
- (d) 给重度用户一个显式入口：Settings 里加一个 "我的口吻（可选）" 文本框，用户写一句"casual technical Chinese-English mix" 就直接写进 Layer C，覆盖启发式产物。
- (b) 留作 Phase 5 的可选增强，**默认关**。开了之后才会跑 Qwen 总结。

(c) 直接否决——违反层级目标。

### 2.1 启发式版本（方案 a）能学什么

实测 attribute，每条都映射成一行简短描述：

| 启发式 | 阈值 | 写进档案的样子 |
| --- | --- | --- |
| 平均句长 < 8 词 | 50% 以上转写 | "User tends to dictate short imperative sentences." |
| 平均句长 > 25 词 | 50% 以上转写 | "User dictates long, multi-clause sentences; preserve structure." |
| 中英 code-switching 出现率 > 20% | — | "User mixes English technical terms into Mandarin freely; do not translate them." |
| 出现 ≥ 5 次的特定术语（去停用词） | 在最近 50 条转写中 | "Frequent terms: Swift, async/await, Sparkle." |
| 缩写率（"I'll", "we'd", "won't"）> 30% | — | "Casual register; keep contractions." |
| 几乎不用问号 | — | （省略，无信息量） |

每条独立 emit，最多取前 5 条。结果就是 Layer C 的文本。

### 2.2 数据从哪来

**存的是「用户最终发出去的那一段」**，不是 raw 转写：

- 如果 polish 开着 → 存 polished 输出（粘贴到光标的版本）
- 如果 polish 关着 → 存 raw 转写

理由：L2 学的是**用户是谁**，体现在他/她**写出来的最终文本**里——这才是用户认可的自我表达。raw 里的 "嗯/那个" 是听写中间产物，对识别用户身份没价值，反而会污染。

写入时机：每次 `AppleSpeechSession` 拿到 final transcript，且 `coordinator.maybePolish` 返回值（无论是 polish 输出还是 raw fallback）准备粘贴前，**那一段就是要存的「最终文本」**。

```
~/Library/Application Support/Scribe/recent.jsonl
```

每行一条 JSON，硬上限 5 条滚动（不是之前写的 50 条）：

```json
{"ts": "2026-04-27T16:30:00Z", "lang": "zh-CN", "text": "我觉得我们应该把这个 feature 在周二上线。"}
```

**截断策略**：单条 ≥ 100 字符的截到 100；超过 5 条删最旧的。文件大小预估 < 5 KB。

---

## 3. 什么时候学

不要每次 polish 都重算。规则：

1. **每 N 条新转写后触发一次后台学习**，N = 5（不是用户说的 3——3 太密集，学习抖动大；5 是个折中）。
2. 后台任务：扫 `transcript-history.jsonl` 中的最近 50 条，跑启发式，写新版 `profile.txt`。
3. 后台任务的执行用 `Task.detached(priority: .background)`，**不阻塞 polish 主流程**。
4. App 启动时也跑一次，保证档案是最新的（防止上次跑完后用户卸载/装回）。

---

## 4. 隐私、可控、可观测

> 这是这个 feature 能不能上线的真正的硬门槛。Scribe 当前 README 明文写「audio is discarded after each push-to-talk」。引入 L2/L3 持久化必须明确划界。

### 4.1 Settings 里的入口（不做 Reset 按钮）

Polish 主开关下加一个独立 sub-section：

```
☐ Adapt to my voice over time
   Scribe will keep the text of your last 5 dictations in
   ~/Library/Application Support/Scribe/ to learn what you write like.
   Text only — no audio, never uploaded. Off by default.

   [ Open Scribe folder in Finder ]
```

**默认关**。除非用户主动打勾，**L2/L3 文件都不会被持久化**。

按用户决议，**本期不做 Reset 按钮**——给用户一键打开 Finder 即可，要清就直接删文件。Settings 面板的视觉对齐 [SettingsWindow](../Sources/Scribe/SettingsWindow.swift) 现有的 Polish 那个 sub-section 风格。

### 4.2 五份 README 的隐私章节必须更新

加一段：

> **Adaptive polishing (off by default).** If you opt in, Scribe stores
> the *text* of your last 5 dictation outputs (the final pasted text,
> not raw audio) under `~/Library/Application Support/Scribe/`,
> alongside a short user-persona summary. Everything stays on your Mac;
> nothing is uploaded. The folder is visible and editable from Finder.

### 4.3 可观测

- 「Open Scribe folder in Finder」按钮：直接 reveal `~/Library/Application Support/Scribe/`。用户能看到 `persona.txt`、`recent.jsonl`、模型文件全在一起，要删/要看/要改都直观。

透明度比聪明度重要。

---

## 5. 同时还要做的：把当前 prompt 升级（与上面解耦）

这是**今天就能做、不依赖三层结构**的低成本改进，独立于上面整套学习架构：

### 5.1 给 Layer A 加规则

补两条目前缺的：

- **自更正**：明确 "if speaker says X then corrects to Y, output Y only"。当前 prompt 没说这个。
- **CJK fillers**：当前 prompt 列举的 filler 是英文的；加上 "嗯", "那个", "あのー", "어"。

### 5.2 给 Layer A/B 加 few-shot 示例

3-4 个，覆盖不同模式：

```
raw: "uh so I I think we should um maybe ship the the feature on Tuesday I guess"
out: "I think we should ship the feature on Tuesday."

raw: "the meeting is on Tuesday actually no wait Wednesday at 3pm"
out: "The meeting is on Wednesday at 3pm."

raw: "嗯那个我觉得我们应该应该把这个那个 feature 在周二上线吧"
out: "我觉得我们应该把这个 feature 在周二上线。"

raw: "yeah totally I'm down let's grab coffee tomorrow um around 10 maybe"
out: "Yeah totally — I'm down, let's grab coffee tomorrow around 10."
```

### 5.3 风险

小模型容易**记忆 examples 字面**——在无关输入上输出 "ship the feature on Tuesday" 之类的串。缓解：

- 选词多样化，不重复短语
- 例子数量上限 4 条
- 真上线前用本机已有的 Qwen 实测一批 corner case

---

## 6. 实施分阶段

**Phase 5.0**（今天就能上，不依赖任何架构改动）：
1. 升级 Layer A 文案（自更正 + CJK fillers）
2. 加 4 条 few-shot 示例
3. 本机用 Qwen 验证 5-10 个真实 case
4. tag 一个小版本（比如 v0.3.3）

**Phase 5.1**（结构化，但仍是静态）：
5. 把单一 system 字符串重构成 `assemble(coreA, contextB, profileC)` 函数
6. profile C 默认空，通过 settings 里那个 textarea 让用户手写（方案 d）
7. View / Reset profile 按钮

**Phase 5.2**（启发式自动学习，opt-in）：
8. 转写历史的 JSONL 滚动文件
9. Settings opt-in 开关 + 计数显示
10. 启发式分析器
11. README 隐私章节更新

**Phase 5.3**（增强，可选）：
12. 用 Qwen 自总结代替/补充启发式
13. 可能的 per-app context（前台 app 决定语气，参考 Typeless 的做法）

每一阶段独立可上线，**低阶段先验证有用了再投高阶段**。

---

## 7. 关键风险与待确认

1. **"学习"听起来很性感，但真能改善输出吗**？测试方法：在真实用户口语上跑 Phase 5.0 的静态版 vs Phase 5.2 的启发式版，盲评 30 条样本，看个性化版是否真的更"像我"。如果差距 < 5%，就别做 Phase 5.2 / 5.3。
2. **Layer C 注入时机**：每次都从磁盘读？还是 in-memory cache + filesystem watch？在 .deliverFinal 的关键路径上不能多 ms。建议启动时读一次 + 后台学习任务原子写入后通知主流程刷新。
3. **不同语言的档案怎么处理**？同一档案描述中英混说？还是 per-language 多份？倾向于一份，因为很多用户就是混着用的。
4. **多设备同步**？目前 Scribe 没有云端同步。档案文件可以放进 iCloud Drive 让用户手动复制——不在 Scribe 范围内。
5. **滚动 14 天 / 50 条** 是否合理？数太少学不到稳定模式，数太多老旧风格会拖累现状。需要等真用起来再回调参数。

---

## 8. 不在范围内（避免设计扩散）

- 上传任何东西到云端。
- 跨设备同步。
- 给用户的"档案"做版本管理 / undo 历史——磁盘文件即是状态，简单就好。
- 多用户（macOS 上一个账户对应一个用户的假设成立）。
- 跟踪用户是否「采纳了」polished 结果（需要 hook 进 paste 反馈链路，复杂度高，收益不明）。
