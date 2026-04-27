import AppKit
import QuartzCore

final class OverlayPanel: NSPanel {
    private let waveformView = WaveformView()
    private let spinnerView = SpinnerView()
    private let transcriptLabel = NSTextField(labelWithString: "")
    private let transcriptBackground = NSVisualEffectView()

    private let capsuleHeight: CGFloat = 34
    private let capsuleWidth: CGFloat = 78
    private let waveSize: CGFloat = 38
    private let spinnerSize: CGFloat = 16

    /// Vertical distance between the capsule and the floating transcript pill above it.
    private let transcriptGap: CGFloat = 8
    /// Width budget for the transcript pill — generous so a single long sentence fits.
    private let transcriptWidth: CGFloat = 520
    /// Reserved space above the capsule for the transcript pill. The pill itself
    /// auto-sizes to its content; this just bounds the panel so a 3-line sentence fits.
    private let transcriptMaxHeight: CGFloat = 80

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        // Start tall enough to host both the transcript area and the capsule.
        // The capsule sits at the bottom of `contentView`, the transcript pill
        // floats above it.
        let panelHeight = capsuleHeight + transcriptMaxHeight + transcriptGap
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: transcriptWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false

        let cv = contentView!
        cv.wantsLayer = true

        buildTranscriptPill(in: cv)
        buildCapsule(in: cv)
    }

    private func buildCapsule(in cv: NSView) {
        // Bottom-anchored capsule, horizontally centered.
        let capsuleHost = NSView()
        capsuleHost.translatesAutoresizingMaskIntoConstraints = false
        capsuleHost.wantsLayer = true
        capsuleHost.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        capsuleHost.layer?.shadowOffset = CGSize(width: 0, height: -3)
        capsuleHost.layer?.shadowRadius = 20
        capsuleHost.layer?.shadowOpacity = 1
        cv.addSubview(capsuleHost)

        let effect = NSVisualEffectView()
        effect.translatesAutoresizingMaskIntoConstraints = false
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = capsuleHeight / 2
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.alphaValue = 0.8
        capsuleHost.addSubview(effect)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.wantsLayer = true
        content.layer?.cornerRadius = capsuleHeight / 2
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        capsuleHost.addSubview(content)

        waveformView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(waveformView)

        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        spinnerView.isHidden = true
        content.addSubview(spinnerView)

        NSLayoutConstraint.activate([
            capsuleHost.widthAnchor.constraint(equalToConstant: capsuleWidth),
            capsuleHost.heightAnchor.constraint(equalToConstant: capsuleHeight),
            capsuleHost.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            capsuleHost.bottomAnchor.constraint(equalTo: cv.bottomAnchor),

            effect.leadingAnchor.constraint(equalTo: capsuleHost.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: capsuleHost.trailingAnchor),
            effect.topAnchor.constraint(equalTo: capsuleHost.topAnchor),
            effect.bottomAnchor.constraint(equalTo: capsuleHost.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: capsuleHost.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: capsuleHost.trailingAnchor),
            content.topAnchor.constraint(equalTo: capsuleHost.topAnchor),
            content.bottomAnchor.constraint(equalTo: capsuleHost.bottomAnchor),

            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 16),
            waveformView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: content.centerYAnchor),

            spinnerView.widthAnchor.constraint(equalToConstant: spinnerSize),
            spinnerView.heightAnchor.constraint(equalToConstant: spinnerSize),
            spinnerView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    private func buildTranscriptPill(in cv: NSView) {
        // Wrapper that sits directly above the capsule. Hidden until partial
        // text arrives. The visual effect view gives it the same frosted look.
        transcriptBackground.translatesAutoresizingMaskIntoConstraints = false
        transcriptBackground.material = .fullScreenUI
        transcriptBackground.blendingMode = .behindWindow
        transcriptBackground.state = .active
        transcriptBackground.appearance = NSAppearance(named: .darkAqua)
        transcriptBackground.wantsLayer = true
        transcriptBackground.layer?.cornerRadius = 14
        transcriptBackground.layer?.masksToBounds = true
        transcriptBackground.layer?.borderWidth = 0.5
        transcriptBackground.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        transcriptBackground.alphaValue = 0
        cv.addSubview(transcriptBackground)

        transcriptLabel.translatesAutoresizingMaskIntoConstraints = false
        transcriptLabel.font = .systemFont(ofSize: 13, weight: .regular)
        transcriptLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        // Single line, ellipsised at the **head**, not the tail. The user is
        // mid-sentence and the words on the right are the ones they just
        // said — those should always stay visible, with `…` eating the older
        // beginning when the sentence overruns the pill width. Punctuation-
        // based segmenting upstream in `currentSentence(from:)` keeps the
        // visible text scoped to the current sentence.
        transcriptLabel.lineBreakMode = .byTruncatingHead
        transcriptLabel.maximumNumberOfLines = 1
        transcriptLabel.alignment = .center
        transcriptBackground.addSubview(transcriptLabel)

        NSLayoutConstraint.activate([
            transcriptBackground.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            transcriptBackground.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -(capsuleHeight + transcriptGap)),
            transcriptBackground.widthAnchor.constraint(lessThanOrEqualToConstant: transcriptWidth),

            transcriptLabel.leadingAnchor.constraint(equalTo: transcriptBackground.leadingAnchor, constant: 14),
            transcriptLabel.trailingAnchor.constraint(equalTo: transcriptBackground.trailingAnchor, constant: -14),
            transcriptLabel.topAnchor.constraint(equalTo: transcriptBackground.topAnchor, constant: 8),
            transcriptLabel.bottomAnchor.constraint(equalTo: transcriptBackground.bottomAnchor, constant: -8),
        ])
    }

    // MARK: - Public

    func show() {
        waveformView.isHidden = false
        spinnerView.isHidden = true
        spinnerView.stop()
        waveformView.isAnimating = true

        // Reset any leftover transcript from a previous recording.
        setTranscript("")

        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let panelWidth = transcriptWidth
        let panelHeight = capsuleHeight + transcriptMaxHeight + transcriptGap
        let x = area.midX - panelWidth / 2
        let y = area.minY + 32

        setFrame(NSRect(x: x, y: y - 14, width: panelWidth, height: panelHeight), display: true)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            animator().alphaValue = 1
            animator().setFrame(
                NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        }
    }

    func updateAudioLevel(_ level: Float) {
        waveformView.setLevel(CGFloat(level))
    }

    /// Update the floating transcript above the capsule with the current
    /// sentence the user is speaking. Pass an empty string to hide.
    func updatePartialTranscript(_ rawText: String) {
        let sentence = Self.currentSentence(from: rawText)
        setTranscript(sentence)
    }

    private func setTranscript(_ text: String) {
        transcriptLabel.stringValue = text
        transcriptBackground.animator().alphaValue = text.isEmpty ? 0 : 1
    }

    /// Post-recording state (transcribing → polishing): hide waveform, show
    /// spinner, and clear the transcript pill — the partial-text preview is
    /// only relevant while the user is actively speaking. Keeping it on
    /// during loading made the UI feel like the app didn't notice Fn was
    /// released.
    func showLoading() {
        waveformView.isAnimating = false
        waveformView.isHidden = true
        spinnerView.isHidden = false
        spinnerView.start()
        setTranscript("")
    }

    func dismiss() {
        waveformView.isAnimating = false
        spinnerView.stop()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            self.setTranscript("")
        })
    }

    // MARK: - Sentence extraction

    /// Returns just the most recent sentence from `text`. We split on the last
    /// sentence-terminating punctuation Apple Speech might have inserted; if
    /// there is none, the whole running utterance is the current sentence.
    /// Hesitations like "啊" / "um" are kept — they're part of the sentence.
    static func currentSentence(from text: String) -> String {
        let terminators: Set<Character> = ["。", ".", "！", "!", "？", "?", "．"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastIdx = trimmed.lastIndex(where: { terminators.contains($0) }) else {
            return trimmed
        }
        let afterLast = trimmed.index(after: lastIdx)
        // If the terminator is the final character, the user just finished a
        // sentence — show the *previous* sentence so the pill doesn't blank out
        // mid-flow. Find the second-to-last terminator and slice between them.
        if afterLast == trimmed.endIndex {
            let untilTerminator = trimmed[..<lastIdx]
            if let prev = untilTerminator.lastIndex(where: { terminators.contains($0) }) {
                return String(trimmed[trimmed.index(after: prev)...]).trimmingCharacters(in: .whitespaces)
            }
            return trimmed
        }
        return String(trimmed[afterLast...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Audio-driven waveform bars

private final class WaveformView: NSView {
    private let barCount = 5
    private var barLayers: [CALayer] = []
    var isAnimating = false

    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothedLevel: CGFloat = 0
    private let minBarFraction: CGFloat = 0.08

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }

    private func setupBars() {
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            bar.cornerRadius = 2
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    override func layout() {
        super.layout()
        applyBars(level: smoothedLevel)
    }

    func setLevel(_ level: CGFloat) {
        guard isAnimating else { return }
        // Boost the input so quiet speech still produces visible swing,
        // then lift the low end with a sub-linear curve.
        let amplified = min(level * 1.6, 1.0)
        let expanded = pow(amplified, 0.55)
        let attack: CGFloat = 0.65
        let release: CGFloat = 0.22
        let factor = expanded > smoothedLevel ? attack : release
        smoothedLevel += (expanded - smoothedLevel) * factor

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        applyBars(level: smoothedLevel)
        CATransaction.commit()
    }

    private func applyBars(level: CGFloat) {
        let barWidth: CGFloat = 4
        let barGap: CGFloat = 3
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (bounds.width - totalWidth) / 2

        for (i, bar) in barLayers.enumerated() {
            let weight = barWeights[i]
            let fraction = minBarFraction + (1 - minBarFraction) * level * weight
            let jitter = CGFloat.random(in: -0.04...0.04)
            let h = bounds.height * min(max(fraction + jitter, minBarFraction), 1.0)
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let y = (bounds.height - h) / 2
            bar.frame = CGRect(x: x, y: y, width: barWidth, height: h)
        }
    }
}

// MARK: - Loading spinner

private final class SpinnerView: NSView {
    private let ring = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupRing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupRing()
    }

    private func setupRing() {
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        ring.lineWidth = 2
        ring.lineCap = .round
        ring.strokeStart = 0
        ring.strokeEnd = 0.78
        layer?.addSublayer(ring)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGMutablePath()
        path.addEllipse(in: rect)
        ring.path = path
        ring.frame = bounds
    }

    func start() {
        guard ring.animation(forKey: "spin") == nil else { return }
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.fromValue = 0
        rot.toValue = -2 * Double.pi
        rot.duration = 0.9
        rot.repeatCount = .infinity
        // Rotate around the layer's center.
        ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ring.frame = bounds
        ring.add(rot, forKey: "spin")
    }

    func stop() {
        ring.removeAnimation(forKey: "spin")
    }
}
