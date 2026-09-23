import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum LaunchAtLogin {
    struct State {
        let isSelected: Bool
        let errorMessage: String?
    }

    static var state: State {
        switch SMAppService.mainApp.status {
        case .enabled:
            return State(isSelected: true, errorMessage: nil)
        case .requiresApproval:
            return State(isSelected: true, errorMessage: nil)
        case .notFound:
            return State(isSelected: false, errorMessage: nil)
        case .notRegistered:
            return State(isSelected: false, errorMessage: nil)
        @unknown default:
            return State(isSelected: false, errorMessage: "自動起動の状態を確認できません")
        }
    }

    static func setEnabled(_ enabled: Bool) -> State {
        let service = SMAppService.mainApp
        do {
            if enabled {
                switch service.status {
                case .enabled, .requiresApproval:
                    break
                case .notFound:
                    // A development build can replace the entire .app bundle,
                    // leaving macOS with a stale login-item registration.
                    // Clear it when possible, then register the current bundle.
                    try? service.unregister()
                    try service.register()
                case .notRegistered:
                    try service.register()
                @unknown default:
                    try service.register()
                }
            } else if service.status != .notRegistered {
                try service.unregister()
            }
            return state
        } catch {
            return State(
                isSelected: state.isSelected,
                errorMessage: "変更できませんでした: \(error.localizedDescription)"
            )
        }
    }
}

@MainActor
final class CandidatePanel: NSPanel {
    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let queryLabel = NSTextField(labelWithString: "")
    private(set) var candidates: [EmojiEntry] = []
    private(set) var selectedIndex = 0
    var onSelection: ((EmojiEntry) -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        backgroundColor = .windowBackgroundColor
        configureTable()
    }

    private func configureTable() {
        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("emoji")))
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        queryLabel.font = .systemFont(ofSize: 13)
        queryLabel.textColor = .secondaryLabelColor
        contentView?.addSubview(queryLabel)
        contentView?.addSubview(scrollView)
        queryLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            queryLabel.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 12),
            queryLabel.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -12),
            queryLabel.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 8),
            queryLabel.heightAnchor.constraint(equalToConstant: 24),
            scrollView.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: queryLabel.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor)
        ])
    }

    func update(query: String, candidates: [EmojiEntry], searching: Bool = false,
                providerName: String = "Jev", showPanel: Bool = true) {
        queryLabel.stringValue = searching
            ? ":\(query) · \(providerName)で検索中…"
            : ":\(query)"
        self.candidates = candidates
        selectedIndex = 0
        tableView.reloadData()
        if !candidates.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        if showPanel {
            if !isVisible { orderFrontRegardless() }
        } else {
            orderOut(nil)
        }
    }

    func showError(_ message: String) {
        queryLabel.stringValue = message
    }

    func moveSelection(_ delta: Int) {
        guard !candidates.isEmpty else { return }
        selectedIndex = max(0, min(candidates.count - 1, selectedIndex + delta))
        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        tableView.scrollRowToVisible(selectedIndex)
    }

    func selectCurrent() {
        guard candidates.indices.contains(selectedIndex) else { return }
        onSelection?(candidates[selectedIndex])
    }

}

extension CandidatePanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { candidates.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: "\(candidates[row].emoji)   \(candidates[row].name)")
        label.font = .systemFont(ofSize: 16)
        label.frame = NSRect(x: 12, y: 4, width: 330, height: 24)
        cell.addSubview(label)
        return cell
    }
}

@MainActor
final class APIKeyInputView: NSView {
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 4, width: 290, height: 24))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let pasteButton = NSButton(title: "ペースト", target: self, action: #selector(pasteFromClipboard))
        pasteButton.frame = NSRect(x: 300, y: 1, width: 82, height: 30)
        addSubview(field)
        addSubview(pasteButton)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func pasteFromClipboard() {
        guard let copiedKey = NSPasteboard.general.string(forType: .string) else { return }
        field.stringValue = copiedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        window?.makeFirstResponder(field)
    }
}

@MainActor
final class SettingsPanel: NSPanel, NSWindowDelegate {
    private let apiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(
        checkboxWithTitle: "Macにログインしたときに自動で起動",
        target: nil,
        action: nil
    )
    private let providerName: String
    var onSave: ((String) -> Bool)?
    var onSetLaunchAtLogin: ((Bool) -> LaunchAtLogin.State)?
    var onClose: (() -> Void)?

    init(providerName: String) {
        self.providerName = providerName
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 230),
                   styleMask: [.titled, .closable], backing: .buffered, defer: true)
        title = "Emojichao 設定"
        isReleasedWhenClosed = false
        delegate = self
        setupView()
    }

    private func setupView() {
        guard let root = contentView else { return }
        let heading = NSTextField(labelWithString: "\(providerName) APIキー")
        heading.font = .systemFont(ofSize: 15, weight: .semibold)
        apiKeyField.placeholderString = "\(providerName) APIキー"
        let saveButton = NSButton(title: "保存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        let separator = NSBox()
        separator.boxType = .separator
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        for view in [heading, apiKeyField, saveButton, statusLabel, separator,
                     launchAtLoginCheckbox] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 25),
            apiKeyField.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            apiKeyField.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            apiKeyField.heightAnchor.constraint(equalToConstant: 28),
            statusLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: apiKeyField.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: apiKeyField.trailingAnchor),
            separator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 18),
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            saveButton.trailingAnchor.constraint(equalTo: apiKeyField.trailingAnchor),
            saveButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
    }

    func show(apiKey: String?, launchAtLoginState: LaunchAtLogin.State) {
        apiKeyField.stringValue = apiKey ?? ""
        statusLabel.stringValue = apiKey == nil ? "APIキーを入力してください" : "APIキーは設定済みです"
        applyLaunchAtLoginState(launchAtLoginState)
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        makeFirstResponder(apiKeyField)
    }

    @objc private func save() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            statusLabel.stringValue = "APIキーを入力してください"
            statusLabel.textColor = .systemRed
            return
        }
        let saved = onSave?(key) ?? false
        statusLabel.stringValue = saved ? "保存しました" : "保存できませんでした"
        statusLabel.textColor = saved ? .systemGreen : .systemRed
    }

    @objc private func toggleLaunchAtLogin() {
        let requested = launchAtLoginCheckbox.state == .on
        let state = onSetLaunchAtLogin?(requested) ?? LaunchAtLogin.state
        applyLaunchAtLoginState(state)
    }

    private func applyLaunchAtLoginState(_ state: LaunchAtLogin.State) {
        launchAtLoginCheckbox.state = state.isSelected ? .on : .off
        if let errorMessage = state.errorMessage {
            let alert = NSAlert()
            alert.messageText = "自動起動の設定を変更できませんでした"
            alert.informativeText = errorMessage
            alert.beginSheetModal(for: self)
        }
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor
final class PermissionDragIconView: NSImageView, NSDraggingSource {
    private var dragStart: NSPoint?

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let current = event.locationInWindow
        guard hypot(current.x - dragStart.x, current.y - dragStart.y) > 4 else { return }
        self.dragStart = nil

        let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
}

@MainActor
final class PermissionDragPanel: NSPanel {
    private let iconView = PermissionDragIconView()

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 210),
                   styleMask: [.titled, .closable, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        title = "EmojiShortcutを追加"
        isFloatingPanel = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        let label = NSTextField(labelWithString: "システム設定の「入力監視」にアイコンをドラッグ&ドロップしてください")
        label.alignment = .center
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.frame = NSRect(x: 24, y: 135, width: 312, height: 54)
        iconView.image = NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.frame = NSRect(x: 150, y: 42, width: 60, height: 60)
        iconView.toolTip = "Emojichaoをドラッグ"
        contentView?.addSubview(label)
        contentView?.addSubview(iconView)
    }

    func showNearSettings() {
        let frame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame
        if let frame {
            setFrameOrigin(NSPoint(x: frame.midX - self.frame.width / 2,
                                   y: frame.midY - self.frame.height / 2))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

}

@MainActor
final class PermissionCheckboxView: NSView {
    var isChecked = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3)
        (isChecked ? NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.96, alpha: 0.10)
                   : NSColor(calibratedWhite: 0.96, alpha: 1)).setFill()
        path.fill()
        guard isChecked else { return }
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 4, y: 8))
        check.line(to: NSPoint(x: 7, y: 5))
        check.line(to: NSPoint(x: 13, y: 12))
        check.lineWidth = 2
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(calibratedRed: 0.48, green: 0.38, blue: 0.96, alpha: 1).setStroke()
        check.stroke()
    }
}

@MainActor
final class PermissionSetupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    private let accessibilityCheck = PermissionCheckboxView()
    private let inputMonitoringCheck = PermissionCheckboxView()
    private let accessibilityStatus = NSTextField(labelWithString: "")
    private let inputMonitoringStatus = NSTextField(labelWithString: "")
    private let eventPostingStatus = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let continueButton = NSButton(title: "許可状態を再確認", target: nil, action: nil)
    var onOpenAccessibility: (() -> Void)?
    var onOpenInputMonitoring: (() -> Void)?
    var onContinue: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 489, height: 240),
                   styleMask: [.borderless], backing: .buffered, defer: true)
        title = ""
        isReleasedWhenClosed = false
        level = .floating
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        setupView()
    }

    private func setupView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.white.cgColor
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        contentView = root
        let accessibilityButton = NSButton(title: "", target: self, action: #selector(openAccessibility))
        let inputButton = NSButton(title: "", target: self, action: #selector(openInputMonitoring))
        for button in [accessibilityButton, inputButton] {
            button.isBordered = false
            button.setButtonType(.momentaryChange)
        }
        accessibilityStatus.font = .systemFont(ofSize: 18, weight: .regular)
        inputMonitoringStatus.font = .systemFont(ofSize: 18, weight: .regular)
        eventPostingStatus.isHidden = true
        progressLabel.isHidden = true
        continueButton.isHidden = true
        let accessibilityDescription = NSTextField(labelWithString: "入力された文字を読み取るために必要です")
        let inputDescription = NSTextField(labelWithString: "「:」が入力されたことを検知するために必要です")
        for description in [accessibilityDescription, inputDescription] {
            description.font = .systemFont(ofSize: 14)
            description.textColor = NSColor(calibratedWhite: 0.55, alpha: 1)
        }
        for view in [accessibilityCheck, inputMonitoringCheck, accessibilityStatus, inputMonitoringStatus, accessibilityDescription, inputDescription,
                     eventPostingStatus, accessibilityButton, inputButton, progressLabel, continueButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            accessibilityCheck.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 48), accessibilityCheck.topAnchor.constraint(equalTo: root.topAnchor, constant: 48), accessibilityCheck.widthAnchor.constraint(equalToConstant: 16), accessibilityCheck.heightAnchor.constraint(equalToConstant: 16),
            accessibilityStatus.leadingAnchor.constraint(equalTo: accessibilityCheck.trailingAnchor, constant: 12), accessibilityStatus.topAnchor.constraint(equalTo: root.topAnchor, constant: 42), accessibilityStatus.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -48), accessibilityStatus.heightAnchor.constraint(equalToConstant: 26),
            accessibilityDescription.leadingAnchor.constraint(equalTo: accessibilityStatus.leadingAnchor), accessibilityDescription.topAnchor.constraint(equalTo: accessibilityStatus.bottomAnchor, constant: 4),
            accessibilityButton.leadingAnchor.constraint(equalTo: root.leadingAnchor), accessibilityButton.trailingAnchor.constraint(equalTo: root.trailingAnchor), accessibilityButton.topAnchor.constraint(equalTo: root.topAnchor), accessibilityButton.bottomAnchor.constraint(equalTo: accessibilityDescription.bottomAnchor, constant: 12),
            inputMonitoringCheck.leadingAnchor.constraint(equalTo: accessibilityCheck.leadingAnchor), inputMonitoringCheck.topAnchor.constraint(equalTo: accessibilityDescription.bottomAnchor, constant: 36), inputMonitoringCheck.widthAnchor.constraint(equalToConstant: 16), inputMonitoringCheck.heightAnchor.constraint(equalToConstant: 16),
            inputMonitoringStatus.leadingAnchor.constraint(equalTo: accessibilityStatus.leadingAnchor), inputMonitoringStatus.centerYAnchor.constraint(equalTo: inputMonitoringCheck.centerYAnchor), inputMonitoringStatus.trailingAnchor.constraint(equalTo: accessibilityStatus.trailingAnchor), inputMonitoringStatus.heightAnchor.constraint(equalToConstant: 26),
            inputDescription.leadingAnchor.constraint(equalTo: inputMonitoringStatus.leadingAnchor), inputDescription.topAnchor.constraint(equalTo: inputMonitoringStatus.bottomAnchor, constant: 4),
            inputButton.leadingAnchor.constraint(equalTo: root.leadingAnchor), inputButton.trailingAnchor.constraint(equalTo: root.trailingAnchor), inputButton.topAnchor.constraint(equalTo: inputMonitoringStatus.topAnchor, constant: -8), inputButton.bottomAnchor.constraint(equalTo: inputDescription.bottomAnchor, constant: 8)
        ])
    }

    private func configureStatus(_ label: NSTextField) { label.font = .systemFont(ofSize: 14) }
    func refresh() {
        let accessibilityAllowed = AXIsProcessTrusted()
        let inputAllowed = CGPreflightListenEventAccess()
        accessibilityCheck.isChecked = accessibilityAllowed
        inputMonitoringCheck.isChecked = inputAllowed
        accessibilityStatus.stringValue = "アクセシビリティの制御を許可"
        inputMonitoringStatus.stringValue = "入力監視の制御を許可"
        accessibilityStatus.font = .systemFont(ofSize: 18, weight: accessibilityAllowed ? .bold : .regular)
        inputMonitoringStatus.font = .systemFont(ofSize: 18, weight: inputAllowed ? .bold : .regular)
        accessibilityStatus.textColor = .labelColor
        inputMonitoringStatus.textColor = .labelColor
    }
    func show() {
        refresh()
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
    @objc private func openAccessibility() { onOpenAccessibility?() }
    @objc private func openInputMonitoring() { onOpenInputMonitoring?() }
    @objc private func continuePressed() { refresh(); onContinue?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct AutoAppliedSelection {
        let shortcut: String
        let candidates: [EmojiEntry]
        let appliedEmoji: String
        let target: AXUIElement?
        let targetApplication: NSRunningApplication?
    }

    private struct PendingTextSearchResume {
        let selection: AutoAppliedSelection
        var shortcut: String
        var revision: Int
    }

    private var statusItem: NSStatusItem!
    private let panel = CandidatePanel()
    private let toastPanel = ToastPanel()
    private let catalog = EmojiCatalog.shared
    private let jev = JevClient()
    private var searchCache: [String: [EmojiEntry]] = [:]
    private var shownToastIDs: Set<String> = []
    private var eventTap: CFMachPort?
    private var activeShortcut: String?
    private var shortcutTarget: AXUIElement?
    private var shortcutTargetApplication: NSRunningApplication?
    private var shortcutContext: String?
    private var contextCaptureGeneration = 0
    private var isPerformingKeyboardReplacement = false
    private var isCommittingComposition = false
    private var pendingKanaRestore = false
    private var isBlockingKeyboardInput = false
    private var keyboardReplacementGeneration = 0
    private var lastTypedCharacter: Character?
    private var autoAppliedSelection: AutoAppliedSelection?
    private var choosingAutoApplied: AutoAppliedSelection?
    private var pendingTextSearchResume: PendingTextSearchResume?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var isSearchPending = false
    private var jevPacer = SearchRequestPacer(
        minimumInterval: 0.5,
        cooldownUntil: UserDefaults.standard.object(forKey: "JevRateLimitCooldownUntil") as? Date
    )
    private var isConfiguringAPIKey = false
    private var accessibilityMenuItem: NSMenuItem!
    private var inputMonitoringMenuItem: NSMenuItem!
    private var eventPostingMenuItem: NSMenuItem!
    private var monitorMenuItem: NSMenuItem!
    private var apiKeyMenuItem: NSMenuItem!
    private var contextSearchModeMenuItem: NSMenuItem?
    private var textSearchModeMenuItem: NSMenuItem?
    private var permissionMenuItems: [NSMenuItem] = []
    private lazy var permissionDragPanel = PermissionDragPanel()
    private lazy var permissionSetupPanel = PermissionSetupPanel()
    private lazy var settingsPanel = SettingsPanel(providerName: "Jev")
    private var permissionSetupTimer: DispatchSourceTimer?
    private var didStartInputMonitoringStep = false
    private var didOpenAccessibilitySettingsForSetup = false
    private var systemSettingsLaunchObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configureStatusItemButton()
        let menu = NSMenu()
        menu.delegate = self
        apiKeyMenuItem = NSMenuItem(title: "Jev APIキーを設定…", action: #selector(setAPIKey), keyEquivalent: "")
        apiKeyMenuItem.target = self
        let settingsItem = NSMenuItem(title: "設定…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let searchModeHeader = NSMenuItem(title: "絵文字の選び方", action: nil, keyEquivalent: "")
        searchModeHeader.isEnabled = false
        let headerView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let headerLabel = NSTextField(labelWithString: "絵文字の選び方")
        headerLabel.frame = NSRect(x: 8, y: 3, width: 250, height: 18)
        headerLabel.font = .menuFont(ofSize: 0)
        headerLabel.textColor = .secondaryLabelColor
        headerView.addSubview(headerLabel)
        searchModeHeader.view = headerView
        menu.addItem(searchModeHeader)
        let contextItem = NSMenuItem(
            title: "文脈を判断して絵文字を自動選択",
            action: #selector(selectContextSearchMode),
            keyEquivalent: ""
        )
        contextItem.target = self
        contextItem.indentationLevel = 1
        contextSearchModeMenuItem = contextItem
        menu.addItem(contextItem)
        let textItem = NSMenuItem(
            title: "テキストを入力して絵文字を検索",
            action: #selector(selectTextSearchMode),
            keyEquivalent: ""
        )
        textItem.target = self
        textItem.indentationLevel = 1
        textSearchModeMenuItem = textItem
        menu.addItem(textItem)
        refreshSearchModeMenu()
        menu.addItem(.separator())
        menu.addItem(apiKeyMenuItem)
        menu.addItem(settingsItem)
        let permissionSeparator = NSMenuItem.separator()
        menu.addItem(permissionSeparator)
        let permissionsHeader = NSMenuItem(title: "権限と動作状況", action: nil, keyEquivalent: "")
        permissionsHeader.isEnabled = false
        menu.addItem(permissionsHeader)
        accessibilityMenuItem = NSMenuItem(title: "アクセシビリティ: 確認中…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityMenuItem.target = self
        menu.addItem(accessibilityMenuItem)
        inputMonitoringMenuItem = NSMenuItem(title: "入力監視: 確認中…", action: #selector(openInputMonitoringSettings), keyEquivalent: "")
        inputMonitoringMenuItem.target = self
        menu.addItem(inputMonitoringMenuItem)
        eventPostingMenuItem = NSMenuItem(title: "キー送信: 確認中…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        eventPostingMenuItem.target = self
        menu.addItem(eventPostingMenuItem)
        monitorMenuItem = NSMenuItem(title: "監視: 確認中…", action: nil, keyEquivalent: "")
        monitorMenuItem.isEnabled = false
        menu.addItem(monitorMenuItem)
        let retryItem = NSMenuItem(title: "許可後に監視を再開", action: #selector(retryMonitor), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)
        let requestPermissionItem = NSMenuItem(title: "未許可の権限を要求", action: #selector(requestMissingPermission), keyEquivalent: "")
        requestPermissionItem.target = self
        menu.addItem(requestPermissionItem)
        let setupItem = NSMenuItem(title: "権限セットアップを開く…", action: #selector(showPermissionSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)
        let revealAppItem = NSMenuItem(title: "このアプリをFinderで表示", action: #selector(revealCurrentApp), keyEquivalent: "")
        revealAppItem.target = self
        menu.addItem(revealAppItem)
        let copyAppFolderItem = NSMenuItem(title: "アプリのフォルダをコピー", action: #selector(copyCurrentAppFolder), keyEquivalent: "")
        copyAppFolderItem.target = self
        menu.addItem(copyAppFolderItem)
        permissionMenuItems = [
            permissionSeparator, permissionsHeader, accessibilityMenuItem,
            inputMonitoringMenuItem, eventPostingMenuItem, monitorMenuItem,
            retryItem, requestPermissionItem, setupItem, revealAppItem,
            copyAppFolderItem
        ]
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        panel.onSelection = { [weak self] entry in self?.replaceShortcut(with: entry) }
        panel.onCancel = { [weak self] in self?.cancelShortcut() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lastTypedCharacter = nil
                self?.cancelShortcut()
            }
        }
        permissionSetupPanel.onOpenAccessibility = { [weak self] in self?.requestAccessibilityFromSetup() }
        permissionSetupPanel.onOpenInputMonitoring = { [weak self] in self?.requestInputMonitoringFromSetup() }
        permissionSetupPanel.onContinue = { [weak self] in self?.handlePermissionSetupContinue() }
        settingsPanel.onSave = { [weak self] key in self?.saveAPIKey(key) ?? false }
        settingsPanel.onSetLaunchAtLogin = { enabled in LaunchAtLogin.setEnabled(enabled) }
        settingsPanel.onClose = { [weak self] in self?.isConfiguringAPIKey = false }
        if UserDefaults.standard.bool(forKey: "PermissionSetupGuideV3Completed"),
           AXIsProcessTrusted(), CGPreflightListenEventAccess() {
            NSApp.setActivationPolicy(.accessory)
            installMonitor(requestPermissions: false)
        } else {
            presentPermissionSetupIfNeeded()
        }
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        let displaySize = NSSize(width: 18, height: 18)
        let image = NSImage(size: displaySize)
        var addedRepresentation = false

        for resourceName in ["MenuBarIcon", "MenuBarIcon@2x"] {
            let url = Bundle.module.url(
                forResource: resourceName,
                withExtension: "png",
                subdirectory: "Icons"
            ) ?? Bundle.module.url(forResource: resourceName, withExtension: "png")
            guard let url, let loadedImage = NSImage(contentsOf: url) else { continue }
            for representation in loadedImage.representations {
                representation.size = displaySize
                image.addRepresentation(representation)
                addedRepresentation = true
            }
        }

        guard addedRepresentation else {
            button.title = "🙂"
            return
        }
        image.isTemplate = true
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
    }

    private func presentPermissionSetupIfNeeded() {
        let guideCompleted = UserDefaults.standard.bool(forKey: "PermissionSetupGuideV3Completed")
        guard !guideCompleted || !AXIsProcessTrusted() || !CGPreflightListenEventAccess() else {
            return
        }
        // Let the menu bar item finish appearing before showing the first-run guide.
        DispatchQueue.main.async { [weak self] in
            self?.runPermissionSetup()
        }
    }

    private func runPermissionSetup() {
        NSApp.setActivationPolicy(.regular)
        didOpenAccessibilitySettingsForSetup = false
        permissionSetupPanel.show()
        didStartInputMonitoringStep = false
        permissionSetupTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100), leeway: .milliseconds(10))
        timer.setEventHandler { [weak self] in self?.advancePermissionSetup() }
        permissionSetupTimer = timer
        timer.resume()
        activatePermissionGuide(attempt: 0)
    }

    private func activatePermissionGuide(attempt: Int) {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        permissionSetupPanel.makeKeyAndOrderFront(nil)
        permissionSetupPanel.orderFrontRegardless()
        if NSApp.isActive && permissionSetupPanel.isKeyWindow {
            if !didOpenAccessibilitySettingsForSetup {
                didOpenAccessibilitySettingsForSetup = true
                permissionSetupPanel.displayIfNeeded()
                openPrivacySettings("Privacy_Accessibility")
            }
            return
        }
        guard attempt < 30 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.activatePermissionGuide(attempt: attempt + 1)
        }
    }

    private func advancePermissionSetup() {
        permissionSetupPanel.refresh()
        guard AXIsProcessTrusted() else { return }

        if !didStartInputMonitoringStep {
            didStartInputMonitoringStep = true
            permissionSetupPanel.refresh()
            permissionSetupPanel.displayIfNeeded()
            permissionDragPanel.showNearSettings()
            // Open Settings last. NSWorkspace then owns activation, while both
            // onboarding panels remain visible without stealing focus back.
            openPrivacySettings("Privacy_ListenEvent")
        }

        guard CGPreflightListenEventAccess() else { return }
        completePermissionSetup()
    }

    private func completePermissionSetup() {
        permissionSetupTimer?.cancel()
        permissionSetupTimer = nil
        permissionDragPanel.orderOut(nil)
        permissionSetupPanel.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.set(true, forKey: "PermissionSetupCompleted")
        UserDefaults.standard.set(true, forKey: "PermissionSetupGuideV3Completed")
        installMonitor(requestPermissions: false)
        refreshPermissionMenu()
        presentAPIKeySetupIfNeeded()
    }

    private func presentAPIKeySetupIfNeeded() {
        guard KeychainStore.read(for: .jev) == nil, !isConfiguringAPIKey else { return }

        // Wait until the permission panels have closed before activating the
        // existing API-key window as the next onboarding step.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  KeychainStore.read(for: .jev) == nil,
                  !self.isConfiguringAPIKey else { return }
            self.openSettings()
        }
    }

    private func requestAccessibilityFromSetup() {
        openAccessibilitySettings()
    }

    private func requestInputMonitoringFromSetup() {
        guard !CGPreflightListenEventAccess() else { openInputMonitoringSettings(); return }
        _ = CGRequestListenEventAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.openInputMonitoringSettings() }
    }

    @objc private func showPermissionSetup() {
        runPermissionSetup()
        refreshPermissionMenu()
    }

    private func handlePermissionSetupContinue() {
        permissionSetupPanel.refresh()
        if AXIsProcessTrusted() && CGPreflightListenEventAccess() {
            completePermissionSetup()
        }
    }

    private func beginPermissionStep(_ index: Int) {
        guard index < 3 else {
            UserDefaults.standard.set(true, forKey: "PermissionSetupCompleted")
            installMonitor(requestPermissions: false)
            refreshPermissionMenu()
            return
        }
        let allowed: () -> Bool
        let request: () -> Void
        let openSettings: () -> Void
        switch index {
        case 0:
            allowed = { AXIsProcessTrusted() }
            request = { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) }
            openSettings = { self.openAccessibilitySettings() }
        case 1:
            allowed = { CGPreflightListenEventAccess() }
            request = { _ = CGRequestListenEventAccess() }
            openSettings = { self.openInputMonitoringSettings() }
        default:
            allowed = { CGPreflightPostEventAccess() }
            request = { _ = CGRequestPostEventAccess() }
            openSettings = { self.openAccessibilitySettings() }
        }
        guard !allowed() else { beginPermissionStep(index + 1); return }
        request()
        pollPermission(allowed: allowed, index: index, openSettings: openSettings, attempts: 0)
    }

    private func pollPermission(allowed: @escaping () -> Bool, index: Int,
                                openSettings: @escaping () -> Void, attempts: Int) {
        guard !allowed() else { beginPermissionStep(index + 1); return }
        // Accessibility is added by macOS's native prompt. The drag helper is
        // only useful for Input Monitoring, where the user may need to add the
        // app to the list manually.
        if attempts == 2 && index == 1 { openSettings() }
        guard attempts < 120 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.pollPermission(allowed: allowed, index: index,
                                 openSettings: openSettings, attempts: attempts + 1)
        }
    }

    private func refreshPermissionMenu() {
        apiKeyMenuItem.isHidden = KeychainStore.read(for: .jev) != nil
        refreshSearchModeMenu()
        accessibilityMenuItem.title = permissionTitle("アクセシビリティ", allowed: AXIsProcessTrusted())
        inputMonitoringMenuItem.title = permissionTitle("入力監視", allowed: CGPreflightListenEventAccess())
        eventPostingMenuItem.title = permissionTitle("キー送信", allowed: CGPreflightPostEventAccess())
        let running = eventTap.map { CFMachPortIsValid($0) && CGEvent.tapIsEnabled(tap: $0) } ?? false
        monitorMenuItem.title = running ? "監視: ✅ 動作中" : "監視: ⚠️ 停止中"
        let hasProblem = !AXIsProcessTrusted()
            || !CGPreflightListenEventAccess()
            || !CGPreflightPostEventAccess()
            || !running
        permissionMenuItems.forEach { $0.isHidden = !hasProblem }
    }

    private func permissionTitle(_ name: String, allowed: Bool) -> String {
        "\(name): \(allowed ? "✅ 許可済み" : "⚠️ 未許可")  → 設定を開く"
    }

    @objc private func openAccessibilitySettings() {
        openPrivacySettings("Privacy_Accessibility")
    }

    @objc private func openInputMonitoringSettings() {
        openPrivacySettings("Privacy_ListenEvent")
        permissionDragPanel.showNearSettings()
    }

    private func openPrivacySettings(_ section: String) {
        prepareToActivateSystemSettings()
        let address = "x-apple.systempreferences:com.apple.preference.security?\(section)"
        if let url = URL(string: address), NSWorkspace.shared.open(url) {
            activateSystemSettingsIfRunning()
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(fallback)
            activateSystemSettingsIfRunning()
        }
    }

    private func prepareToActivateSystemSettings() {
        if let observer = systemSettingsLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        systemSettingsLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  application.bundleIdentifier == "com.apple.systempreferences" else { return }
            Task { @MainActor in
                application.unhide()
                application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                if let observer = self?.systemSettingsLaunchObserver {
                    NSWorkspace.shared.notificationCenter.removeObserver(observer)
                    self?.systemSettingsLaunchObserver = nil
                }
            }
        }
    }

    private func activateSystemSettingsIfRunning() {
        guard let settings = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences"
        ).first else { return }
        settings.unhide()
        settings.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let observer = systemSettingsLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            systemSettingsLaunchObserver = nil
        }
    }

    @objc private func requestMissingPermission() {
        if !AXIsProcessTrusted() {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        } else if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        } else {
            installMonitor(requestPermissions: false)
        }
        refreshPermissionMenu()
    }

    @objc private func revealCurrentApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    @objc private func copyCurrentAppFolder() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Bundle.main.bundleURL.deletingLastPathComponent().path, forType: .string)
    }

    @objc private func selectContextSearchMode() {
        setSearchMode(.context)
    }

    @objc private func selectTextSearchMode() {
        setSearchMode(.text)
    }

    private func setSearchMode(_ mode: JevSearchMode) {
        guard JevSettings.searchMode() != mode else { return }
        JevSettings.setSearchMode(mode)
        refreshSearchModeMenu()
        searchCache.removeAll()
        cancelShortcut()
    }

    private func refreshSearchModeMenu() {
        let mode = JevSettings.searchMode()
        contextSearchModeMenuItem?.state = mode == .context ? .on : .off
        textSearchModeMenuItem?.state = mode == .text ? .on : .off
    }

    @objc private func retryMonitor() {
        guard AXIsProcessTrusted(), CGPreflightListenEventAccess(), CGPreflightPostEventAccess() else {
            let alert = NSAlert()
            alert.messageText = "権限がまだ揃っていません"
            alert.informativeText = "メニューバーアイコンから未許可の項目を押して、設定を確認してください。"
            alert.runModal()
            return
        }
        installMonitor(requestPermissions: false)
        refreshPermissionMenu()
    }

    @objc private func setAPIKey() {
        openSettings()
    }

    @objc private func openSettings() {
        isConfiguringAPIKey = true
        settingsPanel.show(
            apiKey: KeychainStore.read(for: .jev),
            launchAtLoginState: LaunchAtLogin.state
        )
    }

    private func saveAPIKey(_ key: String) -> Bool {
        let saved = KeychainStore.save(key, for: .jev)
        if saved {
            searchCache.removeAll()
            jevPacer = SearchRequestPacer(minimumInterval: 0.5)
            UserDefaults.standard.removeObject(forKey: "JevRateLimitCooldownUntil")
            shownToastIDs.removeAll()
            toastPanel.orderOut(nil)
            apiKeyMenuItem.isHidden = true
        }
        return saved
    }

    private func installMonitor(requestPermissions: Bool = true) {
        NSLog(
            "Emojichao permission state: accessibility=%@ inputMonitoring=%@ eventPosting=%@",
            AXIsProcessTrusted() ? "yes" : "no",
            CGPreflightListenEventAccess() ? "yes" : "no",
            CGPreflightPostEventAccess() ? "yes" : "no"
        )
        if let eventTap, CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }
        eventTap = nil
        if requestPermissions {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                NSLog("Emojichao requires Accessibility permission to replace text in other apps.")
            }
            if !CGPreflightListenEventAccess() {
                NSLog("Emojichao requires Input Monitoring permission to observe keyboard events.")
                CGRequestListenEventAccess()
            }
            if !CGPreflightPostEventAccess() {
                NSLog("Emojichao requires permission to post replacement events.")
                CGRequestPostEventAccess()
            }
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        )
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        guard let eventTap else {
            NSLog("Unable to create keyboard event tap. Check Accessibility permission.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disables the tap when TCC permission is revoked. Do not
            // fight that state by immediately re-enabling it; doing so can
            // make WindowServer/TCC unstable while the user changes settings.
            if AXIsProcessTrusted(), CGPreflightListenEventAccess(), CGPreflightPostEventAccess() {
                if let tap = delegate.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if let tap = delegate.eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            MainActor.assumeIsolated { delegate.cancelShortcut() }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeyboardReplacement.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }
        let keyCode = nsEvent.keyCode
        let characters = nsEvent.characters ?? ""
        let modifiers = nsEvent.modifierFlags
        let consumed = MainActor.assumeIsolated {
            delegate.handle(keyCode: keyCode, characters: characters, modifiers: modifiers)
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func handle(keyCode: UInt16, characters chars: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        if isBlockingKeyboardInput {
            if var pending = pendingTextSearchResume,
               let resume = EmojiSearchPolicy.textSearchResume(
                   shortcut: pending.shortcut, characters: chars
               ) {
                pending.shortcut = resume.shortcut
                pending.revision += 1
                pendingTextSearchResume = pending
            }
            // Do not let another key overwrite the text while it is selected
            // for clipboard verification. The operation completes quickly.
            return true
        }
        // Ignore keys typed into our own settings, but keep the global
        // shortcut active when that window is left open behind another app.
        if isConfiguringAPIKey,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == getpid() {
            return false
        }
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            lastTypedCharacter = nil
            autoAppliedSelection = nil
            choosingAutoApplied = nil
            cancelShortcut()
            return false
        }
        if activeShortcut == nil, let autoAppliedSelection {
            if keyCode == kVK_DownArrow {
                let selection = autoAppliedSelection
                self.autoAppliedSelection = nil
                choosingAutoApplied = selection
                panel.update(
                    query: String(selection.shortcut.dropFirst()),
                    candidates: selection.candidates,
                    providerName: "Jev"
                )
                panel.moveSelection(1)
                return true
            }
            if keyCode == kVK_Escape {
                self.autoAppliedSelection = nil
                postUndo()
                return true
            }
            if resumeTextSearch(from: autoAppliedSelection, characters: chars) { return true }
            self.autoAppliedSelection = nil
            // The character before the caret is now the inserted emoji, so a
            // ':' typed next may open a new shortcut.
            lastTypedCharacter = nil
        }
        if let selection = choosingAutoApplied {
            if keyCode == kVK_Escape {
                choosingAutoApplied = nil
                panel.orderOut(nil)
                postUndo()
                return true
            }
            if keyCode == kVK_UpArrow { panel.moveSelection(-1); return true }
            if keyCode == kVK_DownArrow { panel.moveSelection(1); return true }
            if keyCode == kVK_Return || keyCode == kVK_Tab {
                guard panel.candidates.indices.contains(panel.selectedIndex) else { return true }
                replaceAutoApplied(selection, with: panel.candidates[panel.selectedIndex])
                return true
            }
            if resumeTextSearch(from: selection, characters: chars) {
                choosingAutoApplied = nil
                return true
            }
            choosingAutoApplied = nil
            panel.orderOut(nil)
        }
        if let shortcut = activeShortcut {
            if keyCode == kVK_Escape { cancelShortcut(); return true }
            if keyCode == kVK_UpArrow { panel.moveSelection(-1); return true }
            if keyCode == kVK_DownArrow { panel.moveSelection(1); return true }
            if keyCode == kVK_Return || keyCode == kVK_Tab {
                switch EmojiSearchPolicy.selectionAction(
                    candidateCount: panel.candidates.count, searchPending: isSearchPending
                ) {
                case .select:
                    panel.selectCurrent()
                    return true
                case .waitForSearch:
                    panel.showError("Jevで検索中…少し待ってください")
                    return true
                case .passThrough:
                    cancelShortcut()
                    return false
                }
            }
            if keyCode == kVK_Delete {
                if shortcut.count <= 1 {
                    // The deleted character was the trigger itself. Do not
                    // let it remain as the previous character, otherwise a
                    // newly typed ':' is mistaken for an invalid adjacent
                    // trigger and never opens the panel.
                    lastTypedCharacter = nil
                    cancelShortcut()
                }
                else {
                    activeShortcut = String(shortcut.dropLast())
                    updateCandidates()
                }
                return false
            }
            if chars == ":" || chars == "：" || chars.contains(" ") || chars.contains("\n") {
                cancelShortcut(); return false
            }
            guard chars.count == 1, shortcut.count < 50 else { cancelShortcut(); return false }
            activeShortcut = shortcut + chars
            lastTypedCharacter = chars.last
            updateCandidates()
            return false
        }

        guard !chars.isEmpty else { return false }
        guard chars == ":" || chars == "：" else {
            lastTypedCharacter = chars.last
            return false
        }
        guard previousCharacterAllowsTrigger() else { return false }
        activeShortcut = chars
        shortcutTarget = ShortcutReplacement.focusedElement()
        shortcutTargetApplication = NSWorkspace.shared.frontmostApplication
        let shouldReadContext = JevSettings.searchMode() == .context
        shortcutContext = nil
        lastTypedCharacter = chars.last
        panel.setFrameOrigin(NSEvent.mouseLocation)
        if shouldReadContext {
            contextCaptureGeneration += 1
            let generation = contextCaptureGeneration
            let target = shortcutTarget
            Task { [weak self] in
                // Let ':' reach the editor first so a Japanese IME can commit
                // its marked text before AX is queried.
                try? await Task.sleep(for: .milliseconds(50))
                guard let self,
                      self.contextCaptureGeneration == generation,
                      self.activeShortcut == chars else { return }
                self.shortcutContext = ShortcutReplacement.contextBeforeTrigger(
                    in: target, trigger: chars
                )
                self.updateCandidates()
            }
        } else {
            updateCandidates()
        }
        return false
    }

    private func previousCharacterAllowsTrigger() -> Bool {
        guard let previous = lastTypedCharacter else { return true }
        return previous == " " || previous == "\u{3000}" || previous == "\n" || previous == "\r"
    }

    private func updateCandidates() {
        guard let shortcut = activeShortcut else { return }
        searchGeneration += 1
        let currentGeneration = searchGeneration
        searchTask?.cancel()
        isSearchPending = false
        let query = String(shortcut.dropFirst())
        let searchMode = JevSettings.searchMode()
        let requestedContextMode = searchMode == .context
        // Context mode only owns the bare ':' trigger. A typed query should
        // always become a normal text search. When the editor does not expose
        // nearby text through Accessibility, fall back to text search instead
        // of selecting text with synthetic keys, which can swallow typing.
        let isContextMode = EmojiSearchPolicy.usesContextSearch(
            requested: requestedContextMode,
            query: query,
            hasContext: shortcutContext != nil
        )
        let remoteQuery = isContextMode ? "" : query
        let context = isContextMode ? shortcutContext : nil
        let cacheKey = JevClient.cacheKey(query: remoteQuery, context: context)
        let local = isContextMode ? [] : catalog.localMatches(query)
        let key = KeychainStore.read(for: .jev)
        let maySearch = EmojiSearchPolicy.shouldSearchRemote(remoteQuery, hasContext: context != nil)
        let shouldSearch = maySearch && key != nil
        // When Jev is available, do not put literal local matches in front of
        // the semantic result. For example, "goodnight" can make 🥱 appear
        // before Jev has had a chance to interpret "いいね〜:good".
        let initialCandidates = shouldSearch ? [] : local
        panel.update(
            query: query,
            candidates: initialCandidates,
            searching: shouldSearch,
            providerName: "Jev",
            showPanel: EmojiSearchPolicy.shouldShowPanel(
                query: query, isContextMode: isContextMode
            )
        )
        // Only a Jev result may be applied without the user choosing it. Local
        // matches always wait for Enter, so ':' keeps the session open for the
        // search text instead of inserting an emoji on its own.
        if requestedContextMode && query.isEmpty && key != nil && shortcutContext == nil {
            panel.showError(": · 文脈を読み取れない入力欄ではテキスト検索に切り替えます")
        } else if query.count >= 2 && key == nil {
            panel.showError("Jev APIキー未設定 · メニューバーアイコンから設定")
            showMissingAPIKeyToast()
        }
        guard shouldSearch, let key else { return }
        if let cached = searchCache[cacheKey] {
            panel.update(query: query, candidates: cached)
            panel.showError(":\(query) · Jevの候補")
            if EmojiSearchPolicy.shouldAutoApplyFirstCandidate(
                isContextMode: isContextMode, candidateCount: cached.count
            ) {
                autoApplyFirstCandidate(cached)
            }
            return
        }
        isSearchPending = true
        searchTask = Task { [weak self] in
            // Jev can use the already-captured context immediately. Keep a
            // short debounce for typing a query, but make the context-only
            // ':' flow respond in real time.
            let delayMilliseconds = remoteQuery.isEmpty ? 0 : 200
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
            guard !Task.isCancelled, let self else { return }
            do {
                let wait = jevPacer.waitDuration(at: Date())
                if wait > 0 {
                    try await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, searchGeneration == currentGeneration else { return }
                }
                jevPacer.recordAttempt(at: Date())
                let ranked = try await jev.rank(
                    query: remoteQuery,
                    context: context,
                    entries: catalog.searchableEntries,
                    apiKey: key
                )
                jevPacer.recordSuccess()
                UserDefaults.standard.removeObject(forKey: "JevRateLimitCooldownUntil")
                resetTransientToastState()
                guard !Task.isCancelled, searchGeneration == currentGeneration else { return }
                isSearchPending = false
                if searchCache.count >= 100 { searchCache.removeAll() }
                searchCache[cacheKey] = ranked
                panel.update(
                    query: query,
                    candidates: ranked,
                    showPanel: EmojiSearchPolicy.shouldShowPanel(
                        query: query, isContextMode: isContextMode
                    )
                )
                panel.showError(":\(query) · Jevの候補")
                if EmojiSearchPolicy.shouldAutoApplyFirstCandidate(
                    isContextMode: isContextMode, candidateCount: ranked.count
                ) {
                    autoApplyFirstCandidate(ranked)
                }
            } catch {
                let retryWait: Int?
                if case JevError.http(let code) = error,
                   code == 429 || code == 529 || (500...599).contains(code) {
                    retryWait = Int(jevPacer.recordRateLimit(at: Date()))
                    UserDefaults.standard.set(jevPacer.cooldownUntil, forKey: "JevRateLimitCooldownUntil")
                } else {
                    retryWait = nil
                }
                guard !Task.isCancelled, searchGeneration == currentGeneration else { return }
                isSearchPending = false
                panel.update(query: query, candidates: local)
                presentSearchError(error, retryWait: retryWait)
            }
        }
    }

    private func presentSearchError(_ error: Error, retryWait: Int?) {
        if case JevError.http(let code) = error {
            switch code {
            case 401, 403:
                panel.showError("Jev APIキーを確認してください · ローカル候補を表示中")
                showToastOnce(
                    id: "jev-auth-\(code)",
                    title: "Jevに接続できません",
                    message: code == 401
                        ? "APIキーが無効か、期限切れです"
                        : "このAPIキーではJevを利用できません",
                    symbolName: "key",
                    actionTitle: "キーを更新",
                    duration: 8
                ) { [weak self] in
                    self?.openSettings()
                }
                return
            case 429:
                let wait = retryWait ?? 60
                panel.showError("Jevの利用制限中 · 約\(wait)秒はローカル候補を表示")
                let resumeText = formattedResumeTime(after: wait)
                showToastOnce(
                    id: "jev-rate-limit-\(Int(jevPacer.cooldownUntil?.timeIntervalSince1970 ?? 0))",
                    title: "Jevの利用制限中",
                    message: "\(resumeText)から検索を再開します",
                    symbolName: "clock",
                    actionTitle: "利用状況",
                    duration: 8
                ) { [weak self] in
                    self?.openJevConsole()
                }
                return
            case 500...599:
                let wait = retryWait ?? 60
                panel.showError("Jevが混み合っています · 約\(wait)秒はローカル候補を表示")
                showToastOnce(
                    id: "jev-service-\(code)-\(Int(jevPacer.cooldownUntil?.timeIntervalSince1970 ?? 0))",
                    title: "Jevが混み合っています",
                    message: "ローカル候補を表示しています",
                    symbolName: "cloud",
                    duration: 5
                )
                return
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                panel.showError("オフライン · ローカル候補を表示しています")
                showToastOnce(
                    id: "jev-network-offline",
                    title: "インターネットに接続されていません",
                    message: "接続後にJev検索を再開します",
                    symbolName: "wifi.slash",
                    duration: 6
                )
                return
            case .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed:
                panel.showError("Jevから応答がありません · ローカル候補を表示中")
                showToastOnce(
                    id: "jev-network-temporary",
                    title: "Jevから応答がありません",
                    message: "ローカル候補を表示しています",
                    symbolName: "wifi.exclamationmark",
                    duration: 5
                )
                return
            default:
                break
            }
        }

        panel.showError(error.localizedDescription)
    }

    private func showMissingAPIKeyToast() {
        showToastOnce(
            id: "jev-no-key",
            title: "Jevを使うにはAPIキーが必要です",
            message: "設定すると意味から絵文字を検索できます",
            symbolName: "key",
            actionTitle: "APIキーを設定",
            duration: 8
        ) { [weak self] in
            self?.openSettings()
        }
    }

    private func showToastOnce(
        id: String,
        title: String,
        message: String,
        symbolName: String,
        actionTitle: String? = nil,
        duration: TimeInterval,
        action: (() -> Void)? = nil
    ) {
        guard shownToastIDs.insert(id).inserted else { return }
        toastPanel.show(
            title: title,
            message: message,
            symbolName: symbolName,
            actionTitle: actionTitle,
            duration: duration,
            on: statusItem.button?.window?.screen,
            action: action
        )
    }

    private func resetTransientToastState() {
        shownToastIDs = shownToastIDs.filter {
            !$0.hasPrefix("jev-network-") && !$0.hasPrefix("jev-service-")
        }
    }

    private func formattedResumeTime(after seconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "H:mm"
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(seconds)))
    }

    private func openJevConsole() {
        guard let url = URL(string: "https://console.typesafe.ai") else { return }
        NSWorkspace.shared.open(url)
    }

    private func replaceShortcut(with entry: EmojiEntry) {
        guard let shortcut = activeShortcut else { return }
        // While a Japanese IME is still composing, nothing can take the
        // shortcut away: the editor keeps the composition and the emoji lands
        // after it, and Shift-Left moves inside the conversion instead of
        // selecting it. Settle the text first, then replace it.
        guard ShortcutReplacement.visibleShortcut(
            rawShortcut: shortcut, originalElement: shortcutTarget
        ) == shortcut else {
            commitCompositionThenReplace(shortcut: shortcut, with: entry)
            return
        }
        replaceCommittedShortcut(shortcut: shortcut, with: entry)
    }

    private func commitCompositionThenReplace(shortcut: String, with entry: EmojiEntry) {
        guard !isCommittingComposition else { return }
        isCommittingComposition = true
        isBlockingKeyboardInput = true
        let generation = keyboardReplacementGeneration
        Task { [weak self] in
            await IMEComposition.commit()
            guard let self, self.keyboardReplacementGeneration == generation,
                  self.activeShortcut == shortcut else { return }
            self.isCommittingComposition = false
            self.isBlockingKeyboardInput = false
            // 英数 also left the IME in alphanumeric mode. Only put it back
            // when the committed shortcut shows the user was typing Japanese.
            let visible = ShortcutReplacement.visibleShortcut(
                rawShortcut: shortcut, originalElement: self.shortcutTarget
            )
            self.pendingKanaRestore = IMEComposition.containsJapanese(visible ?? "")
            self.replaceCommittedShortcut(shortcut: shortcut, with: entry)
        }
    }

    private func replaceCommittedShortcut(shortcut: String, with entry: EmojiEntry) {
        switch ShortcutReplacement.selectVisibleShortcut(
            rawShortcut: shortcut, originalElement: shortcutTarget
        ) {
        case .success: break
        case .failure(let reason):
            // Every way the Accessibility path can fail leaves the text
            // untouched, so the keyboard fallback is always worth trying.
            if let targetApp = shortcutTargetApplication {
                beginKeyboardReplacement(shortcut: shortcut, emoji: entry.emoji,
                                         targetApp: targetApp)
                return
            }
            panel.showError("\(reason.message) · 入力はそのままです · Escで閉じる")
            restoreInputModeIfNeeded()
            return
        }
        cancelShortcut()
        paste(entry.emoji)
        restoreInputModeIfNeeded()
    }

    /// Puts the IME back into kana mode after a commit that was only made to
    /// settle the text for replacement.
    private func restoreInputModeIfNeeded() {
        guard pendingKanaRestore else { return }
        pendingKanaRestore = false
        IMEComposition.restoreKanaMode()
    }

    /// Turns an emoji that was inserted from context into a text search. The
    /// user types the search word right after ':' without waiting for the
    /// automatic selection, so the inserted emoji goes back to being the
    /// shortcut and the typed character starts the query.
    private func resumeTextSearch(from selection: AutoAppliedSelection, characters chars: String) -> Bool {
        guard let resume = EmojiSearchPolicy.textSearchResume(
            shortcut: selection.shortcut, characters: chars
        ) else { return false }
        guard let targetApp = selection.targetApplication else { return false }
        return beginKeyboardTextSearchResume(
            from: selection, shortcut: resume.shortcut, targetApp: targetApp
        )
    }

    /// Collects the whole typing burst before replacing the auto-applied emoji.
    /// This avoids losing characters while an asynchronous editor operation is
    /// in progress and uses the same recent-insertion path in every app.
    private func beginKeyboardTextSearchResume(
        from selection: AutoAppliedSelection,
        shortcut: String,
        targetApp: NSRunningApplication
    ) -> Bool {
        guard !isPerformingKeyboardReplacement else { return false }
        shortcutTarget = selection.target
        shortcutTargetApplication = targetApp
        shortcutContext = nil
        lastTypedCharacter = shortcut.last
        pendingTextSearchResume = PendingTextSearchResume(
            selection: selection, shortcut: shortcut, revision: 0
        )
        isPerformingKeyboardReplacement = true
        isBlockingKeyboardInput = true
        let generation = keyboardReplacementGeneration
        let stillValid: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.isPerformingKeyboardReplacement
                && self.keyboardReplacementGeneration == generation
                && self.pendingTextSearchResume?.selection.appliedEmoji
                    == selection.appliedEmoji
        }
        Task { [weak self] in
            guard let self else { return }
            while stillValid() {
                let revision = self.pendingTextSearchResume?.revision
                try? await Task.sleep(for: .milliseconds(200))
                guard stillValid() else { return }
                if self.pendingTextSearchResume?.revision == revision { break }
            }
            guard let pending = self.pendingTextSearchResume else { return }
            let finalShortcut = pending.shortcut
            self.activeShortcut = finalShortcut
            let onPastePosted: () -> Void = { [weak self] in
                guard let self, stillValid() else { return }
                self.keyboardReplacementGeneration += 1
                self.isBlockingKeyboardInput = false
                self.isPerformingKeyboardReplacement = false
                self.pendingTextSearchResume = nil
                self.autoAppliedSelection = nil
                self.lastTypedCharacter = finalShortcut.last
                self.updateCandidates()
            }
            let result = await KeyboardReplacement.replaceMostRecentInsertion(
                selection.appliedEmoji, with: finalShortcut, in: targetApp,
                stillValid: stillValid, onPastePosted: onPastePosted
            )
            guard self.keyboardReplacementGeneration == generation else { return }
            self.isPerformingKeyboardReplacement = false
            self.isBlockingKeyboardInput = false
            if case .failure(let reason) = result {
                let typedText = EmojiSearchPolicy.typedTextToRestore(
                    originalShortcut: selection.shortcut,
                    resumedShortcut: finalShortcut
                )
                self.pendingTextSearchResume = nil
                self.autoAppliedSelection = nil
                self.finishCommittedShortcut()
                if !typedText.isEmpty { self.paste(typedText) }
                self.showToastOnce(
                    id: "resume-search-\(reason)",
                    title: "検索に切り替えられませんでした",
                    message: "入力した文字はそのまま残しました",
                    symbolName: "exclamationmark.triangle",
                    duration: 4
                )
            }
        }
        return true
    }

    private func autoApplyFirstCandidate(_ candidates: [EmojiEntry]) {
        guard let shortcut = activeShortcut, let first = candidates.first else { return }
        autoAppliedSelection = AutoAppliedSelection(
            shortcut: shortcut,
            candidates: candidates,
            appliedEmoji: first.emoji,
            target: shortcutTarget,
            targetApplication: shortcutTargetApplication
        )
        replaceShortcut(with: first)
    }

    private func replaceAutoApplied(_ selection: AutoAppliedSelection, with entry: EmojiEntry) {
        if entry.emoji == selection.appliedEmoji {
            choosingAutoApplied = nil
            panel.orderOut(nil)
            return
        }
        switch ShortcutReplacement.selectVisibleText(
            selection.appliedEmoji, originalElement: selection.target
        ) {
        case .success:
            choosingAutoApplied = nil
            panel.orderOut(nil)
            paste(entry.emoji)
        case .failure(let reason):
            guard let targetApp = selection.targetApplication else {
                panel.showError("\(reason.message) · 絵文字はそのままです")
                return
            }
            isPerformingKeyboardReplacement = true
            isBlockingKeyboardInput = true
            let generation = keyboardReplacementGeneration
            Task { [weak self] in
                guard let self else { return }
                let result = await KeyboardReplacement.replaceVisibleText(
                    selection.appliedEmoji, with: entry.emoji, in: targetApp,
                    element: selection.target,
                    stillValid: { [weak self] in
                        guard let self else { return false }
                        return self.isPerformingKeyboardReplacement
                            && self.keyboardReplacementGeneration == generation
                            && self.choosingAutoApplied != nil
                    },
                    onPastePosted: { [weak self] in
                        guard let self,
                              self.keyboardReplacementGeneration == generation,
                              self.choosingAutoApplied != nil else { return }
                        self.keyboardReplacementGeneration += 1
                        self.isBlockingKeyboardInput = false
                        self.isPerformingKeyboardReplacement = false
                        self.choosingAutoApplied = nil
                        self.panel.orderOut(nil)
                    }
                )
                guard self.keyboardReplacementGeneration == generation else { return }
                self.isPerformingKeyboardReplacement = false
                self.isBlockingKeyboardInput = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    self.panel.showError("\(error.message) · 絵文字はそのままです")
                }
            }
        }
    }

    private func postUndo() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(kVK_ANSI_Z)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = .maskCommand
        down?.setIntegerValueField(
            .eventSourceUserData, value: KeyboardReplacement.syntheticEventMarker
        )
        up?.setIntegerValueField(
            .eventSourceUserData, value: KeyboardReplacement.syntheticEventMarker
        )
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func beginKeyboardReplacement(
        shortcut: String, emoji: String, targetApp: NSRunningApplication
    ) {
        guard !isPerformingKeyboardReplacement else { return }
        isPerformingKeyboardReplacement = true
        isBlockingKeyboardInput = true
        panel.showError("入力した文字を確認中…")
        let generation = keyboardReplacementGeneration
        let element = shortcutTarget
        Task { [weak self] in
            guard let self else { return }
            let result = await self.performKeyboardReplacement(
                shortcut: shortcut, emoji: emoji, targetApp: targetApp,
                element: element, generation: generation
            )
            guard self.keyboardReplacementGeneration == generation else { return }
            self.isPerformingKeyboardReplacement = false
            self.isBlockingKeyboardInput = false
            self.restoreInputModeIfNeeded()
            switch result {
            case .success:
                break
            case .failure(let reason):
                self.panel.showError("\(reason.message) · 入力はそのままです · Escで閉じる")
            }
        }
    }

    /// Replacement for editors that refuse an Accessibility selection.
    /// Chromium-based ones (Chrome pages, Slack, ChatGPT) accept a selection
    /// made with Shift-Left and report it back through AXSelectedText;
    /// terminals expose no editable selection at all and are handled by
    /// deleting the characters they show. Both work on the visible shortcut,
    /// which with a Japanese IME differs from the roman keys we intercepted.
    private func performKeyboardReplacement(
        shortcut: String, emoji: String, targetApp: NSRunningApplication,
        element: AXUIElement?, generation: Int
    ) async -> Result<Void, KeyboardReplacement.Failure> {
        let stillValid: () -> Bool = { [weak self] in
            guard let self else { return false }
            return self.isPerformingKeyboardReplacement
                && self.keyboardReplacementGeneration == generation
                && self.activeShortcut == shortcut
        }
        let onPastePosted: () -> Void = { [weak self] in
            guard let self,
                  self.keyboardReplacementGeneration == generation,
                  self.activeShortcut == shortcut else { return }
            self.keyboardReplacementGeneration += 1
            self.isBlockingKeyboardInput = false
            self.isPerformingKeyboardReplacement = false
            self.finishCommittedShortcut()
        }

        let visible = ShortcutReplacement.visibleShortcut(
            rawShortcut: shortcut, originalElement: element
        )
        guard let visible else {
            // Nothing readable through Accessibility. Keep the strict old
            // path: ASCII shortcodes, verified against the clipboard.
            guard KeyboardReplacement.canReplace(shortcut) else {
                return .failure(.unsupportedShortcut)
            }
            return await KeyboardReplacement.replace(
                shortcut: shortcut, with: emoji, in: targetApp,
                stillValid: stillValid, onPastePosted: onPastePosted
            )
        }
        if let element, !ShortcutReplacement.replacesSelectedText(element),
           visible != shortcut {
            // A terminal keeps an IME composition out of Accessibility. Do
            // not delete visible text unless it exactly matches the shortcut.
            return .failure(.composingText)
        }
        return await KeyboardReplacement.replaceVisibleText(
            visible, with: emoji, in: targetApp, element: element,
            stillValid: stillValid, onPastePosted: onPastePosted
        )
    }

    private func cancelShortcut() {
        isCommittingComposition = false
        if isPerformingKeyboardReplacement {
            keyboardReplacementGeneration += 1
            isPerformingKeyboardReplacement = false
        }
        isBlockingKeyboardInput = false
        pendingTextSearchResume = nil
        searchGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearchPending = false
        contextCaptureGeneration += 1
        activeShortcut = nil
        shortcutTarget = nil
        shortcutTargetApplication = nil
        shortcutContext = nil
        panel.orderOut(nil)
    }

    private func finishCommittedShortcut() {
        pendingTextSearchResume = nil
        searchGeneration += 1
        contextCaptureGeneration += 1
        searchTask?.cancel()
        searchTask = nil
        isSearchPending = false
        activeShortcut = nil
        shortcutTarget = nil
        shortcutTargetApplication = nil
        shortcutContext = nil
        panel.orderOut(nil)
    }

    private func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let old = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        // Mark the paste so the event tap does not read it back as the user
        // pressing a command key, which would cancel the shortcut that is
        // still being edited.
        down?.setIntegerValueField(
            .eventSourceUserData, value: KeyboardReplacement.syntheticEventMarker
        )
        up?.setIntegerValueField(
            .eventSourceUserData, value: KeyboardReplacement.syntheticEventMarker
        )
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pasteboard.string(forType: .string) == text, let old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshPermissionMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Start as a foreground app so the onboarding window can be presented before
// any macOS permission UI. Completed setups switch back to `.accessory` during
// launch; new setups switch after both permissions are granted.
app.setActivationPolicy(.regular)
app.run()
