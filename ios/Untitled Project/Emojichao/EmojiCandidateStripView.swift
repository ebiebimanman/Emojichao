import EmojiCatalogCore
import UIKit

protocol EmojiCandidateStripViewDelegate: AnyObject {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry)
}

/// The row of tappable emoji shown above the keys while a ':shortcode' search
/// is active, in the same spot a system keyboard would show predictive text.
final class EmojiCandidateStripView: UIView {
    weak var delegate: EmojiCandidateStripViewDelegate?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var candidates: [EmojiEntry] = []

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
    }

    func update(candidates: [EmojiEntry]) {
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
        isHidden = candidates.isEmpty
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        guard candidates.indices.contains(sender.tag) else { return }
        delegate?.candidateStrip(self, didSelect: candidates[sender.tag])
    }
}
