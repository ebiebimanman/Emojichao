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
/// conversions underneath, next to the keys. While Jev is still ranking, three pulsing dots follow
/// the emoji. With nothing in progress it shows the 左寄せ / 通常 / 右寄せ
/// picker instead, since the stock globe-key menu for it isn't reachable.
final class EmojiCandidateStripView: UIView {
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
    private let loadingDots = LoadingDotsView()
    private var isLoading = false

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
        setLoading(false)
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

    /// Replace just the emoji row, keeping the conversions (Jev results).
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

        var emojiItems: [UIView] = emoji.enumerated().map { index, entry in
            let button = UIButton(type: .system)
            button.setTitle(entry.emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumTapWidth).isActive = true
            button.tag = index
            button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            return button
        }
        if isLoading { emojiItems.append(loadingDots) }
        emojiRow.setItems(emojiItems)
        // Re-added by the rebuild above, so restart its animation too.
        if isLoading { loadingDots.startAnimating() }
        updateVisibility()
    }

    func setLoading(_ loading: Bool) {
        guard loading != isLoading else { return }
        isLoading = loading
        if loading {
            emojiRow.append(loadingDots)
            loadingDots.startAnimating()
        } else {
            loadingDots.stopAnimating()
            loadingDots.removeFromSuperview()
        }
        updateVisibility()
    }

    private func updateVisibility() {
        isHidden = candidates.isEmpty && conversions.isEmpty && !isLoading
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

    func append(_ item: UIView) {
        stackView.addArrangedSubview(item)
    }

    func reveal(_ item: UIView) {
        layoutIfNeeded()
        scrollView.scrollRectToVisible(item.frame.insetBy(dx: -40, dy: 0), animated: true)
    }
}

/// Three dots that pulse in turn, like a typing indicator.
private final class LoadingDotsView: UIView {
    private let dots: [UIView] = (0..<3).map { _ in UIView() }
    private static let dotSize: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: dots)
        stack.axis = .horizontal
        stack.spacing = 5
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for dot in dots {
            dot.backgroundColor = .secondaryLabel
            dot.layer.cornerRadius = Self.dotSize / 2
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
            dot.heightAnchor.constraint(equalToConstant: Self.dotSize).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func startAnimating() {
        for (index, dot) in dots.enumerated() {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.25
            pulse.duration = 0.45
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.beginTime = CACurrentMediaTime() + Double(index) * 0.15
            dot.layer.add(pulse, forKey: "pulse")
        }
    }

    func stopAnimating() {
        dots.forEach { $0.layer.removeAnimation(forKey: "pulse") }
    }
}
