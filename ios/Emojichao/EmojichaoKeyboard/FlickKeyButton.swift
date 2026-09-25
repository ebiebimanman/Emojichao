import UIKit

/// The iPhone keyboard's key colors, which differ from the stock
/// `systemBackground` family in dark mode.
enum KeyColors {
    static let character = UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    }
    static let function = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.27, alpha: 1)
            : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
    }
}

/// A 12-key (テンキー) key that tells a tap apart from a flick in one of four
/// directions. Reports the direction under the finger while it moves (for
/// the preview bubble) and the final one on release.
final class FlickKeyButton: UIControl {
    let key: FlickKey
    var onPreview: ((FlickKeyButton, FlickDirection?) -> Void)?
    /// `isTap` is true only when the finger never left the center, which is
    /// what advances the トグル cycle; a flick back to center just types the
    /// center character.
    var onCommit: ((FlickKeyButton, FlickDirection, _ isTap: Bool) -> Void)?

    private static let flickThreshold: CGFloat = 18

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var startPoint: CGPoint = .zero
    private var direction: FlickDirection = .center
    private var didLeaveCenter = false

    init(key: FlickKey) {
        self.key = key
        super.init(frame: .zero)
        backgroundColor = KeyColors.character
        layer.cornerRadius = 6
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)

        titleLabel.text = key.label
        titleLabel.textColor = .label
        titleLabel.font = .systemFont(ofSize: key.label.count > 2 ? 17 : 22)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        subtitleLabel.text = key.subLabel
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.isHidden = key.subLabel == nil

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 0
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        startPoint = touch.location(in: self)
        direction = .center
        didLeaveCenter = false
        backgroundColor = KeyColors.function
        onPreview?(self, .center)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        let point = touch.location(in: self)
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y
        let newDirection: FlickDirection
        if hypot(dx, dy) < Self.flickThreshold {
            newDirection = .center
        } else if abs(dx) > abs(dy) {
            newDirection = dx < 0 ? .left : .right
        } else {
            newDirection = dy < 0 ? .up : .down
        }
        if newDirection != .center { didLeaveCenter = true }
        if newDirection != direction {
            direction = newDirection
            onPreview?(self, direction)
        }
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        backgroundColor = KeyColors.character
        onPreview?(self, nil)
        onCommit?(self, direction, !didLeaveCenter)
    }

    override func cancelTracking(with event: UIEvent?) {
        backgroundColor = KeyColors.character
        onPreview?(self, nil)
    }
}
