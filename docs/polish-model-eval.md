# Polish 质量评估 + 候选模型调研（迭代记录）

> 状态：**实测 + 调研**
> 范围：从 Phase 5.1 v0.3.8 开始观察到的 polish 质量问题，以及为换模型做的桌面调研。
> 关系：[adaptive-polish.md](adaptive-polish.md) 是 Phase 5.x 的架构设计；本文档专注**质量评估和模型选型**这一条线。

---

## 1. v0.3.8 测试矩阵实测结果（2026-04-27 晚间）

### 1.1 测试设置

- 测试程序：`/tmp/scribe_llama_probe`（Swift CLI，调真实 Qwen2.5-1.5B-Instruct-Q4_K_M GGUF）
- 系统提示词：与 [PolishPrompt.swift](../Sources/Scribe/Refinement/PolishPrompt.swift) 一致（含 5 条 few-shot + persona/recent 拼装框架）
- ChatML 包装：`<RAW>...</RAW>` 用户消息（v0.3.8 引入）
- 用例数：36
- 涵盖：5 种语言（en/zh-CN/ja/ko + 部分 zh-TW）× 14 种语言学场景 + 真实用户口水稿样本

### 1.2 自动判分的盲区

我用了简单 heuristic（`mustContain` / `mustNotContain` / 长度 / token leak / persona-token 出现）做自动判分，**通过 31/36**。**但人工核对发现真实合格只有约 22-24 个** —— heuristic 没覆盖：

| 漏检类型 | 一个真实例子 |
| --- | --- |
| **语言翻译** | JA "あのーですねえっとそのプロジェクト…" → ZH "那个项目进展还不错。"（**翻译了！违反 do-not-translate 规则**） |
| **语义翻转** | "我能不知道吗"（反问 = 我当然知道） → "我能知道吗？"（疑问 = 反义，**意思 180° 翻转**） |
| **句首 filler 残留** | "嗯那个吧就是说啊…" → "嗯，那个吧，就是说啊…"（只加标点，filler 全留） |
| **few-shot 幻觉** | 单字输入 "嗯" → 模型把 example 里的 "把这个 feature 在周二上线" 抄进输出 |
| **内容幻觉** | "调整我的说出来的口水语" → 输出多了一句 "他还说了一些口水语"（原文没说） |

### 1.3 真实失败分类

```
模型容量天花板（prompt 修不动 / 暂没解）：
  ❌ persona-leak（"我是向松涛" + "你是谁吗" → 答案泄漏）
  ❌ 句首 嗯 残留（被 1.5B 当 discourse marker 不当 filler）
  ❌ 负词丢失（"我能不知道吗" → "我能知道吗"）
  ❌ JA / KO 输入下指令遵循差（被翻译成中文）
  ❌ persona 内容被原样 paste 进输出

prompt 还有空间能优化的：
  ⚠ few-shot leakage 在极短输入上（"嗯"）
  ⚠ 内容幻觉（边界扩张）
  ⚠ 反问 → 陈述句的转换（丢失语用细节）

设计原本想做但 1.5B 做不到的：
  ⚠ persona-aware 音近字纠错
     例：persona「到那时 = 但是」+ raw「我打了字到那时他显示白色的」
         期望："我打字了，但他显示白色，是个问题。"
         实际："我打字到那时，他显示白色是问题。"（"到那时" 没纠正）
```

### 1.4 失败原始数据（保留以便对比新模型）

> 完整 36 个用例的输入、persona、输出在 `/tmp/scribe_llama_probe/main.swift`。
> 关键失败用例（带 reproduction 数据）：

```
[REGRESS-persona-leak]
  PERSONA: 我是向松涛
  RAW:     你知道我是谁吗
  OUT:     你知道我是向松涛。           ← 应该输出 "你知道我是谁吗？"

[ADV-persona-name-leak]
  PERSONA: 我叫向松涛。
  RAW:     猜猜我叫什么
  OUT:     我叫向松涛。                 ← 应该输出 "猜猜我叫什么？"

[JA-fillers]（违反 do-not-translate）
  RAW:     あのーですねえっとそのプロジェクトはまあいい感じで進んでます
  OUT:     那个项目进展还不错。         ← 输出应是日文清理版

[ZH-rhetorical-2]（语义翻转）
  RAW:     我能不知道吗
  OUT:     我能知道吗？                 ← 丢了 "不"，意思反了

[ZH-fillers-stack]（filler 没去掉）
  RAW:     嗯那个吧就是说啊我觉得这个事情吧应该挺好的吧
  OUT:     嗯，那个吧，就是说啊我觉得这个事情挺好的。   ← 加标点≠去 filler

[EDGE-short-zh]（few-shot 幻觉）
  RAW:     嗯
  OUT:     嗯，我觉得我们应该把这个 feature 在周二上线。  ← 完全编的

[REAL-zh-2-instruction]（persona 内容 paste）
  PERSONA: 我是 AI 工程师。茱萸是听写时对助词的音近误识别...
  RAW:     茱萸主谓代词之类的虚拟词拟声词啊反问答非所问等等都可以作为测试
  OUT:     我是AI工程师。茱萸是听写时对助词的音近误识别...   ← 把 persona 抄进输出

[REAL-zh-4-typo]（persona 无效）
  PERSONA: 我是 AI 工程师。「到那时」是「但是」的音近误识别。
  RAW:     我打了字到那时他显示白色的是个问题
  OUT:     我打字到那时，他显示白色是问题。   ← 没纠正 "到那时"
```

### 1.5 改进 heuristic 的方向（下一轮测试要加）

- 语言检测：如果 raw 是 ja/ko 但输出是 zh，自动 fail
- 否定词保留：raw 含「不/没/no/not」时，输出必须保留对应的否定词
- 幻觉检测（hard）：输出长度不能比 raw 多 50% 以上字符（除非是必要的标点）

---

## 2. 候选小模型调研

### 2.1 评估维度

| 维度 | 权重 | 说明 |
| --- | --- | --- |
| 体积（Q4_K_M） | 高 | < 2 GB 是设计上限（首次下载体验） |
| CJK 支持 | **极高** | 用户主要用中文，必须中文原生 |
| 指令遵循（小模型最大瓶颈） | **极高** | 当前 1.5B 在我们 prompt 下经常违反规则 |
| 多语种保持（不翻译） | 高 | JA / KO 输入不能被翻成 ZH |
| 推理延迟（M2，30-token 输出） | 高 | 需要 ≤ 1.5s（保留预算给 prompt decode） |
| 许可 | 中 | 想要 Apache 2.0 / MIT，不要带商业限制条款 |
| ChatML 兼容 | 低 | 不兼容也能改 LocalPolishService 的模板，1 小时活 |

### 2.2 候选清单

> 数据基于 2026-04 公开发布信息和我对这些模型架构的认识；具体效果**必须实测**才能下定论。

| 模型 | 参数 | Q4 体积 | 许可 | CJK | 我的预期（待实测）|
| --- | --- | --- | --- | --- | --- |
| **Qwen2.5-1.5B-Instruct** ⬅ 当前 | 1.5B | ~0.95 GB | Apache 2.0 | 强（阿里原生）| 已知问题见 §1.3 |
| Qwen2.5-3B-Instruct | 3B | ~1.8 GB | Apache 2.0 | 强 | **重点候选** — 同家族 2x 容量，是「容量瓶颈 vs 架构问题」的关键控制变量 |
| Qwen2.5-7B-Instruct | 7B | ~4.4 GB | Apache 2.0 | 强 | M2 上 30-token 输出 ~2-3s，**贴近 3s 软上限**，体积也大；备选 |
| **Qwen3-4B-Instruct**（如已发布稳定 GGUF）| 4B | ~2.4 GB | Apache 2.0 | 强 | 新一代，指令遵循通常显著好于 2.5；**重点候选** |
| Qwen3-1.7B-Instruct | 1.7B | ~1.0 GB | Apache 2.0 | 强 | 同 size 但新一代，看是否能压住 1.5B 的问题 |
| **Gemma 2 2B-Instruct** | 2B | ~1.5 GB | Gemma 许可（商用 OK 但有禁止条款）| 中 | 用户提名做对比；多语种比 Qwen 弱，但训练数据更干净，幻觉可能更少 |
| Gemma 3 1B / 4B | 1B/4B | ~0.6/2.5 GB | Gemma 许可 | 中 | 2025 新一代，对话能力较 G2 强；CJK 是否够用要测 |
| Phi-3.5-mini-instruct | 3.8B | ~2.2 GB | MIT | 中 | 英文非常强，CJK 中等；**幻觉历史**有名 |
| Llama 3.2-1B-Instruct | 1B | ~0.75 GB | Llama 3 许可 | 弱 | 体积有诱惑，但 CJK 表现弱；**不推荐做主力**，只做对比 |
| Llama 3.2-3B-Instruct | 3B | ~1.8 GB | Llama 3 许可 | 中 | 同上，3B 版 CJK 略好但仍弱于 Qwen |
| DeepSeek-R1-Distill-Qwen-1.5B | 1.5B | ~0.95 GB | MIT | 强 | 基于 Qwen 蒸馏，强化推理；指令遵循是否赢 1.5B 原版**值得一测** |

### 2.3 用户关注点 → 候选侧重

按用户已经出过问题的 case 反推：

- **persona-leak** —— 主要靠**容量**，建议：Qwen2.5-3B、Qwen3-4B
- **JA/KO → ZH 翻译** —— 多语种训练数据 + 指令遵循，建议：Qwen2.5-3B+
- **filler 去除弱** —— 指令遵循 + 中文细致度，建议：Qwen3 系列
- **persona-aware 音近字纠错** —— 极强的上下文推理能力，**1.5-3B 都可能做不到**，建议：Qwen2.5-7B 或干脆放弃这个目标
- **Gemma 对比的价值** —— 不在于它一定更好，而在于**作为不同家族的对照**，能告诉我们「问题是 Qwen 特有还是小模型通病」

### 2.4 推荐的实测排序（按"信息量 ÷ 成本"）

每个候选的成本 ~= 下载（1-3 min）+ probe 跑 36 个 case（~50 sec）+ 人工核对（~5 min）。

```
推荐 Round 1（实测 3 个，约 20 分钟）：

  1. Qwen2.5-3B-Instruct-Q4_K_M
     → 最直接的「容量是否够」实验。如果 3B 能解决 50% 以上的 §1.3 失败，
       那答案就是「上 3B」，不用换家族。

  2. Qwen3-4B-Instruct-Q4_K_M（如有稳定 GGUF）
     → 测试「新一代是否对小模型痛点有改进」。如果 4B 全过，
       那 Phase 5.x 直接定 Qwen3-4B。

  3. Gemma 2 2B-IT-Q4_K_M
     → 用户指定的对照。看跨家族结果。如果 Gemma 在 CJK 上
       远弱于 Qwen，那 Gemma 路线否决；如果接近，留作备选。

Round 2（视 Round 1 结论决定）：
  - 如果 Round 1 仍未解决 persona-leak / JA→ZH，上 Qwen2.5-7B
  - 如果 Round 1 都比 1.5B 强但仍有问题，看 DeepSeek-R1-Distill
```

### 2.5 实测协议

每个候选模型走同一套流程，结果横向对比：

1. 下载 GGUF 到 `/tmp/scribe_llama_probe/<model>.gguf`
2. probe 改 `modelPath` 指向新文件
3. 跑全部 36 个 case
4. 用 `tee` 把输出存进 `docs/eval-runs/<model>-<date>.txt`（commit 进 repo 留底）
5. 关键失败用例（§1.4 的 8 个）做人工对比表
6. 综合打分：
   - 严重失败 = 1×
   - 警告 = 0.5×
   - 通过 = 1
   - 总分 / 36 → 「合格率」百分比
7. 结合**延迟**（30-token 平均生成时间）和**体积**给一个「值不值得换」的结论

### 2.6 不在范围内（避免设计扩散）

- 同时换模型 + 换推理引擎（MLX-Swift 等）：先把模型选定，引擎层之后再单独评估
- 多模型并存让用户选：违反 [local-refinement.md](local-refinement.md) §10 的「用户不选模型」原则
- Apple FoundationModels 这条线：那是另一个独立 backend，本文档不涉及

---

## 3. 状态记录（写完先睡，醒来继续）

- 已完成：测试矩阵建立、v0.3.8 实测、失败分类、候选清单、推荐顺序
- **待你决定**：要不要按 Round 1 跑那 3 个候选？还是先只跑某一个？
- 不在动：当前代码已经 release 到 v0.3.8，没有 in-flight 的 commit
