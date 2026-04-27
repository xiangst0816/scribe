import AppKit
import Speech
import Sparkle

public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let appleProvider = AppleSpeechProvider()
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()

    private var isEnabled = true
    private var isRecording = false
    private var isTranscribing = false

    /// Trailing audio captured after FN release. Users often let go a beat
    /// before they finish their sentence; this preserves those last words.
    private static let trailingBufferSeconds: TimeInterval = 0.5
    private var pendingStop: DispatchWorkItem?

    private var enableMenuItem: NSMenuItem!
    private var langMenuItem: NSMenuItem!
    private var systemDefaultLangItem: NSMenuItem!
    private var quitMenuItem: NSMenuItem!
    private var languageItems: [NSMenuItem] = []

    private var selectedLocaleCode: String {
        get { UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLocaleCode") }
    }

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let savedCode = selectedLocaleCode
        if !savedCode.isEmpty {
            appleProvider.locale = Locale(identifier: savedCode)
        }
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
    }

    // MARK: - Key events

    private func fnDown() {
        // Re-pressing FN while a trailing-buffer stop is pending means the user
        // wasn't done — cancel the pending stop and keep the same recording.
        if let pending = pendingStop {
            pending.cancel()
            pendingStop = nil
            return
        }

        guard isEnabled, !isRecording, !isTranscribing else { return }

        isRecording = true
        updateStatusIcon()
        overlayPanel.show()
        NSSound(named: .init("Tink"))?.play()

        appleProvider.start()
    }

    private func fnUp() {
        guard isRecording, pendingStop == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStop = nil
            self.isRecording = false
            self.isTranscribing = true
            self.updateStatusIcon()
            self.overlayPanel.showLoading()
            self.appleProvider.stop()
        }
        pendingStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trailingBufferSeconds, execute: work)
    }

    // MARK: - Provider callbacks

    private func setupProviderCallbacks() {
        appleProvider.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }
        appleProvider.onPartialResult = { [weak self] text in
            self?.overlayPanel.updatePartialTranscript(text)
        }
        appleProvider.onError = { [weak self] msg in
            guard let self else { return }
            self.isRecording = false
            self.isTranscribing = false
            self.updateStatusIcon()
            NSLog("Scribe overlay error: %@", msg)
            self.overlayPanel.dismiss()
        }
        appleProvider.onFinalResult = { [weak self] text in
            self?.deliverFinal(text)
        }
        appleProvider.onLocaleUnavailable = { [weak self] msg in
            self?.showAlert(title: L10n.t("alert.languageUnavailable"), message: msg)
        }
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

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()

        enableMenuItem = NSMenuItem(title: L10n.t("menu.enabled"), action: #selector(toggleEnabled), keyEquivalent: "")
        enableMenuItem.target = self
        enableMenuItem.state = .on
        menu.addItem(enableMenuItem)

        menu.addItem(.separator())

        // Language submenu — controls the SFSpeechRecognizer locale.
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

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "Scribe v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        quitMenuItem = NSMenuItem(title: L10n.t("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    /// Re-apply current localization to all static menu titles.
    private func relocalizeStaticMenu() {
        enableMenuItem?.title = L10n.t("menu.enabled")
        langMenuItem?.title = L10n.t("menu.language")
        quitMenuItem?.title = L10n.t("menu.quit")
        systemDefaultLangItem?.title = L10n.t("menu.systemDefault")
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil  // always inherit menu-bar foreground
        button.title = ""

        let symbolName: String
        let description: String
        if isTranscribing {
            symbolName = "waveform"
            description = "Transcribing"
        } else {
            symbolName = "mic.fill"
            description = "Voice Input"
        }
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
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
            pendingStop?.cancel()
            pendingStop = nil
            if isRecording {
                appleProvider.cancel()
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

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }

        L10n.setLanguage(localeCode: code)
        relocalizeStaticMenu()
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
