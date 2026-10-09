import EmojiCatalogCore
import UIKit

protocol EmojiCandidateStripViewDelegate: AnyObject {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry)
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelectConversionAt index: Int)
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect handedness: KeyboardHandedness)
}

/// 左寄せ / 通常 / 右寄せ, remembered across launches like the stock keyboard.
enum KeyboardHandedness: String, CaseIterable {
    case left, full, right

    private static let defaultsKey = "Handedness"

    static var saved: KeyboardHandedness {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(KeyboardHandedness.init) ?? .full
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    var symbolName: String {
        switch self {
        case .left: return "keyboard.onehanded.left"
        case .full: return "keyboard"
        case .right: return "keyboard.onehanded.right"
        }
    }
}

/// The two rows above the keys, where a system keyboard shows its
/// candidates: emoji for the kana being composed on top, its kanji
/// conversions underneath, next to the keys. While emoji are being looked
/// up, a 検索中… badge spins at the end of the emoji row (which dims while
/// its emoji are left over from before); when the search is done the badge
/// goes, or reads 該当なし for a moment if nothing matched. With nothing in progress it shows the
/// 左寄せ / 通常 / 右寄せ picker instead, since the stock globe-key menu for
/// it isn't reachable.
final class EmojiCandidateStripView: UIView {
    enum SearchState: Equatable {
        case idle
        /// `stale`: the emoji showing are for what was typed before.
        case searching(stale: Bool)
        case finished(found: Bool)
    }

    weak var delegate: EmojiCandidateStripViewDelegate?

    /// Each row is the whole touch target, so keep it at the 44pt minimum.
    static let rowHeight: CGFloat = 44
    private static let minimumTapWidth: CGFloat = 44

    private let handednessPicker = UIStackView()
    private var handednessButtons: [KeyboardHandedness: UIButton] = [:]
    private let rows = UIStackView()
    private let conversionRow = CandidateRow()
    private let emojiRow = CandidateRow()
    private var candidates: [EmojiEntry] = []
    /// The emoji currently on show.
    var emoji: [EmojiEntry] { candidates }
    private var conversions: [String] = []
    private var selectedConversion: Int?
    private let statusBadge = SearchStatusView()
    private var searchState = SearchState.idle
    /// Shows the searching look after a beat, or hides 該当なし after one.
    private var statusTimer: Task<Void, Never>?
    /// Local lookups usually land within this; only slower searches (Jev)
    /// show the badge, so typing doesn't make the row flicker.
    private static let searchingDelay: Duration = .milliseconds(150)
    private static let noMatchesDuration: Duration = .seconds(1.2)
    private static let dimmedAlpha: CGFloat = 0.45

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpLayout() {
        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true

        rows.axis = .vertical
        rows.addArrangedSubview(emojiRow)
        rows.addArrangedSubview(divider)
        rows.addArrangedSubview(conversionRow)
        addSubview(rows)
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            conversionRow.heightAnchor.constraint(equalTo: emojiRow.heightAnchor)
        ])

        // Over the end of the emoji row; it takes no touches, so the emoji
        // under it stay tappable.
        addSubview(statusBadge)
        statusBadge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusBadge.trailingAnchor.constraint(equalTo: emojiRow.trailingAnchor, constant: -6),
            statusBadge.centerYAnchor.constraint(equalTo: emojiRow.centerYAnchor)
        ])

        handednessPicker.axis = .horizontal
        handednessPicker.spacing = 24
        handednessPicker.isHidden = true
        for option in KeyboardHandedness.allCases {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: option.symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.candidateStrip(self, didSelect: option)
            }, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 52).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            handednessButtons[option] = button
            handednessPicker.addArrangedSubview(button)
        }
        addSubview(handednessPicker)
        handednessPicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            handednessPicker.centerXAnchor.constraint(equalTo: centerXAnchor),
            handednessPicker.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// Swap the candidate rows for the handedness picker, lighting `current`.
    func showHandednessPicker(current: KeyboardHandedness) {
        setSearchState(.idle)
        update(conversions: [], selected: nil, emoji: [])
        for (option, button) in handednessButtons {
            let selected = option == current
            button.tintColor = selected ? .systemBlue : .secondaryLabel
            button.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.15) : .clear
        }
        rows.isHidden = true
        handednessPicker.isHidden = false
        isHidden = false
    }

    /// Emoji only (no composition, e.g. an ABC word).
    func update(candidates: [EmojiEntry]) {
        update(conversions: [], selected: nil, emoji: candidates)
    }

    /// Replace just the emoji row, keeping the conversions (search results).
    func updateEmoji(_ emoji: [EmojiEntry]) {
        update(conversions: conversions, selected: selectedConversion, emoji: emoji)
    }

    /// Move the 次候補 highlight without touching the rest.
    func selectConversion(_ index: Int?) {
        update(conversions: conversions, selected: index, emoji: candidates)
    }

    func update(conversions: [String], selected: Int?, emoji: [EmojiEntry]) {
        rows.isHidden = false
        handednessPicker.isHidden = true
        self.conversions = conversions
        self.selectedConversion = selected
        self.candidates = emoji

        let conversionButtons = conversions.enumerated().map { index, text in
            let button = UIButton(type: .system)
            button.setTitle(text, for: .normal)
            button.setTitleColor(.label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 18)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
            button.layer.cornerRadius = 6
            if index == selected {
                button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.2)
            }
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumTapWidth).isActive = true
            button.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.candidateStrip(self, didSelectConversionAt: index)
            }, for: .touchUpInside)
            return button
        }
        conversionRow.setItems(conversionButtons)
        if let selected, conversionButtons.indices.contains(selected) {
            conversionRow.reveal(conversionButtons[selected])
        }

        let emojiItems: [UIView] = emoji.enumerated().map { index, entry in
            let button = UIButton(type: .system)
            button.setTitle(entry.emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumTapWidth).isActive = true
            button.tag = index
            button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            return button
        }
        emojiRow.setItems(emojiItems)
        updateVisibility()
    }

    /// Show whether emoji are still being looked up, or how it went.
    func setSearchState(_ state: SearchState) {
        // The badge sits over the emoji row; with the handedness picker up
        // instead, there's nothing for it to describe.
        let state = rows.isHidden ? .idle : state
        guard state != searchState else { return }
        let previous = searchState
        searchState = state
        defer { updateVisibility() }
        if case .searching(let stale) = state, case .searching = previous {
            // Still searching (now only Jev, say): keep the badge, and just
            // brighten the row once its emoji are current. If the badge is
            // still waiting to appear, it'll pick up the new state itself.
            if statusTimer == nil {
                UIView.animate(withDuration: 0.15) { self.emojiRow.alpha = stale ? Self.dimmedAlpha : 1 }
            }
            return
        }
        statusTimer?.cancel()
        statusTimer = nil
        switch state {
        case .idle:
            statusBadge.layer.removeAllAnimations()
            statusBadge.alpha = 0
            statusBadge.stop()
            emojiRow.alpha = 1
        case .searching:
            let delay = Self.searchingDelay
            let dimmedAlpha = Self.dimmedAlpha
            statusTimer = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self, case .searching(let stale) = self.searchState else { return }
                self.statusTimer = nil
                self.statusBadge.showSearching()
                self.bringSubviewToFront(self.statusBadge)
                UIView.animate(withDuration: 0.15) {
                    self.statusBadge.alpha = 1
                    // Dim emoji that are still for what was typed before.
                    self.emojiRow.alpha = stale ? dimmedAlpha : 1
                }
            }
        case .finished(found: true):
            UIView.animate(withDuration: 0.2, delay: 0, options: .beginFromCurrentState) {
                self.statusBadge.alpha = 0
                self.emojiRow.alpha = 1
            } completion: { _ in
                if case .finished = self.searchState { self.statusBadge.stop() }
            }
        case .finished(found: false):
            statusBadge.showNoMatches()
            bringSubviewToFront(statusBadge)
            UIView.animate(withDuration: 0.15, delay: 0, options: .beginFromCurrentState) {
                self.statusBadge.alpha = 1
                self.emojiRow.alpha = 1
            }
            let duration = Self.noMatchesDuration
            statusTimer = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled, let self, self.searchState == .finished(found: false) else { return }
                self.statusTimer = nil
                UIView.animate(withDuration: 0.3) { self.statusBadge.alpha = 0 }
            }
        }
    }

    private func updateVisibility() {
        isHidden = candidates.isEmpty && conversions.isEmpty && searchState == .idle
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        delegate?.candidateStrip(self, didSelect: candidates[sender.tag])
    }
}

/// One horizontally scrolling row of candidates.
private final class CandidateRow: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .fill
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Replace the row's contents and scroll back to its start.
    func setItems(_ items: [UIView]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        items.forEach { stackView.addArrangedSubview($0) }
        scrollView.setContentOffset(.zero, animated: false)
    }

    func reveal(_ item: UIView) {
        layoutIfNeeded()
        scrollView.scrollRectToVisible(item.frame.insetBy(dx: -40, dy: 0), animated: true)
    }
}

/// The badge over the end of the emoji row: a spinner with 検索中… while
/// searching, 該当なし when nothing matched. It never takes touches.
private final class SearchStatusView: UIView {
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        // Resolved per appearance, so it follows light and dark mode.
        backgroundColor = UIColor { traits in
            UIColor.secondarySystemBackground.resolvedColor(with: traits).withAlphaComponent(0.95)
        }
        layer.cornerRadius = 14
        spinner.color = .secondaryLabel
        spinner.hidesWhenStopped = true
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSearching() {
        label.text = "検索中…"
        spinner.startAnimating()
    }

    func showNoMatches() {
        label.text = "該当なし"
        spinner.stopAnimating()
    }

    func stop() {
        spinner.stopAnimating()
    }
}
