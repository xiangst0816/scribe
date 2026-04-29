import AppKit

/// Settings panel for the transcript polishing feature. One master toggle plus
/// two backend radios (System / Local). The unavailable backend is greyed out
/// with a status string explaining why.
///
/// For the Local backend, this window also drives the model download:
/// pre-download the button reads "Download…", mid-download it shows a progress
/// label and "Cancel", and on failure it offers "Retry" / "Delete model file".
final class SettingsWindow: NSPanel {
    private let coordinator: PolishCoordinator

    private let enableCheckbox = NSButton()
    private let systemRadio = NSButton()
    private let localRadio = NSButton()
    private let systemStatusLabel = NSTextField(labelWithString: "")
    private let localStatusLabel = NSTextField(labelWithString: "")
    private let localPrimaryButton = NSButton()       // Download / Cancel / Retry
    private let localSecondaryButton = NSButton()     // Delete model file (when applicable)
    private let mirrorPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mirrorLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(labelWithString: "")
    private let engineHeader = NSTextField(labelWithString: "")
    private let systemDetailLabel = NSTextField(labelWithString: "")
    private let localDetailLabel = NSTextField(labelWithString: "")

    private var observer: NSObjectProtocol?

    init(coordinator: PolishCoordinator) {
        self.coordinator = coordinator
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        title = L10n.t("settings.title")
        isReleasedWhenClosed = false
        setupUI()
        refresh()
        center()

        observer = NotificationCenter.default.addObserver(
            forName: .polishAvailabilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - UI

    private func setupUI() {
        guard let cv = contentView else { return }

        enableCheckbox.setButtonType(.switch)
        enableCheckbox.title = L10n.t("settings.polish.enable")
        enableCheckbox.target = self
        enableCheckbox.action = #selector(enableToggled)

        descriptionLabel.stringValue = L10n.t("settings.polish.description")
        descriptionLabel.font = .systemFont(ofSize: 11)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.maximumNumberOfLines = 0
        descriptionLabel.preferredMaxLayoutWidth = 480

        engineHeader.stringValue = L10n.t("settings.polish.engine")
        engineHeader.font = .boldSystemFont(ofSize: 12)

        systemRadio.setButtonType(.radio)
        systemRadio.title = L10n.t("settings.polish.system.label")
        systemRadio.target = self
        systemRadio.action = #selector(backendChanged(_:))
        systemRadio.tag = 0

        localRadio.setButtonType(.radio)
        localRadio.title = L10n.t("settings.polish.local.label")
        localRadio.target = self
        localRadio.action = #selector(backendChanged(_:))
        localRadio.tag = 1

        systemDetailLabel.stringValue = L10n.t("settings.polish.system.detail")
        systemDetailLabel.font = .systemFont(ofSize: 11)
        systemDetailLabel.textColor = .secondaryLabelColor

        localDetailLabel.stringValue = L10n.t("settings.polish.local.detail")
        localDetailLabel.font = .systemFont(ofSize: 11)
        localDetailLabel.textColor = .secondaryLabelColor

        for label in [systemStatusLabel, localStatusLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .tertiaryLabelColor
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 0
            label.preferredMaxLayoutWidth = 460
        }

        localPrimaryButton.bezelStyle = .rounded
        localPrimaryButton.target = self
        localPrimaryButton.action = #selector(localPrimaryTapped)

        localSecondaryButton.bezelStyle = .rounded
        localSecondaryButton.title = L10n.t("settings.polish.delete")
        localSecondaryButton.target = self
        localSecondaryButton.action = #selector(localPurgeTapped)
        localSecondaryButton.isHidden = true

        mirrorLabel.stringValue = L10n.t("settings.polish.mirror")
        mirrorLabel.font = .systemFont(ofSize: 11)

        mirrorPopUp.target = self
        mirrorPopUp.action = #selector(mirrorChanged(_:))
        mirrorPopUp.addItem(withTitle: L10n.t("settings.polish.mirror.auto"))
        mirrorPopUp.lastItem?.representedObject = ModelMirrorPreference.auto.rawValue
        for m in ModelMirror.allCases {
            mirrorPopUp.addItem(withTitle: m.displayName)
            mirrorPopUp.lastItem?.representedObject = ModelMirrorPreference(rawValue: m.rawValue)?.rawValue ?? "auto"
        }

        let doneButton = NSButton(title: L10n.t("settings.polish.done"), target: self, action: #selector(closeWindow))
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"

        // Vertical stack with manual indentation for the radio rows.
        let systemBlock = NSStackView(views: [systemRadio, systemDetailLabel, systemStatusLabel])
        systemBlock.orientation = .vertical
        systemBlock.alignment = .leading
        systemBlock.spacing = 4
        systemBlock.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)

        let localButtonRow = NSStackView(views: [localPrimaryButton, localSecondaryButton])
        localButtonRow.orientation = .horizontal
        localButtonRow.alignment = .firstBaseline
        localButtonRow.spacing = 8

        let mirrorRow = NSStackView(views: [mirrorLabel, mirrorPopUp])
        mirrorRow.orientation = .horizontal
        mirrorRow.alignment = .firstBaseline
        mirrorRow.spacing = 8

        let localBlock = NSStackView(views: [localRadio, localDetailLabel, localStatusLabel, localButtonRow, mirrorRow])
        localBlock.orientation = .vertical
        localBlock.alignment = .leading
        localBlock.spacing = 4
        localBlock.edgeInsets = NSEdgeInsets(top: 0, left: 18, bottom: 0, right: 0)

        let main = NSStackView(views: [
            enableCheckbox,
            descriptionLabel,
            engineHeader,
            systemBlock,
            localBlock,
        ])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 12
        main.translatesAutoresizingMaskIntoConstraints = false

        let bottomBar = NSStackView(views: [doneButton])
        bottomBar.orientation = .horizontal
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        cv.addSubview(main)
        cv.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: cv.topAnchor, constant: 20),
            main.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            main.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),

            bottomBar.topAnchor.constraint(greaterThanOrEqualTo: main.bottomAnchor, constant: 16),
            bottomBar.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
            bottomBar.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - Refresh from coordinator

    private func refresh() {
        enableCheckbox.state = coordinator.isEnabled ? .on : .off

        // Status under each radio — reflects backend.statusText verbatim.
        systemStatusLabel.stringValue = L10n.t("settings.polish.statusPrefix") + coordinator.system.statusText
        localStatusLabel.stringValue = L10n.t("settings.polish.statusPrefix") + coordinator.local.statusText

        // Radio selection always tracks `selectedBackend`, even if that backend
        // is currently unavailable — the status under the radio explains why.
        systemRadio.state = coordinator.selectedBackend == .system ? .on : .off
        localRadio.state = coordinator.selectedBackend == .local ? .on : .off

        // Grey out an unavailable backend so the user can see it but not pick it.
        // Local radio remains selectable even pre-download — the user might
        // want to switch the *preference* before triggering the download.
        systemRadio.isEnabled = coordinator.system.isReady
        localRadio.isEnabled = true

        // Mirror dropdown — show current preference.
        let prefRaw = coordinator.mirrorPreference.rawValue
        if let idx = mirrorPopUp.itemArray.firstIndex(where: { ($0.representedObject as? String) == prefRaw }) {
            mirrorPopUp.selectItem(at: idx)
        }

        configureLocalButtons()
    }

    /// Set the Local backend's primary/secondary buttons based on the current
    /// download state. The primary button is the affordance the user is most
    /// likely to want next.
    private func configureLocalButtons() {
        let local = coordinator.local as? LocalPolishService
        guard let state = local?.downloadState else {
            localPrimaryButton.isHidden = true
            localSecondaryButton.isHidden = true
            return
        }
        localPrimaryButton.isHidden = false
        switch state {
        case .notDownloaded:
            localPrimaryButton.title = L10n.t("settings.polish.download")
            localPrimaryButton.tag = ButtonAction.download.rawValue
            localSecondaryButton.isHidden = true
        case .downloading:
            localPrimaryButton.title = L10n.t("settings.polish.cancel")
            localPrimaryButton.tag = ButtonAction.cancel.rawValue
            localSecondaryButton.isHidden = true
        case .verifying:
            localPrimaryButton.title = L10n.t("settings.polish.cancel")
            localPrimaryButton.tag = ButtonAction.cancel.rawValue
            localSecondaryButton.isHidden = true
        case .ready:
            localPrimaryButton.isHidden = true
            localSecondaryButton.isHidden = false
        case .downloadFailed(_, let retriable):
            localPrimaryButton.title = retriable ? L10n.t("settings.polish.download") : L10n.t("settings.polish.delete")
            localPrimaryButton.tag = (retriable ? ButtonAction.download : ButtonAction.purge).rawValue
            localSecondaryButton.isHidden = true
        case .loadFailed:
            localPrimaryButton.title = L10n.t("settings.polish.delete")
            localPrimaryButton.tag = ButtonAction.purge.rawValue
            localSecondaryButton.isHidden = true
        }
    }

    private enum ButtonAction: Int {
        case download = 0
        case cancel = 1
        case purge = 2
    }

    // MARK: - Actions

    @objc private func enableToggled() {
        coordinator.isEnabled = (enableCheckbox.state == .on)
    }

    @objc private func backendChanged(_ sender: NSButton) {
        let newBackend: PolishBackend = (sender.tag == 0) ? .system : .local
        coordinator.selectedBackend = newBackend
        refresh()
    }

    @objc private func mirrorChanged(_ sender: NSPopUpButton) {
        let raw = (sender.selectedItem?.representedObject as? String) ?? "auto"
        if let pref = ModelMirrorPreference(rawValue: raw) {
            coordinator.mirrorPreference = pref
        }
    }

    @objc private func localPrimaryTapped() {
        switch ButtonAction(rawValue: localPrimaryButton.tag) ?? .download {
        case .download: coordinator.startLocalDownload()
        case .cancel:   coordinator.cancelLocalDownload()
        case .purge:    coordinator.purgeLocalModel()
        }
    }

    @objc private func localPurgeTapped() {
        coordinator.purgeLocalModel()
    }

    @objc private func closeWindow() {
        close()
    }
}
