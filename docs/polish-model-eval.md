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

### 2.2 候选清单（含 Gemma 4，2026-04-27 重新核实）

> Gemma 4 在 2026-04-02 发布，比当前晚 3 周。Apache 2.0 许可（Gemma 2/3 是 Gemma-specific license，Gemma 4 改成完全开放）。**关键反直觉**：Gemma 4 用 "E2B / E4B" 命名指**有效参数量**（per-token MoE 激活量），但 GGUF 文件大小由**总参数量**决定，所以 E2B 体积远比 Qwen 2B 大。

| 模型 | 参数 | Q4_K_M 体积 | 许可 | CJK | 备注 |
| --- | --- | --- | --- | --- | --- |
| **Qwen2.5-1.5B-Instruct** ⬅ 当前 | 1.5B | 0.95 GB | Apache 2.0 | 强（阿里原生）| 已知问题见 §1.3 |
| Qwen2.5-3B-Instruct | 3B | ~1.8 GB | Apache 2.0 | 强 | 同家族 2x 容量；**控制变量**首选 |
| Qwen2.5-7B-Instruct | 7B | ~4.4 GB | Apache 2.0 | 强 | 30-token 输出 ~2–3s，贴近 3s 软上限 |
| **Qwen3-1.7B-Instruct** | 1.7B（1.4B 非 embedding）| ~1.0 GB | Apache 2.0 | 强 | 比 Qwen2.5-1.5B 新一代；同 size 直接对比 |
| **Qwen3-4B-Instruct** | 4B | ~2.4 GB | Apache 2.0 | 强 | 新一代+大容量；指令遵循通常胜 2.5 |
| **Gemma 4 E2B-it** ⬅ 用户指名 | **5B 总 / ~2B active (MoE)** | **~3 GB** | **Apache 2.0** ✓ | 中-强（140+ 语言原生预训练）| **比 Qwen2.5-3B 文件还大** |
| Gemma 4 E4B-it | 8B 总 / ~4B active (MoE) | **5.34 GB** | Apache 2.0 | 中-强 | **比 Qwen2.5-7B 还大**，对首次下载体验不友好 |
| Gemma 4 26B-A4B | 26B 总 / 4B active (MoE) | ~16 GB | Apache 2.0 | 中-强 | 太大，超出首次下载预算 |
| Phi-3.5-mini-instruct | 3.8B | ~2.2 GB | MIT | 中 | 英文强，CJK 中等；幻觉历史 |
| Llama 3.2-3B-Instruct | 3B | ~1.8 GB | Llama 3 许可 | 弱 | CJK 弱于 Qwen，仅作对比 |
| DeepSeek-R1-Distill-Qwen-1.5B | 1.5B | ~0.95 GB | MIT | 强 | 基于 Qwen 蒸馏强化推理 |

### 2.2.1 Gemma 4 vs Qwen 直接对照（用户最关心）

按 Polish 实际场景的关键维度排：

| 维度 | Qwen2.5-1.5B（当前）| Qwen2.5-3B | Qwen3-4B | **Gemma 4 E2B** | **Gemma 4 E4B** |
| --- | --- | --- | --- | --- | --- |
| Q4 文件大小 | 0.95 GB | ~1.8 GB | ~2.4 GB | **~3 GB** | **5.34 GB** |
| 体积 vs 当前 | 1× | 1.9× | 2.5× | **3.2×** | **5.6×** |
| 上下文窗口 | 32K | 32K | 32K（推测）| **128K** | **128K** |
| 多语种声明 | ~30 well-supported | 同 | 同 | **140+ 原生**（claim）| 同 |
| CJK 训练强度 | 阿里原生（中文母语级）| 同 | 同 | 多语种均匀（**中文未必比 Qwen 强**）| 同 |
| 许可 | Apache 2.0 | Apache 2.0 | Apache 2.0 | **Apache 2.0** ✓（终于改了）| Apache 2.0 |
| MoE 推理特点 | 非 MoE（dense）| dense | dense | **MoE 5B 激活 ~2B** — 内存占 5B，每 token 计算 ~2B | MoE 8B/4B |
| 首次下载体验 | ✓ 1 GB 可接受 | ✓ 1.8 GB 可忍 | ⚠ 2.4 GB 偏大 | ⚠⚠ **3 GB**（隐形门槛）| ❌ 5.34 GB 不可接受 |
| App bundle 影响 | 0（运行时下）| 0 | 0 | 0 | 0 |
| Polish 延迟（M2 估算）| 24 tok/s ≈ 1.2s | ~12 tok/s ≈ 2.5s | ~10 tok/s ≈ 3s 边缘 | **~15 tok/s ≈ 2s**（MoE 算激活）| ~8 tok/s ≈ 3.5s **超** |

**Gemma 4 E2B 表面上是最直接的"换 Gemma"选择，但有几个真正的 trade-off：**

1. **体积**：3 GB 是 Qwen 1.5B 的 3 倍，比 Qwen2.5-3B 还大。不是「轻量替代」。
2. **CJK**：Gemma 系列声明 140+ 语言，但**未公开过中文 benchmark 跑赢 Qwen**。Qwen 是阿里中文母语训练的，这是它的家门口优势。换 Gemma 在中文上**很可能反而退步**。
3. **MoE 内存模型**：E2B 加载时内存占 5B 模型大小（~3 GB Q4 内存），但每个 token 推理只激活 2B 等效参数。延迟跟 dense 2B 差不多，但内存占用是 dense 5B。M2 24G 完全够，不是问题。
4. **指令遵循**：Gemma 系列在过去版本 instruction-following 比同 size Qwen 弱（Gemma 2 2B vs Qwen2.5-1.5B 多个 benchmark 落后）。Gemma 4 是否反转**得测**。

**结论候选**（按性价比排序）：

```
A. Qwen2.5-3B-Instruct（1.8 GB）
   理由：同家族放大；保持中文母语优势；体积可接受。
   是「容量是不是瓶颈」的最干净对照实验。

B. Qwen3-1.7B-Instruct（1.0 GB）
   理由：同 size 但新一代；看新版指令遵循是否能压住 1.5B 的问题。
   是「新一代 prompt 跟随是不是更好」的对照实验。

C. Gemma 4 E2B-it（3 GB）          ⬅ 用户指名
   理由：跨家族对照；140+ 语言；许可终于 Apache 2.0；新模型架构。
   要警惕：CJK 不一定强于 Qwen，体积是 3 倍。

D. Qwen3-4B-Instruct（2.4 GB）
   理由：新一代 + 大容量，是「最佳 Qwen 路线」候选。

E. Gemma 4 E4B（5.34 GB）和 Qwen2.5-7B（4.4 GB）：
   都太大，超出"首次下载 1 GB"的隐含约定。先不测。
```

### 2.3 用户关注点 → 候选侧重

按用户已经出过问题的 case 反推：

- **persona-leak** —— 主要靠**容量**，建议：Qwen2.5-3B、Qwen3-4B
- **JA/KO → ZH 翻译** —— 多语种训练数据 + 指令遵循，建议：Qwen2.5-3B+
- **filler 去除弱** —— 指令遵循 + 中文细致度，建议：Qwen3 系列
- **persona-aware 音近字纠错** —— 极强的上下文推理能力，**1.5-3B 都可能做不到**，建议：Qwen2.5-7B 或干脆放弃这个目标
- **Gemma 对比的价值** —— 不在于它一定更好，而在于**作为不同家族的对照**，能告诉我们「问题是 Qwen 特有还是小模型通病」

### 2.4 推荐的实测排序（用户指名 Gemma 4，按性价比排序）

每个候选的成本 ~= 下载（GGUF 大小决定，1-3 min）+ probe 跑 36 个 case（~1 min）+ 人工核对（~5 min）。

```
推荐 Round 1（实测 3 个，约 25-30 分钟）：

  1. Qwen2.5-3B-Instruct-Q4_K_M（1.8 GB 下载）
     → 最干净的「容量是否够」实验。同家族 2x；保持中文母语优势。
       如果 3B 解决 50%+ 的 §1.3 失败，结论就是「上 3B」，结束。

  2. Gemma 4 E2B-it-Q4_K_M（~3 GB 下载）  ⬅ 用户指名
     → 跨家族对照。要重点观察：
        a. CJK 输出是否被"翻译化"（Gemma 训练数据更倾向英文化输出）
        b. JA/KO → ZH 翻译 bug 是否消失（多语种 140+ 是 Gemma 4 强项）
        c. Polish 延迟是否仍在 3s 内
        d. persona-leak 是否被压住（更大模型更可能能压）

  3. Qwen3-1.7B-Instruct-Q4_K_M（1.0 GB 下载）
     → 同 size 不同代对照。如果 Qwen3-1.7B 都比 Qwen2.5-1.5B 好，
       那"换 Qwen3 系列"是几乎零成本的升级路径。

Round 2（视 Round 1 结论决定）：
  - 如果三个都不够，上 Qwen3-4B（2.4 GB）
  - 如果 Gemma 4 E2B 有 CJK 倒退，Gemma 路线整体否决
  - persona-leak 如果三个候选都过不了，确认是「设计目标不可达」，
    需要在产品层面收紧 persona 写法的指引（不是技术问题）
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
