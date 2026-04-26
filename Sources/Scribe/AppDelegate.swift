import AppKit
import Speech

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let appleProvider = AppleSpeechProvider()
    private let whisperProvider = WhisperSpeechProvider()
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()

    private var activeProvider: SpeechProvider?
    private var isEnabled = true
    private var isRecording = false
    private var isTranscribing = false
    private var currentDownloadProgress: Double?

    private var enableMenuItem: NSMenuItem!
    private var statusInfoItem: NSMenuItem!
    private var qualityItems: [VoiceQuality: NSMenuItem] = [:]
    private var languageItems: [NSMenuItem] = []

    private var selectedLocaleCode: String {
        get { UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLocaleCode") }
    }

    /// Map BCP-47 locale (zh-CN) to Whisper language code (zh). Empty = auto-detect.
    private func whisperLanguageHint(from code: String) -> String? {
        guard !code.isEmpty else { return nil }
        return String(code.split(separator: "-").first ?? "")
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedCode = selectedLocaleCode
        if !savedCode.isEmpty {
            appleProvider.locale = Locale(identifier: savedCode)
        }
        whisperProvider.languageHint = whisperLanguageHint(from: savedCode)

        setupStatusBar()
        setupProviderCallbacks()

        AppleSpeechProvider.requestPermissions { [weak self] granted, errorMsg in
            if !granted, let msg = errorMsg {
                self?.showAlert(title: "Permission Required", message: msg)
            }
        }

        keyMonitor.onFnDown = { [weak self] in self?.fnDown() }
        keyMonitor.onFnUp = { [weak self] in self?.fnUp() }

        if !keyMonitor.start() {
            showAccessibilityAlert()
        }

        // Re-attempt event tap when the app regains focus, so the user can grant
        // Accessibility in System Settings without having to relaunch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isEnabled else { return }
            _ = self.keyMonitor.start()
        }

        // Observe model state, then trigger initial download/load of selected quality.
        ModelManager.shared.onStateChange = { [weak self] quality, state in
            self?.onModelStateChange(quality, state)
        }
        ModelManager.shared.ensureLoaded(ModelManager.shared.selectedQuality)
    }

    // MARK: - Key events

    private func fnDown() {
        guard isEnabled, !isRecording, !isTranscribing else { return }

        // Choose Whisper if ready, else fall back to Apple Speech.
        let provider: SpeechProvider = whisperProvider.isReady ? whisperProvider : appleProvider
        activeProvider = provider

        isRecording = true
        updateStatusIcon()
        overlayPanel.show()
        NSSound(named: .init("Tink"))?.play()

        provider.start()
    }

    private func fnUp() {
        guard isRecording else { return }
        isRecording = false
        isTranscribing = true

        updateStatusIcon()
        overlayPanel.showLoading()

        activeProvider?.stop()
    }

    // MARK: - Provider callbacks

    private func setupProviderCallbacks() {
        let onLevel: (Float) -> Void = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }
        let onError: (String) -> Void = { [weak self] msg in
            guard let self else { return }
            self.isRecording = false
            self.isTranscribing = false
            self.updateStatusIcon()
            NSLog("Scribe overlay error: %@", msg)
            self.overlayPanel.dismiss()
        }
        let onFinal: (String) -> Void = { [weak self] text in
            self?.deliverFinal(text)
        }

        appleProvider.onAudioLevel = onLevel
        appleProvider.onError = onError
        appleProvider.onFinalResult = onFinal
        appleProvider.onLocaleUnavailable = { [weak self] msg in
            self?.showAlert(title: "Language Unavailable", message: msg)
        }

        whisperProvider.onAudioLevel = onLevel
        whisperProvider.onError = onError
        whisperProvider.onFinalResult = onFinal
    }

    private func deliverFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        isTranscribing = false
        updateStatusIcon()

        guard !trimmed.isEmpty else {
            overlayPanel.dismiss()
            return
        }

        overlayPanel.dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.textInjector.inject(trimmed)
            NSSound(named: .init("Pop"))?.play()
        }
    }

    // MARK: - Model state

    private func onModelStateChange(_ quality: VoiceQuality, _ state: ModelState) {
        // Track the *selected* quality's download progress for the status bar icon.
        if quality == ModelManager.shared.selectedQuality {
            switch state {
            case .downloading(let p): currentDownloadProgress = p
            default: currentDownloadProgress = nil
            }
            updateStatusIcon()
        }

        refreshQualityMenu()
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()

        // Top informational row — shows current voice model state at a glance.
        statusInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusInfoItem.isEnabled = false
        menu.addItem(statusInfoItem)

        menu.addItem(.separator())

        enableMenuItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        // Language submenu (Apple Speech fallback only)
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let languages: [(String, String)] = [
            ("System Default", ""),
            ("English (US)", "en-US"),
            ("中文 (简体)", "zh-CN"),
            ("中文 (繁體)", "zh-TW"),
            ("日本語", "ja-JP"),
            ("한국어", "ko-KR"),
        ]
        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == selectedLocaleCode ? .on : .off
            languageItems.append(item)
            langMenu.addItem(item)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // Voice Quality submenu
        let qualityItem = NSMenuItem(title: "Voice Quality", action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        for q in VoiceQuality.allCases {
            let item = NSMenuItem(title: "", action: #selector(changeQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = q.rawValue
            qualityItems[q] = item
            qualityMenu.addItem(item)
        }
        qualityItem.submenu = qualityMenu
        menu.addItem(qualityItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Scribe", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        refreshQualityMenu()
    }

    private func refreshQualityMenu() {
        let selected = ModelManager.shared.selectedQuality
        for q in VoiceQuality.allCases {
            guard let item = qualityItems[q] else { continue }
            let state = ModelManager.shared.states[q] ?? .notDownloaded
            item.title = formatQualityRow(q, state: state)
            item.state = (q == selected) ? .on : .off
        }
        refreshStatusInfo()
    }

    private func refreshStatusInfo() {
        guard let item = statusInfoItem else { return }
        let q = ModelManager.shared.selectedQuality
        let state = ModelManager.shared.states[q] ?? .notDownloaded

        let line: String
        switch state {
        case .notDownloaded:
            line = "\(q.displayName) · Not downloaded"
        case .downloading(let p):
            line = "\(q.displayName) · Downloading \(Int(p * 100))% — using fallback"
        case .downloaded:
            line = "\(q.displayName) · Ready"
        case .loading:
            line = "\(q.displayName) · Loading model…"
        case .ready:
            line = "\(q.displayName) · Active"
        case .failed(let msg):
            line = "\(q.displayName) · \(msg) — click to retry"
        }
        item.title = line
    }

    private func formatQualityRow(_ q: VoiceQuality, state: ModelState) -> String {
        let suffix: String
        switch state {
        case .notDownloaded: suffix = "  ·  \(q.sizeLabel)  ·  Download"
        case .downloading(let p): suffix = "  ·  Downloading \(Int(p * 100))%"
        case .downloaded: suffix = "  ·  \(q.sizeLabel)  ·  Ready"
        case .loading: suffix = "  ·  Loading…"
        case .ready: suffix = "  ·  \(q.sizeLabel)  ·  In Use"
        case .failed: suffix = "  ·  \(q.sizeLabel)  ·  Failed — click to retry"
        }
        return q.displayName + suffix
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil  // always inherit menu-bar foreground

        // Downloading the selected model takes priority in the icon.
        if let progress = currentDownloadProgress {
            let img = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Downloading")
            img?.isTemplate = true
            button.image = img
            button.title = " \(Int(progress * 100))%"
            return
        }
        button.title = ""

        let symbol: String
        if isRecording {
            symbol = "mic.fill"
        } else if isTranscribing {
            symbol = "waveform"
        } else {
            symbol = "mic"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Voice Input")
        img?.isTemplate = true
        button.image = img
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        enableMenuItem.state = isEnabled ? .on : .off

        if isEnabled {
            if !keyMonitor.start() {
                showAccessibilityAlert()
            }
        } else {
            keyMonitor.stop()
            if isRecording {
                activeProvider?.cancel()
                overlayPanel.dismiss()
                isRecording = false
                isTranscribing = false
                updateStatusIcon()
            }
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        selectedLocaleCode = code
        appleProvider.locale = code.isEmpty ? .current : Locale(identifier: code)
        whisperProvider.languageHint = whisperLanguageHint(from: code)

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }
    }

    @objc private func changeQuality(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let quality = VoiceQuality(rawValue: raw) else { return }
        ModelManager.shared.selectedQuality = quality
        ModelManager.shared.ensureLoaded(quality)
        refreshQualityMenu()
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Scribe needs Accessibility permission to monitor the Fn key.

            1. Open System Settings → Privacy & Security → Accessibility
            2. Add Scribe and toggle it on
            3. Return to this app — it will retry automatically
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
