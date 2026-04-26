import AppKit
import QuartzCore

final class OverlayPanel: NSPanel {
    private let waveformView = WaveformView()
    private let spinnerView = SpinnerView()

    private let capsuleHeight: CGFloat = 40
    private let capsuleWidth: CGFloat = 92
    private let waveSize: CGFloat = 44
    private let spinnerSize: CGFloat = 18

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 92, height: 40),
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

        // Shadow host — softer, wider drop for a floating glass feel.
        let shadowHost = NSView(frame: cv.bounds)
        shadowHost.autoresizingMask = [.width, .height]
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -3)
        shadowHost.layer?.shadowRadius = 20
        shadowHost.layer?.shadowOpacity = 1
        cv.addSubview(shadowHost)

        // Dark frosted glass — alpha lowered so the desktop shows through more.
        let effect = NSVisualEffectView(frame: cv.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .fullScreenUI
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = capsuleHeight / 2
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.alphaValue = 0.8
        shadowHost.addSubview(effect)

        // Content layer — sits above the glass at full opacity so icons stay crisp.
        let content = NSView(frame: cv.bounds)
        content.autoresizingMask = [.width, .height]
        content.wantsLayer = true
        content.layer?.cornerRadius = capsuleHeight / 2
        content.layer?.borderWidth = 0.5
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        shadowHost.addSubview(content)

        // Waveform centered.
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(waveformView)

        // Spinner centered, hidden by default.
        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        spinnerView.isHidden = true
        content.addSubview(spinnerView)

        NSLayoutConstraint.activate([
            waveformView.widthAnchor.constraint(equalToConstant: waveSize),
            waveformView.heightAnchor.constraint(equalToConstant: 24),
            waveformView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: content.centerYAnchor),

            spinnerView.widthAnchor.constraint(equalToConstant: spinnerSize),
            spinnerView.heightAnchor.constraint(equalToConstant: spinnerSize),
            spinnerView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
    }

    // MARK: - Public

    func show() {
        waveformView.isHidden = false
        spinnerView.isHidden = true
        spinnerView.stop()
        waveformView.isAnimating = true

        guard let screen = NSScreen.main else { return }
        let area = screen.visibleFrame
        let x = area.midX - capsuleWidth / 2
        let y = area.minY + 56

        setFrame(NSRect(x: x, y: y - 14, width: capsuleWidth, height: capsuleHeight), display: true)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.175, 0.885, 0.32, 1.1)
            animator().alphaValue = 1
            animator().setFrame(
                NSRect(x: x, y: y, width: capsuleWidth, height: capsuleHeight), display: true)
        }
    }

    func updateAudioLevel(_ level: Float) {
        waveformView.setLevel(CGFloat(level))
    }

    /// Post-recording state: hide waveform, show spinner only.
    func showLoading() {
        waveformView.isAnimating = false
        waveformView.isHidden = true
        spinnerView.isHidden = false
        spinnerView.start()
    }

    func dismiss() {
        waveformView.isAnimating = false
        spinnerView.stop()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
            animator().setFrame(
                NSRect(
                    x: frame.origin.x + frame.width * 0.02,
                    y: frame.origin.y - 8,
                    width: frame.width * 0.96,
                    height: capsuleHeight),
                display: true)
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}

// MARK: - Audio-driven waveform bars

private final class WaveformView: NSView {
    private let barCount = 5
    private var barLayers: [CALayer] = []
    var isAnimating = false

    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothedLevel: CGFloat = 0
    private let minBarFraction: CGFloat = 0.18

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
        let attack: CGFloat = 0.4
        let release: CGFloat = 0.15
        let factor = level > smoothedLevel ? attack : release
        smoothedLevel += (level - smoothedLevel) * factor

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
