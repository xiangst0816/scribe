# Logo concept — v3 (locked)

**已选定方案：v3 = Lucide 音频折线，无键帽。**

几何来自 [Lucide audio-waveform](https://lucide.dev/icons/audio-waveform)（ISC，可商用）。

**配色 token：**
- 容器：`#f5f5f7`
- 主色：`#1d1d1f`
- 笔画粗细：2.4 (Lucide 单位)
- 阅读方向：左→右（Lucide 原生）

---

## v3.svg（.app 主图标）

<img src="logo-concepts/v3.svg" width="200">

- 容器：512×512 圆角方形，rx=92
- 折线：缩放 15.33×，居中，留白 72px
- 笔画：2.4 ≈ 37px 绝对宽度

---

## Menubar 状态家族

设计思路：**默认静态、recording 时动起来**，不靠颜色区分。颜色保持纯黑，所有状态都是 template image，菜单栏背景浅/深色都自动反色。

### menubar-idle ✅（locked，静态）

<img src="logo-concepts/menubar-idle.svg" width="100"> &nbsp;&nbsp; <img src="logo-concepts/menubar-idle.svg" width="36"> &nbsp; <img src="logo-concepts/menubar-idle.svg" width="22">

- stroke `#000`，template image
- 状态机里覆盖：`.idle` + `.transcribing` + `.polishing`（任何不在录音的状态都用静态版）

### menubar-recording（路径形变动画）

<img src="logo-concepts/menubar-recording.svg" width="100"> &nbsp;&nbsp; <img src="logo-concepts/menubar-recording.svg" width="36"> &nbsp; <img src="logo-concepts/menubar-recording.svg" width="22">

- stroke `#000`（仍是 template image 配色），通过**路径峰值起伏**模拟实时音频电平
- 4 个关键帧循环（高 → 低 → 不对称 → 极低 → 高），1.6s 一个周期
- 状态机里覆盖：`.recording` + `.armedToStop`

> **预览说明**：上面这张图是 SVG SMIL 动画版，**只用于在 Markdown preview / 浏览器里看效果**。VSCode Markdown preview 用的 webview（基于 Chromium）能正确渲染 SMIL，三档尺寸都会同步播放。
>
> **生产上不能直接喂给菜单栏**——macOS 的 `NSImage` 不渲染 SMIL，丢进 `NSStatusItem` 只会显示第一帧。

---

## 生产环节：怎么把动画接到菜单栏

代码侧需要做的事（**留到接入构建那一步再写**）：

1. 用 `rsvg-convert` 或 `qlmanage` 把 SMIL 的 4 个关键帧分别导出成 8 张 PNG（4 关键帧 × 浅/深色，或者直接靠 template 反色省一半）
2. 在 [AppDelegate.swift](../Sources/Scribe/AppDelegate.swift) 里：
   - `idle` / `transcribing` / `polishing` → 用 `menubar-idle.png` 作为 `NSStatusItem.button.image`，`isTemplate = true`
   - `recording` / `armedToStop` → 起一个 `Timer.scheduledTimer(withTimeInterval: 0.4)` 循环切 4 张 PNG
   - 状态机回到 idle 时，invalidate timer，切回静态

伪代码骨架：

```swift
private var recordingAnimationTimer: Timer?
private let recordingFrames: [NSImage] = (1...4).map { /* load menubar-recording-frame-\($0).png */ }
private var recordingFrameIndex = 0

func updateMenubarIcon(for state: RecordingState) {
    recordingAnimationTimer?.invalidate()
    switch state {
    case .recording, .armedToStop:
        recordingAnimationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingFrameIndex = (self.recordingFrameIndex + 1) % self.recordingFrames.count
            self.statusItem.button?.image = self.recordingFrames[self.recordingFrameIndex]
        }
    default:
        statusItem.button?.image = idleImage
    }
}
```

---

## 还可以微调的旋钮（如果觉得当前动画不对）

- **节奏**：当前 1.6s/周期 = "平静呼吸"。改成 0.9s 会更"激动"，2.5s 会更"沉稳"
- **关键帧数量**：当前 4 帧。多到 8 帧会更"音频化"，少到 2 帧会更"机械化"
- **振幅范围**：当前从 Lucide 原生（peak y=4）到极低（peak y=11）。可以全部缩到 y=8~13 区间让动作更含蓄
- **对称性**：当前帧 3 是不对称的（左高右低交替）。可以全部对称让动作更"中性"

要哪个方向调，告诉我。

---

## 已落地

- [AppIcon.icns](../AppIcon.icns) — 从 [v3.svg](logo-concepts/v3.svg) 通过 `rsvg-convert` + `iconutil` 渲染（10 个 PNG 尺寸 16→1024）
- [Resources/](../Resources/) — 11 张菜单栏 PNG（idle + 4 帧 recording，各带 @2x）
- [AppDelegate.swift](../Sources/Scribe/AppDelegate.swift) — `NSStatusItem` 改用 `NSImage(named:)` 加载 bundle 资源；`.recording` / `.armedToStop` 时跑 0.4s/帧的 `Timer`，挂在 `RunLoop.main` 的 `.common` mode 下（菜单展开时不冻）
- [Makefile](../Makefile) — `cp Resources/*.png $(APP_BUNDLE)/Contents/Resources/`
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) — Lucide ISC 致谢

## 重新生成 .icns（如果之后改 v3.svg）

```bash
mkdir -p AppIcon.iconset
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w $size -h $size docs/logo-concepts/v3.svg > AppIcon.iconset/icon_${size}x${size}.png
done
# 还需要按 .iconset 命名规则补 @2x，详见 Apple iconutil 文档
iconutil -c icns AppIcon.iconset
rm -rf AppIcon.iconset
```

## 重新生成菜单栏 PNG（如果改了 menubar-recording-frame-N.svg）

```bash
for size in 22 44; do
  rsvg-convert -w $size -h $size docs/logo-concepts/menubar-idle.svg > Resources/MenubarIdle$([ $size -eq 44 ] && echo @2x).png
  for i in 1 2 3 4; do
    rsvg-convert -w $size -h $size docs/logo-concepts/menubar-recording-frame-$i.svg > Resources/MenubarRecording$i$([ $size -eq 44 ] && echo @2x).png
  done
done
```
