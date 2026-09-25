import EmojiCatalogCore
import UIKit

/// A minimal add-on keyboard (switched to via the globe key, same as
/// Gboard/Simeji) whose only job is ':shortcode' emoji search. It reuses the
/// exact catalog/scoring logic and shortcode-character rules from the macOS
/// app's EmojiCatalogCore package.
///
/// This is a Phase 1 (local-only) build: no network access, so no "Allow
/// Full Access" prompt is needed to use it. The letter layout is a single
/// lowercase QWERTY row set with no shift, symbols page, or autocorrect —
/// enough to type a shortcode query, not a full replacement for the user's
/// everyday keyboard.
@MainActor
final class KeyboardViewController: UIInputViewController {
    private let candidateStrip = EmojiCandidateStripView()

    /// Text typed since an unmatched ':' started a shortcode search, not
    /// including the ':' itself. nil when no search is active.
    private var activeQuery: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        candidateStrip.delegate = self
        candidateStrip.isHidden = true

        // Custom keyboard extensions can otherwise report a zero-height view
        // on first layout; an explicit height is the standard workaround.
        view.heightAnchor.constraint(equalToConstant: 260).isActive = true

        let rows = buildKeyRows()
        view.addSubview(candidateStrip)
        view.addSubview(rows)

        candidateStrip.translatesAutoresizingMaskIntoConstraints = false
        rows.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidateStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateStrip.topAnchor.constraint(equalTo: view.topAnchor),
            candidateStrip.heightAnchor.constraint(equalToConstant: 44),

            rows.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            rows.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            rows.topAnchor.constraint(equalTo: candidateStrip.bottomAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
    }

    // MARK: - Key layout

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private func buildKeyRows() -> UIStackView {
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 6
        outer.distribution = .fillEqually
        for row in Self.letterRows {
            outer.addArrangedSubview(buildLetterRow(row))
        }
        outer.addArrangedSubview(buildBottomRow())
        return outer
    }

    private func buildLetterRow(_ letters: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillEqually
        for letter in letters {
            let title = String(letter)
            row.addArrangedSubview(makeKey(title: title) { [weak self] in self?.insert(title) })
        }
        return row
    }

    private func buildBottomRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fill

        let nextKeyboard = makeKey(title: "🌐") { [weak self] in self?.advanceToNextInputMode() }
        let colon = makeKey(title: ":") { [weak self] in self?.insert(":") }
        let space = makeKey(title: "space") { [weak self] in self?.insert(" ") }
        let backspace = makeKey(title: "⌫") { [weak self] in self?.handleBackspace() }
        let returnKey = makeKey(title: "return") { [weak self] in self?.insertReturn() }
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true

        [nextKeyboard, colon, space, backspace, returnKey].forEach { row.addArrangedSubview($0) }
        return row
    }

    private func makeKey(title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = .secondarySystemBackground
        button.layer.cornerRadius = 4
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Typing and shortcode search

    private func insert(_ characters: String) {
        textDocumentProxy.insertText(characters)
        trackTyped(characters)
    }

    private func insertReturn() {
        textDocumentProxy.insertText("\n")
        endQuery()
    }

    private func handleBackspace() {
        textDocumentProxy.deleteBackward()
        guard var query = activeQuery else { return }
        guard !query.isEmpty else {
            // The ':' itself was just deleted.
            endQuery()
            return
        }
        query.removeLast()
        activeQuery = query
        updateCandidates(for: query)
    }

    private func trackTyped(_ characters: String) {
        if characters == ":" {
            activeQuery = ""
            updateCandidates(for: "")
            return
        }
        guard activeQuery != nil else { return }
        guard EmojiSearchPolicy.isSearchableCharacter(characters) else {
            endQuery()
            return
        }
        activeQuery! += characters
        updateCandidates(for: activeQuery!)
    }

    private func updateCandidates(for query: String) {
        candidateStrip.update(candidates: EmojiCatalog.shared.localMatches(query))
    }

    private func endQuery() {
        activeQuery = nil
        candidateStrip.update(candidates: [])
    }
}

extension KeyboardViewController: EmojiCandidateStripViewDelegate {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry) {
        guard let query = activeQuery else { return }
        // Remove the typed ':query', including the ':', before inserting the emoji.
        for _ in 0...query.count {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(entry.emoji)
        endQuery()
    }
}
