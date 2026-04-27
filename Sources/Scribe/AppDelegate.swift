import AppKit
import Speech
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
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
    private var langMenuItem: NSMenuItem!
    private var systemDefaultLangItem: NSMenuItem!
    private var qualityMenuItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
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
        L10n.setLanguage(localeCode: savedCode)

        setupStatusBar()
        setupProviderCallbacks()

        AppleSpeechProvider.requestPermissions { [weak self] granted, errorMsg in
            if !granted, let msg = errorMsg {
                self?.showAlert(title: L10n.t("alert.permissionRequired"), message: msg)
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
            self?.showAlert(title: L10n.t("alert.languageUnavailable"), message: msg)
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

        enableMenuItem = NSMenuItem(title: L10n.t("menu.enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        // Language submenu (Apple Speech fallback only)
        langMenuItem = NSMenuItem(title: L10n.t("menu.language"), action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        // (display title, locale code, isSystemDefault)
        let languages: [(String, String, Bool)] = [
            (L10n.t("menu.systemDefault"), "",      true),
            ("English (US)",               "en-US", false),
            ("中文 (简体)",                "zh-CN", false),
            ("中文 (繁體)",                "zh-TW", false),
            ("日本語",                     "ja-JP", false),
            ("한국어",                     "ko-KR", false),
        ]
        for (name, code, isSystem) in languages {
            let item = NSMenuItem(title: name, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == selectedLocaleCode ? .on : .off
            languageItems.append(item)
            if isSystem { systemDefaultLangItem = item }
            langMenu.addItem(item)
        }
        langMenuItem.submenu = langMenu
        menu.addItem(langMenuItem)

        // Voice Quality submenu
        qualityMenuItem = NSMenuItem(title: L10n.t("menu.voiceQuality"), action: nil, keyEquivalent: "")
        let qualityMenu = NSMenu()
        for q in VoiceQuality.allCases {
            let item = NSMenuItem(title: "", action: #selector(changeQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = q.rawValue
            qualityItems[q] = item
            qualityMenu.addItem(item)
        }
        qualityMenuItem.submenu = qualityMenu
        menu.addItem(qualityMenuItem)

        menu.addItem(.separator())

        // Manual update check — Sparkle also runs an automatic background check
        // once a day per Info.plist (SUScheduledCheckInterval / SUEnableAutomaticChecks).
        let updateItem = NSMenuItem(
            title: L10n.t("menu.checkForUpdates"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)

        menu.addItem(.separator())

        quitMenuItem = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

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

        let detail: String
        switch state {
        case .notDownloaded:
            detail = L10n.t("status.notDownloaded")
        case .downloading(let p):
            detail = String(format: L10n.t("status.downloadingFallback"), Int(p * 100))
        case .downloaded:
            detail = L10n.t("status.ready")
        case .loading(let elapsed):
            detail = elapsed > 0
                ? String(format: L10n.t("status.loadingModelElapsed"), elapsed)
                : L10n.t("status.loadingModel")
        case .ready:
            detail = L10n.t("status.active")
        case .failed(let msg):
            detail = String(format: L10n.t("status.failedRetrySuffix"), msg)
        }
        item.title = "\(q.displayName) · \(detail)"
    }

    private func formatQualityRow(_ q: VoiceQuality, state: ModelState) -> String {
        let suffix: String
        switch state {
        case .notDownloaded:      suffix = "  ·  \(q.sizeLabel)  ·  \(L10n.t("quality.suffix.download"))"
        case .downloading(let p): suffix = "  ·  " + String(format: L10n.t("quality.suffix.downloading"), Int(p * 100))
        case .downloaded:         suffix = "  ·  \(q.sizeLabel)  ·  \(L10n.t("quality.suffix.ready"))"
        case .loading(let elapsed):
            suffix = elapsed > 0
                ? "  ·  " + String(format: L10n.t("quality.suffix.loadingElapsed"), elapsed)
                : "  ·  \(L10n.t("quality.suffix.loading"))"
        case .ready:              suffix = "  ·  \(q.sizeLabel)  ·  \(L10n.t("quality.suffix.inUse"))"
        case .failed:             suffix = "  ·  \(q.sizeLabel)  ·  \(L10n.t("quality.suffix.failed"))"
        }
        return q.displayName + suffix
    }

    /// Re-apply current localization to all static menu titles. Quality rows
    /// and the status info line are refreshed via `refreshQualityMenu()`.
    private func relocalizeStaticMenu() {
        enableMenuItem?.title = L10n.t("menu.enabled")
        langMenuItem?.title = L10n.t("menu.language")
        qualityMenuItem?.title = L10n.t("menu.voiceQuality")
        quitMenuItem?.title = L10n.t("menu.quit")
        systemDefaultLangItem?.title = L10n.t("menu.systemDefault")
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

        if isRecording {
            // Keep the mascot logo while recording — the macOS orange mic
            // privacy indicator already signals that the mic is hot.
            button.image = Self.idleLogoImage
        } else if isTranscribing {
            let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Transcribing")
            img?.isTemplate = true
            button.image = img
        } else {
            button.image = Self.idleLogoImage
        }
    }

    /// Mickey-style silhouette of the Scribe mascot — head (r=7) plus two
    /// round ears (r=4) sitting symmetrically on top. Drawn as a single merged
    /// path traversing the outer outline of the three-circle union.
    /// Intersection points are precomputed analytically so the elliptical arc
    /// commands stitch cleanly. No mask/clip — works with the limited SVG
    /// support in NSImage's renderer.
    private static let idleLogoImage: NSImage = {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 22 22">
          <path fill="none" stroke="black" stroke-width="1.6"
                stroke-linejoin="round" stroke-linecap="round"
                d="M 4.94 9.498
                   A 4 4 0 1 1 8.915 6.318
                   A 7 7 0 0 1 13.085 6.318
                   A 4 4 0 1 1 17.06 9.498
                   A 7 7 0 1 1 4.94 9.498 Z"/>
        </svg>
        """
        let data = svg.data(using: .utf8)!
        let img = NSImage(data: data) ?? NSImage()
        img.size = NSSize(width: 18, height: 18)
        img.isTemplate = true
        img.accessibilityDescription = "Voice Input"
        return img
    }()

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

        L10n.setLanguage(localeCode: code)
        relocalizeStaticMenu()
        refreshQualityMenu()
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
        alert.messageText = L10n.t("alert.accessibilityTitle")
        alert.informativeText = L10n.t("alert.accessibilityBody")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("alert.openSystemSettings"))
        alert.addButton(withTitle: L10n.t("alert.later"))

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
        alert.addButton(withTitle: L10n.t("alert.ok"))
        alert.runModal()
    }
}
