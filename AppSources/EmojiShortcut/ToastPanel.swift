import AppKit

@MainActor
final class ToastPanel: NSPanel {
    private let iconBackground = NSBox()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private var actionHandler: (() -> Void)?
    private var dismissalTimer: Timer?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 82),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        configureContent()
    }

    private func configureContent() {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        contentView = effectView

        iconBackground.boxType = .custom
        iconBackground.borderWidth = 0
        iconBackground.fillColor = NSColor.systemYellow.withAlphaComponent(0.18)
        iconBackground.wantsLayer = true
        iconBackground.layer?.cornerRadius = 10
        iconBackground.layer?.cornerCurve = .continuous
        iconBackground.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .systemOrange
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [titleLabel, messageLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        actionButton.controlSize = .small
        actionButton.bezelStyle = .recessed
        actionButton.target = self
        actionButton.action = #selector(runAction)

        let contentStack = NSStackView(views: [iconBackground, textStack, actionButton])
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 11
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 13),
            contentStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
            contentStack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 34),
            iconBackground.heightAnchor.constraint(equalToConstant: 34),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18)
        ])
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        actionButton.setContentHuggingPriority(.required, for: .horizontal)
    }

    func show(
        title: String,
        message: String,
        symbolName: String,
        actionTitle: String? = nil,
        duration: TimeInterval = 6,
        on screen: NSScreen?,
        action: (() -> Void)? = nil
    ) {
        dismissalTimer?.invalidate()
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        actionHandler = action
        actionButton.title = actionTitle ?? ""
        actionButton.isHidden = actionTitle == nil || action == nil

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        if let visibleFrame = targetScreen?.visibleFrame {
            let origin = NSPoint(
                x: visibleFrame.maxX - frame.width - 14,
                y: visibleFrame.maxY - frame.height - 12
            )
            setFrameOrigin(origin)
        }
        orderFrontRegardless()

        dismissalTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.orderOut(nil) }
        }
    }

    @objc private func runAction() {
        orderOut(nil)
        actionHandler?()
    }
}
