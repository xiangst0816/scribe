import AppKit
import Speech
import Sparkle

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public override init() { super.init() }

    private var statusItem: NSStatusItem!
    private let keyMonitor = KeyMonitor()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private let textInjector = TextInjector()
    private lazy var overlayPanel = OverlayPanel()
    private let polishCoordinator = PolishCoordinator.shared
    private var settingsWindow: SettingsWindow?
    private var polishStatusMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var lastPolishWasSkipped = false

    /// Single source of truth for the recording lifecycle. All transitions go
    /// through `fnDown`, `fnUp`, `handleTermination`, or `cleanupAfterPolish`
    /// — no flag juggling.
    private enum SessionState {
        case idle
        case recording(session: AppleSpeechSession)
        case armedToStop(session: AppleSpeechSession, work: DispatchWorkItem)
        case transcribing(session: AppleSpeechSession)
        /// Speech is done; the polish pipeline is running and the loading
        /// overlay is still up. Fn is locked out (fnDown's `.idle` guard
        /// rejects). Lasts ~0.5–5 s, ends in `cleanupAfterPolish`.
        case polishing
    }

    private var sessionState: SessionState = .idle
    private var isEnabled = true

    /// Held while `.polishing` so the user can't kick off a second polish on
    /// top of an in-flight one, and so `resetSession` can cancel cleanly.
    private var polishTask: Task<Void, Never>?

    /// Trailing audio captured after FN release. Users often let go a beat
    /// before they finish their sentence; this preserves those last words.
    private static let trailingBufferSeconds: TimeInterval = 0.5

    /// Per-frame delay for the menu-bar recording animation. 4 frames × 0.4s
    /// ≈ 1.6s loop — feels alive without buzzing.
    private static let recordingFrameInterval: TimeInterval = 0.4

    private var menubarIdleImage: NSImage?
    private var menubarRecordingFrames: [NSImage] = []
    private var recordingAnimationTimer: Timer?
    private var recordingFrameIndex = 0

    private var enableMenuItem: NSMenuItem!
    private var langMenuItem: NSMenuItem!
    private var systemDefaultLangItem: NSMenuItem!
    private var micMenuItem: NSMenuItem!
    private var micSubmenu: NSMenu!
    private var quitMenuItem: NSMenuItem!
    private var languageItems: [NSMenuItem] = []

    private var selectedLocaleCode: String {
        get { UserDefaults.standard.string(forKey: "selectedLocaleCode") ?? "zh-CN" }
        set { UserDefaults.standard.set(newValue, forKey: "selectedLocaleCode") }
    }

    private var currentLocale: Locale {
        let code = selectedLocaleCode
        return code.isEmpty ? .current : Locale(identifier: code)
    }

    // MARK: - Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.setLanguage(localeCode: selectedLocaleCode)

        // Drop the deprecated remote-LLM keys before the new polish UI reads
        // anything. Safe even when no old keys are present.
        PolishCoordinator.purgeLegacyKeys()

        polishCoordinator.refreshAvailability()
        polishCoordinator.prewarmIfNeeded()
        polishCoordinator.onBreakerTripped = { [weak self] message in
            self?.showAlert(
                title: L10n.t("alert.polishBreakerTitle"),
                message: L10n.t("alert.polishBreakerBody") + "\n\n\(message)"
            )
            self?.refreshPolishMenuItem()
        }
        NotificationCenter.default.addObserver(
            forName: .polishAvailabilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Posted on .main, but the closure is Sendable so we hop through
            // assumeIsolated to access main-actor state synchronously.
            MainActor.assumeIsolated {
                self?.refreshPolishMenuItem()
            }
        }

        setupStatusBar()

        AppleSpeechSession.requestPermissions { [weak self] granted, errorMsg in
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
        // Also re-query Apple Intelligence availability — toggling it in
        // System Settings should reflect without a Scribe relaunch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isEnabled { _ = self.keyMonitor.start() }
                self.polishCoordinator.refreshAvailability()
            }
        }
    }

    /// Drain anything llama.cpp / Metal-related before NSApplication runs
    /// `exit()`. Without this, the C++ static destructor of ggml's global
    /// device vector races against a background pipeline-compile dispatch
    /// block and trips `ggml_abort` → SIGABRT (the crash users saw on Cmd-Q
    /// in v0.3.3).
    public func applicationWillTerminate(_ notification: Notification) {
        keyMonitor.stop()
        if let local = polishCoordinator.local as? LocalPolishService {
            local.releaseContextForShutdown()
        }
        LlamaContext.tearDownProcessBackend()
    }

    // MARK: - Key events

    private func fnDown() {
        // Re-pressing FN during the trailing-buffer window means the user
        // wasn't done — keep the same session running.
        if case let .armedToStop(session, work) = sessionState {
            work.cancel()
            sessionState = .recording(session: session)
            return
        }

        guard isEnabled, case .idle = sessionState else { return }

        let session = AppleSpeechSession(locale: currentLocale)
        session.onAudioLevel = { [weak self] level in
            self?.overlayPanel.updateAudioLevel(level)
        }
        session.onPartial = { [weak self] text in
            self?.overlayPanel.updatePartialTranscript(text)
        }
        session.onTerminated = { [weak self] reason in
            self?.handleTermination(reason)
        }

        sessionState = .recording(session: session)
        updateStatusIcon()
        overlayPanel.show()
        NSSound(named: .init("Tink"))?.play()
        session.start()
    }

    private func fnUp() {
        guard case let .recording(session) = sessionState else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard case let .armedToStop(session, _) = self.sessionState else { return }
            self.sessionState = .transcribing(session: session)
            self.updateStatusIcon()
            self.overlayPanel.showLoading()
            session.stop()
        }
        sessionState = .armedToStop(session: session, work: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trailingBufferSeconds, execute: work)
    }

    // MARK: - Session termination

    private func handleTermination(_ reason: AppleSpeechSession.Termination) {
        switch reason {
        case .final(let text):
            // Move to .polishing (NOT .idle) so Fn is locked out while polish
            // runs and the loading overlay stays visible. cleanupAfterPolish
            // moves us back to .idle when the paste finishes.
            sessionState = .polishing
            updateStatusIcon()
            deliverFinal(text)
        case .cancelled:
            sessionState = .idle
            updateStatusIcon()
            overlayPanel.dismiss()
        case .error(let message):
            sessionState = .idle
            updateStatusIcon()
            NSLog("Scribe speech error: %@", message)
            overlayPanel.dismiss()
        }
    }

    private func deliverFinal(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            overlayPanel.dismiss()
            sessionState = .idle
            updateStatusIcon()
            return
        }

        // Polish via the coordinator; on any failure or master-toggle-off this
        // returns the input unchanged. The 0.1s nudge before injection lets
        // the previous `cancel()` settle so cmd-V isn't intercepted mid-state.
        // We hold the task in `polishTask` so `resetSession` can cancel it.
        polishTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let beforeFailures = self.polishCoordinator.consecutiveFailures
            let polished = await self.polishCoordinator.maybePolish(
                trimmed,
                selectedLocaleCode: self.selectedLocaleCode
            )
            self.lastPolishWasSkipped = (self.polishCoordinator.consecutiveFailures > beforeFailures)
            self.refreshPolishMenuItem()

            // If we got cancelled (user disabled Scribe / app quitting),
            // skip the paste — pasting after the user's gesture is gone is
            // worse than dropping the polish.
            guard !Task.isCancelled else {
                self.cleanupAfterPolish()
                return
            }

            try? await Task.sleep(nanoseconds: 100_000_000)  // settle
            guard !Task.isCancelled else {
                self.cleanupAfterPolish()
                return
            }
            self.textInjector.paste(polished)
            NSSound(named: .init("Pop"))?.play()
            self.cleanupAfterPolish(dismissOverlay: true)
        }
    }

    /// Always called once at the end of the polish flow — returns the state
    /// machine to `.idle`, refreshes the menu-bar icon, and (by default)
    /// dismisses the loading overlay. Pass `dismissOverlay: false` when the
    /// caller has just installed a self-managing overlay state (e.g. the
    /// "copied to clipboard" notice). Idempotent so repeated calls are safe.
    private func cleanupAfterPolish(dismissOverlay: Bool = true) {
        polishTask = nil
        if dismissOverlay {
            overlayPanel.dismiss()
        }
        sessionState = .idle
        updateStatusIcon()
    }

    private func resetSession() {
        switch sessionState {
        case .idle:
            return
        case .recording(let session), .transcribing(let session):
            session.cancel()
        case .armedToStop(let session, let work):
            work.cancel()
            session.cancel()
        case .polishing:
            polishTask?.cancel()
            cleanupAfterPolish()
        }
        // session.cancel() triggers onTerminated → handleTermination,
        // which moves the state machine back to .idle and updates UI.
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        loadMenubarImages()
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

        // Microphone submenu — chooses which input device the recognizer reads
        // from. Items are rebuilt on `menuNeedsUpdate(_:)` so freshly-plugged
        // devices appear without relaunch.
        micMenuItem = NSMenuItem(title: L10n.t("menu.microphone"), action: nil, keyEquivalent: "")
        micSubmenu = NSMenu(title: L10n.t("menu.microphone"))
        micSubmenu.delegate = self
        rebuildMicrophoneSubmenu()
        micMenuItem.submenu = micSubmenu
        menu.addItem(micMenuItem)

        menu.addItem(.separator())

        // Polish status (read-only; clicking opens the Settings window).
        polishStatusMenuItem = NSMenuItem(title: "", action: #selector(openScribeSettings), keyEquivalent: "")
        polishStatusMenuItem.target = self
        menu.addItem(polishStatusMenuItem)

        settingsMenuItem = NSMenuItem(title: L10n.t("menu.settings"), action: #selector(openScribeSettings), keyEquivalent: ",")
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)

        refreshPolishMenuItem()

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

        quitMenuItem = NSMenuItem(title: quitMenuItemTitle(), action: #selector(quit), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    /// Re-apply current localization to all static menu titles.
    private func relocalizeStaticMenu() {
        enableMenuItem?.title = L10n.t("menu.enabled")
        langMenuItem?.title = L10n.t("menu.language")
        micMenuItem?.title = L10n.t("menu.microphone")
        quitMenuItem?.title = quitMenuItemTitle()
        systemDefaultLangItem?.title = L10n.t("menu.systemDefault")
        settingsMenuItem?.title = L10n.t("menu.settings")
        rebuildMicrophoneSubmenu()
        refreshPolishMenuItem()
    }

    /// Title for the Quit menu item, with the bundle version appended in
    /// parens. Putting the version here instead of on the "Enabled" row
    /// avoids fighting AppKit's title / keyEquivalent column layout — the
    /// version becomes part of the title text and AppKit measures the menu
    /// width naturally.
    private func quitMenuItemTitle() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "\(L10n.t("menu.quit")) (v\(version))"
    }

    // MARK: - Microphone submenu

    private func rebuildMicrophoneSubmenu() {
        guard let micSubmenu else { return }
        micSubmenu.removeAllItems()
        let pref = MicrophoneRouter.shared.preference

        let autoItem = NSMenuItem(
            title: L10n.t("menu.mic.auto"),
            action: #selector(selectMicAuto),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.state = (pref == .auto) ? .on : .off
        micSubmenu.addItem(autoItem)

        let sysItem = NSMenuItem(
            title: L10n.t("menu.systemDefault"),
            action: #selector(selectMicSystemDefault),
            keyEquivalent: ""
        )
        sysItem.target = self
        sysItem.state = (pref == .systemDefault) ? .on : .off
        micSubmenu.addItem(sysItem)

        let devices = MicrophoneRouter.inputDevices()
        if !devices.isEmpty {
            micSubmenu.addItem(.separator())
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectMicSpecific(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                if case .specific(let uid) = pref, uid == device.uid {
                    item.state = .on
                }
                micSubmenu.addItem(item)
            }
        }
    }

    /// AppKit calls this right before the submenu is displayed. Re-enumerate
    /// devices so freshly-plugged hardware shows up without a relaunch.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === micSubmenu {
            rebuildMicrophoneSubmenu()
        }
    }

    /// Update the "Polish: <state>" menu item based on coordinator state.
    ///
    /// Branch order is load-bearing (R4):
    ///   breaker > master-off > timeout-warning > ready > hard-skip > unavailable
    /// Specifically, `lastCallTimedOut` MUST be checked before `active()` —
    /// timeouts don't trip the breaker, so the backend stays ready, so the
    /// `ready` branch would otherwise shadow the timeout signal forever and
    /// the user would never learn polish was silently falling back to raw.
    private func refreshPolishMenuItem() {
        guard let item = polishStatusMenuItem else { return }
        let key: String
        if polishCoordinator.isBreakerTripped {
            key = "menu.polish.breakerTripped"
        } else if !polishCoordinator.isEnabled {
            key = "menu.polish.off"
        } else if polishCoordinator.lastCallTimedOut {
            key = "menu.polish.skippedTimeout"
        } else if let svc = polishCoordinator.active() {
            key = svc.backend == .system ? "menu.polish.readySystem" : "menu.polish.readyLocal"
        } else if lastPolishWasSkipped {
            key = "menu.polish.skipped"
        } else {
            key = "menu.polish.unavailable"
        }
        item.title = L10n.t(key)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil  // always inherit menu-bar foreground
        button.title = ""

        switch sessionState {
        case .recording, .armedToStop:
            startRecordingAnimation()
        case .idle, .transcribing, .polishing:
            stopRecordingAnimation()
            button.image = menubarIdleImage
        }
    }

    private func loadMenubarImages() {
        // NSImage(named:) finds @1x and @2x reps for files in the bundle's
        // Resources directory and combines them into one image. Falls back to
        // an SF Symbol if the bundled assets are missing — the app should
        // never end up with an invisible status item.
        //
        // We force size to 18×18 pt so the icon visually matches Apple's
        // built-in status-bar items (Battery, Wi-Fi, Volume). The PNGs ship at
        // 22/44 px so macOS still has enough resolution to downscale cleanly.
        let menubarIconSize = NSSize(width: 18, height: 18)

        let idle = NSImage(named: "MenubarIdle")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Voice Input")
        idle?.isTemplate = true
        idle?.size = menubarIconSize
        menubarIdleImage = idle

        menubarRecordingFrames = (1...4).compactMap { i in
            let img = NSImage(named: "MenubarRecording\(i)")
            img?.isTemplate = true
            img?.size = menubarIconSize
            return img
        }
    }

    private func startRecordingAnimation() {
        // Idempotent: state transitions recording → armedToStop also call
        // updateStatusIcon, but the animation should run continuously across
        // both. Bail if the timer is already ticking.
        if recordingAnimationTimer != nil { return }
        guard !menubarRecordingFrames.isEmpty else {
            statusItem.button?.image = menubarIdleImage
            return
        }
        recordingFrameIndex = 0
        statusItem.button?.image = menubarRecordingFrames[0]
        let timer = Timer.scheduledTimer(
            timeInterval: Self.recordingFrameInterval,
            target: self,
            selector: #selector(advanceRecordingFrame),
            userInfo: nil,
            repeats: true
        )
        // Without .common mode, the animation freezes whenever the menu-bar
        // menu is open (NSMenu pushes the run loop into .eventTracking).
        RunLoop.main.add(timer, forMode: .common)
        recordingAnimationTimer = timer
    }

    private func stopRecordingAnimation() {
        recordingAnimationTimer?.invalidate()
        recordingAnimationTimer = nil
        recordingFrameIndex = 0
    }

    @objc private func advanceRecordingFrame() {
        guard !menubarRecordingFrames.isEmpty else { return }
        recordingFrameIndex = (recordingFrameIndex + 1) % menubarRecordingFrames.count
        statusItem.button?.image = menubarRecordingFrames[recordingFrameIndex]
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
            resetSession()
        }
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        selectedLocaleCode = code

        for item in languageItems {
            item.state = (item.representedObject as? String) == code ? .on : .off
        }

        L10n.setLanguage(localeCode: code)
        relocalizeStaticMenu()

        let target = code.isEmpty ? Locale.current : Locale(identifier: code)
        if !AppleSpeechSession.isLocaleSupported(target) {
            showAlert(
                title: L10n.t("alert.languageUnavailable"),
                message: "Speech recognition is not supported for \(target.identifier). Confirm the language is downloaded in System Settings → General → Keyboard → Dictation."
            )
        }
    }

    @objc private func selectMicAuto() {
        MicrophoneRouter.shared.preference = .auto
        rebuildMicrophoneSubmenu()
    }

    @objc private func selectMicSystemDefault() {
        MicrophoneRouter.shared.preference = .systemDefault
        rebuildMicrophoneSubmenu()
    }

    @objc private func selectMicSpecific(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        MicrophoneRouter.shared.preference = .specific(uid: uid)
        rebuildMicrophoneSubmenu()
    }

    @objc private func quit() {
        keyMonitor.stop()
        NSApp.terminate(nil)
    }

    @objc private func openScribeSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow(coordinator: polishCoordinator)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
