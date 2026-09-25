import EmojiCatalogCore
import UIKit

protocol EmojiCandidateStripViewDelegate: AnyObject {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry)
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

/// The row of tappable emoji shown above the keys while a word is being
/// typed, in the same spot a system keyboard would show predictive text.
/// While Jev is still ranking, three pulsing dots follow the local matches.
/// With no word in progress it shows the 左寄せ / 通常 / 右寄せ picker
/// instead, since the stock globe-key menu for it isn't reachable here.
final class EmojiCandidateStripView: UIView {
    weak var delegate: EmojiCandidateStripViewDelegate?

    private let handednessPicker = UIStackView()
    private var handednessButtons: [KeyboardHandedness: UIButton] = [:]
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var candidates: [EmojiEntry] = []
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
            handednessButtons[option] = button
            handednessPicker.addArrangedSubview(button)
        }
        addSubview(handednessPicker)
        handednessPicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            handednessPicker.centerXAnchor.constraint(equalTo: centerXAnchor),
            handednessPicker.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            handednessPicker.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    /// Swap the emoji row for the handedness picker, lighting `current`.
    func showHandednessPicker(current: KeyboardHandedness) {
        setLoading(false)
        update(candidates: [])
        for (option, button) in handednessButtons {
            let selected = option == current
            button.tintColor = selected ? .systemBlue : .secondaryLabel
            button.backgroundColor = selected ? UIColor.systemBlue.withAlphaComponent(0.15) : .clear
        }
        scrollView.isHidden = true
        handednessPicker.isHidden = false
        isHidden = false
    }

    func update(candidates: [EmojiEntry]) {
        scrollView.isHidden = false
        handednessPicker.isHidden = true
        self.candidates = candidates
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, entry) in candidates.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(entry.emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28)
            button.tag = index
            button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            stackView.addArrangedSubview(button)
        }
        if isLoading {
            // Re-added after the rebuild above, so restart its animation too.
            stackView.addArrangedSubview(loadingDots)
            loadingDots.startAnimating()
        }
        updateVisibility()
    }

    func setLoading(_ loading: Bool) {
        guard loading != isLoading else { return }
        isLoading = loading
        if loading {
            stackView.addArrangedSubview(loadingDots)
            loadingDots.startAnimating()
        } else {
            loadingDots.stopAnimating()
            stackView.removeArrangedSubview(loadingDots)
            loadingDots.removeFromSuperview()
        }
        updateVisibility()
    }

    private func updateVisibility() {
        isHidden = candidates.isEmpty && !isLoading
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        delegate?.candidateStrip(self, didSelect: candidates[sender.tag])
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
