import EmojiCatalogCore
import UIKit

/// A minimal add-on keyboard (switched to via the globe key, same as
/// Gboard/Simeji) that searches emoji by the word you're currently typing,
/// no explicit trigger needed. Typing is romaji-to-hiragana only (no kanji
/// conversion, no Latin/English mode) — see RomajiConverter.swift.
///
/// Local matching always works with no network access. If the user grants
/// "Allow Full Access" and has saved a Jev API key (via the container app's
/// settings screen, shared through the App Group in JevKeyStore.swift), the
/// candidate strip is re-ranked by Jev's semantic search on top of the
/// immediate local results.
@MainActor
final class KeyboardViewController: UIInputViewController {
    private let candidateStrip = EmojiCandidateStripView()

    /// The word committed so far (hiragana), since the last word boundary
    /// (space, return, punctuation).
    private var currentWord = ""
    /// Romaji typed but not yet resolvable into hiragana, e.g. a lone "k"
    /// waiting for a vowel. Never reaches the document until it converts.
    private var pendingRomaji = ""

    private let jev = JevClient()
    private var jevPacer = SearchRequestPacer(minimumInterval: 0.5)
    private var searchGeneration = 0

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
            rows.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])
    }

    // MARK: - Key layout

    private static let letterRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

    private func buildKeyRows() -> UIStackView {
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 8
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
        row.spacing = 6
        row.distribution = .fillEqually
        for letter in letters {
            let title = String(letter)
            row.addArrangedSubview(makeKey(title: title, style: .letter) { [weak self] in
                self?.handleRomajiInput(title)
            })
        }
        return row
    }

    private func buildBottomRow() -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill

        let nextKeyboard = makeKey(title: "🌐", style: .control) { [weak self] in self?.advanceToNextInputMode() }
        let space = makeKey(title: "space", style: .control) { [weak self] in self?.insert(" ") }
        let backspace = makeKey(title: "⌫", style: .control) { [weak self] in self?.handleBackspace() }
        let returnKey = makeKey(title: "return", style: .control) { [weak self] in self?.insertReturn() }
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true

        [nextKeyboard, space, backspace, returnKey].forEach { row.addArrangedSubview($0) }
        return row
    }

    private enum KeyStyle {
        case letter
        case control
    }

    private func makeKey(title: String, style: KeyStyle, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: style == .letter ? 20 : 15)
        button.backgroundColor = style == .letter ? .systemBackground : .secondarySystemBackground
        button.layer.cornerRadius = 6
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.15
        button.layer.shadowRadius = 0.5
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    // MARK: - Typing and word search

    private func insert(_ characters: String) {
        textDocumentProxy.insertText(characters)
        trackTyped(characters)
    }

    private func insertReturn() {
        textDocumentProxy.insertText("\n")
        endWord()
    }

    private func handleRomajiInput(_ letter: String) {
        pendingRomaji += letter
        let (committed, remaining) = RomajiConverter.convert(pendingRomaji)
        pendingRomaji = remaining
        guard !committed.isEmpty else { return }
        textDocumentProxy.insertText(committed)
        currentWord += committed
        updateCandidates(for: currentWord)
    }

    private func handleBackspace() {
        if !pendingRomaji.isEmpty {
            // Not yet in the document, so there's nothing to delete there.
            pendingRomaji.removeLast()
            return
        }
        textDocumentProxy.deleteBackward()
        guard !currentWord.isEmpty else { return }
        currentWord.removeLast()
        updateCandidates(for: currentWord)
    }

    private func trackTyped(_ characters: String) {
        guard EmojiSearchPolicy.isSearchableCharacter(characters) else {
            endWord()
            return
        }
        currentWord += characters
        updateCandidates(for: currentWord)
    }

    private func updateCandidates(for query: String) {
        candidateStrip.update(candidates: EmojiCatalog.shared.localMatches(query))
        searchRemote(for: query)
    }

    private func searchRemote(for query: String) {
        guard hasFullAccess, let apiKey = JevKeyStore.read(), !apiKey.isEmpty,
              EmojiSearchPolicy.shouldSearchRemote(query) else { return }
        let now = Date()
        guard jevPacer.waitDuration(at: now) == 0 else { return }
        jevPacer.recordAttempt(at: now)
        searchGeneration += 1
        let generation = searchGeneration
        Task { [weak self] in
            guard let self else { return }
            do {
                let ranked = try await self.jev.rank(
                    query: query, context: nil,
                    entries: EmojiCatalog.shared.searchableEntries, apiKey: apiKey
                )
                guard self.searchGeneration == generation, self.currentWord == query else { return }
                self.jevPacer.recordSuccess()
                self.candidateStrip.update(candidates: ranked)
            } catch JevError.http(429) {
                self.jevPacer.recordRateLimit(at: Date())
            } catch {
                // Network/API trouble: leave the local matches already shown.
            }
        }
    }

    private func endWord() {
        currentWord = ""
        pendingRomaji = ""
        candidateStrip.update(candidates: [])
    }
}

extension KeyboardViewController: EmojiCandidateStripViewDelegate {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry) {
        guard !currentWord.isEmpty else { return }
        // Remove the typed word before inserting the emoji in its place.
        for _ in 0..<currentWord.count {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(entry.emoji)
        endWord()
    }
}
