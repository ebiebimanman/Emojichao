import AppKit
import UniformTypeIdentifiers

// The settings list of apps where Emojichao stays quiet. Entries are stored as
// bundle identifiers; the name shown comes from the installed app when macOS
// can still find it.
@MainActor
final class DisabledAppsView: NSView {
    private let tableView = NSTableView()
    private let removeButton = NSButton(title: "削除", target: nil, action: nil)
    private var identifiers: [String] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    static func displayName(for bundleIdentifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return bundleIdentifier }
        let name = FileManager.default.displayName(atPath: url.path)
        return name.isEmpty ? bundleIdentifier : name
    }

    func reload() {
        identifiers = DisabledApps.identifiers()
        tableView.reloadData()
        updateRemoveButton()
    }

    private func setupView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.allowsMultipleSelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.style = .inset

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let addButton = NSButton(title: "追加…", target: self, action: #selector(addApp))
        removeButton.target = self
        removeButton.action = #selector(removeSelectedApp)
        removeButton.isEnabled = false
        let buttons = NSStackView(views: [addButton, removeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        for view in [scrollView, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 96),
            buttons.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttons.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @objc private func addApp() {
        let openPanel = NSOpenPanel()
        openPanel.message = "Emojichaoを無効にするアプリを選んでください"
        openPanel.prompt = "追加"
        openPanel.allowedContentTypes = [.applicationBundle]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            let alert = NSAlert()
            alert.messageText = "このアプリのBundle IDを読み取れませんでした"
            alert.informativeText = "アプリケーションフォルダにある通常のアプリを選んでください。"
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return
        }
        DisabledApps.setDisabled(true, for: bundleIdentifier)
        reload()
    }

    @objc private func removeSelectedApp() {
        guard identifiers.indices.contains(tableView.selectedRow) else { return }
        DisabledApps.setDisabled(false, for: identifiers[tableView.selectedRow])
        reload()
    }

    private func updateRemoveButton() {
        removeButton.isEnabled = identifiers.indices.contains(tableView.selectedRow)
    }
}

extension DisabledAppsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { identifiers.count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard identifiers.indices.contains(row) else { return nil }
        let identifier = identifiers[row]
        let name = NSTextField(labelWithString: Self.displayName(for: identifier))
        name.font = .systemFont(ofSize: 13)
        let bundleID = NSTextField(labelWithString: identifier)
        bundleID.font = .systemFont(ofSize: 10)
        bundleID.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [name, bundleID])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveButton()
    }
}
