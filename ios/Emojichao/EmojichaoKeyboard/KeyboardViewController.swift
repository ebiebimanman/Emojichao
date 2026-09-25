import EmojiCatalogCore
import UIKit

/// A minimal add-on keyboard (switched to via the globe key, same as
/// Gboard/Simeji) that searches emoji by the word you're currently typing,
/// no explicit trigger needed. The keys copy the iPhone's own 日本語かな
/// keyboard: a 12-key flick layout with 小゛゜, ABC/☆123 modes, the
/// "フリックのみ" option, and the one-handed (左右寄せ) layout. There is no
/// kanji conversion — kana go straight into the document.
///
/// Local matching always works with no network access. If the user grants
/// "Allow Full Access" and has saved a Jev API key (via the container app's
/// settings screen, shared through the App Group in JevKeyStore.swift), the
/// candidate strip is re-ranked by Jev's semantic search on top of the
/// immediate local results.
@MainActor
final class KeyboardViewController: UIInputViewController {
    private let candidateStrip = EmojiCandidateStripView()
    private let keyContainer = UIView()
    private let flickPreview = UILabel()
    private let leftChevron = UIButton(type: .system)
    private let rightChevron = UIButton(type: .system)
    private var keyLeading: NSLayoutConstraint!
    private var keyTrailing: NSLayoutConstraint!

    private static let keySpacing: CGFloat = 6
    private static let edgeInset: CGFloat = 4
    /// How much the keys shrink by in the one-handed layout.
    private static let oneHandedGutter: CGFloat = 64

    private var mode: KeyboardMode = .kana
    private var flickOnly = KeyboardSettings.flickOnly
    private var handedness = KeyboardHandedness.saved
    /// The word typed so far since the last word boundary (punctuation,
    /// or the cursor moving away).
    private var currentWord = ""
    /// The last tap on a flick key, so tapping it again soon replaces that
    /// character with the next one in the key's cycle (か → き → く …).
    /// Cleared by anything else. Never set in フリックのみ mode.
    private var toggle: (key: FlickKey, index: Int, time: Date)?
    /// With no → key to end a cycle, a pause this long does it instead, so
    /// か, pause, か types かか.
    private static let toggleTimeout: TimeInterval = 1.0

    private let jev = JevClient()
    private var jevPacer = SearchRequestPacer(minimumInterval: 0.5)
    private var searchGeneration = 0
    private var backspaceRepeat: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        candidateStrip.delegate = self
        candidateStrip.showHandednessPicker(current: handedness)

        // Custom keyboard extensions can otherwise report a zero-height view
        // on first layout; an explicit height is the standard workaround.
        view.heightAnchor.constraint(equalToConstant: 270).isActive = true

        view.addSubview(candidateStrip)
        view.addSubview(keyContainer)

        candidateStrip.translatesAutoresizingMaskIntoConstraints = false
        keyContainer.translatesAutoresizingMaskIntoConstraints = false
        keyLeading = keyContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        keyTrailing = keyContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            candidateStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            candidateStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            candidateStrip.topAnchor.constraint(equalTo: view.topAnchor),
            candidateStrip.heightAnchor.constraint(equalToConstant: 44),

            keyLeading,
            keyTrailing,
            keyContainer.topAnchor.constraint(equalTo: candidateStrip.bottomAnchor, constant: 4),
            keyContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])

        setUpChevrons()

        flickPreview.textAlignment = .center
        flickPreview.font = .systemFont(ofSize: 28)
        flickPreview.textColor = .white
        flickPreview.backgroundColor = .systemBlue
        flickPreview.layer.cornerRadius = 8
        flickPreview.clipsToBounds = true
        flickPreview.isHidden = true
        view.addSubview(flickPreview)

        applyHandedness()
        rebuildKeys()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The setting may have changed in the app since the last time.
        let latest = KeyboardSettings.flickOnly
        if latest != flickOnly {
            flickOnly = latest
            toggle = nil
            rebuildKeys()
        }
    }

    // MARK: - Key layout

    /// Five columns like the iPhone keyboard: function keys on the left,
    /// the 3×4 character grid, then ⌫, the (blank) 空白 slot, and 改行.
    private func rebuildKeys() {
        keyContainer.subviews.forEach { $0.removeFromSuperview() }

        let columns = UIStackView()
        columns.axis = .horizontal
        columns.spacing = Self.keySpacing
        columns.distribution = .fillEqually

        columns.addArrangedSubview(buildLeftColumn())
        let grid = mode.grid
        for column in 0..<3 {
            columns.addArrangedSubview(verticalStack(grid.map { makeCenterKey($0[column]) }))
        }
        columns.addArrangedSubview(buildRightColumn())

        columns.translatesAutoresizingMaskIntoConstraints = false
        keyContainer.addSubview(columns)
        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: keyContainer.leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: keyContainer.trailingAnchor),
            columns.topAnchor.constraint(equalTo: keyContainer.topAnchor),
            columns.bottomAnchor.constraint(equalTo: keyContainer.bottomAnchor)
        ])
    }

    private func verticalStack(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        stack.spacing = Self.keySpacing
        stack.distribution = .fillEqually
        return stack
    }

    /// One key per mode, the current one lit, as on the iPhone's
    /// フリックのみ layout. The bottom slot is where the stock emoji/globe
    /// key sits; iOS already draws its own globe below the keyboard, so it
    /// stays blank here.
    private func buildLeftColumn() -> UIStackView {
        var keys: [UIView] = [KeyboardMode.number, .alphabet, .kana].map { target in
            let key = makeKey(title: target.title) { [weak self] in self?.switchMode(to: target) }
            if target == mode { key.backgroundColor = KeyColors.character }
            return key
        }
        keys.append(makeBlankKey(color: KeyColors.function))
        return verticalStack(keys)
    }

    private func buildRightColumn() -> UIStackView {
        let backspace = makeKey(title: "⌫") { [weak self] in self?.stopBackspaceRepeat() }
        backspace.addAction(UIAction { [weak self] _ in self?.startBackspaceRepeat() }, for: .touchDown)
        backspace.addAction(UIAction { [weak self] _ in self?.stopBackspaceRepeat() }, for: [.touchUpOutside, .touchCancel])

        // Same shape as the stock 空白, but blank and inert.
        let space = makeBlankKey(color: KeyColors.character)
        // Always a plain line break, even where the stock key would read
        // 検索 or 送信 and submit the field instead.
        let returnKey = makeKey(title: "改行") { [weak self] in self?.insertNewline() }

        let stack = UIStackView(arrangedSubviews: [backspace, space, returnKey])
        stack.axis = .vertical
        stack.spacing = Self.keySpacing
        stack.distribution = .fill
        NSLayoutConstraint.activate([
            space.heightAnchor.constraint(equalTo: backspace.heightAnchor),
            returnKey.heightAnchor.constraint(equalTo: backspace.heightAnchor, multiplier: 2, constant: Self.keySpacing)
        ])
        return stack
    }

    private func makeCenterKey(_ slot: CenterKey) -> UIView {
        switch slot {
        case .flick(let key):
            let button = FlickKeyButton(key: key)
            button.onPreview = { [weak self] button, direction in
                self?.showFlickPreview(for: button, direction: direction)
            }
            button.onCommit = { [weak self] button, direction, isTap in
                self?.handleFlick(button.key, direction: direction, isTap: isTap)
            }
            return button
        case .modifier(let label):
            let button = makeKey(title: label) { [weak self] in self?.handleModifier() }
            button.backgroundColor = KeyColors.character
            button.titleLabel?.font = .systemFont(ofSize: 17)
            return button
        }
    }

    /// A plain function key (gray, like the iPhone's side columns).
    private func makeKey(title: String, action: (() -> Void)?) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.label, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.6
        button.backgroundColor = KeyColors.function
        styleKeyShape(button)
        if let action {
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
        return button
    }

    /// A key-shaped placeholder: keeps the stock layout's outline where
    /// this keyboard has no key.
    private func makeBlankKey(color: UIColor) -> UIView {
        let blank = UIView()
        blank.backgroundColor = color
        blank.isUserInteractionEnabled = false
        styleKeyShape(blank)
        return blank
    }

    private func styleKeyShape(_ key: UIView) {
        key.layer.cornerRadius = 6
        key.layer.shadowColor = UIColor.black.cgColor
        key.layer.shadowOpacity = 0.3
        key.layer.shadowRadius = 0
        key.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    // MARK: - One-handed layout

    /// The chevron in the empty strip beside the shrunken keys; tapping it
    /// goes back to the full-width keyboard, as on iPhone.
    private func setUpChevrons() {
        for (chevron, symbol) in [(leftChevron, "chevron.compact.left"), (rightChevron, "chevron.compact.right")] {
            chevron.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)), for: .normal)
            chevron.tintColor = .secondaryLabel
            chevron.addAction(UIAction { [weak self] _ in self?.setHandedness(.full) }, for: .touchUpInside)
            chevron.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(chevron)
            NSLayoutConstraint.activate([
                chevron.widthAnchor.constraint(equalToConstant: Self.oneHandedGutter),
                chevron.topAnchor.constraint(equalTo: keyContainer.topAnchor),
                chevron.bottomAnchor.constraint(equalTo: keyContainer.bottomAnchor)
            ])
        }
        leftChevron.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        rightChevron.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
    }

    private func applyHandedness() {
        let inset = Self.edgeInset
        let gutter = Self.oneHandedGutter
        keyLeading.constant = handedness == .right ? gutter : inset
        keyTrailing.constant = handedness == .left ? -gutter : -inset
        leftChevron.isHidden = handedness != .right
        rightChevron.isHidden = handedness != .left
    }

    private func setHandedness(_ newValue: KeyboardHandedness) {
        handedness = newValue
        handedness.save()
        if currentWord.isEmpty { candidateStrip.showHandednessPicker(current: handedness) }
        UIView.animate(withDuration: 0.2) {
            self.applyHandedness()
            self.view.layoutIfNeeded()
        }
    }

    /// The bubble showing which character a flick will type, drawn beside
    /// the key in the flick's direction (or over it, for the center).
    private func showFlickPreview(for button: FlickKeyButton, direction: FlickDirection?) {
        guard let direction, let text = button.key.character(for: direction) else {
            flickPreview.isHidden = true
            return
        }
        var frame = button.convert(button.bounds, to: view)
        switch direction {
        case .center: break
        case .left: frame.origin.x -= frame.width
        case .right: frame.origin.x += frame.width
        case .up: frame.origin.y -= frame.height
        case .down: frame.origin.y += frame.height
        }
        // Keyboard extensions can't draw outside their own view.
        frame.origin.x = min(max(frame.origin.x, 0), view.bounds.width - frame.width)
        frame.origin.y = min(max(frame.origin.y, 0), view.bounds.height - frame.height)
        flickPreview.frame = frame
        flickPreview.text = text
        flickPreview.isHidden = false
        view.bringSubviewToFront(flickPreview)
    }

    // MARK: - Key handling

    private func handleFlick(_ key: FlickKey, direction: FlickDirection, isTap: Bool) {
        if isTap, !flickOnly, let toggle, toggle.key.label == key.label,
           Date().timeIntervalSince(toggle.time) < Self.toggleTimeout {
            let index = (toggle.index + 1) % key.cycle.count
            replaceLastCharacter(with: key.cycle[index])
            self.toggle = (key: key, index: index, time: Date())
            return
        }
        guard let character = key.character(for: direction) else {
            toggle = nil
            return
        }
        typeCharacter(character)
        toggle = isTap && !flickOnly ? (key: key, index: 0, time: Date()) : nil
    }

    /// 小゛゜ / a/A: transform the character just before the cursor.
    private func handleModifier() {
        toggle = nil
        guard let last = textDocumentProxy.documentContextBeforeInput?.last,
              let next = CharacterModifier.next(after: last, in: mode) else { return }
        replaceLastCharacter(with: String(next))
    }

    private func switchMode(to newMode: KeyboardMode) {
        toggle = nil
        mode = newMode
        rebuildKeys()
    }

    private func handleBackspace() {
        toggle = nil
        textDocumentProxy.deleteBackward()
        guard !currentWord.isEmpty else { return }
        currentWord.removeLast()
        updateCandidates(for: currentWord)
    }

    private func startBackspaceRepeat() {
        handleBackspace()
        backspaceRepeat?.invalidate()
        backspaceRepeat = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.backspaceRepeat = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.handleBackspace() }
                }
            }
        }
    }

    private func stopBackspaceRepeat() {
        backspaceRepeat?.invalidate()
        backspaceRepeat = nil
    }

    // MARK: - Typing and word search

    private func typeCharacter(_ character: String) {
        textDocumentProxy.insertText(character)
        trackTyped(character)
    }

    private func insertNewline() {
        toggle = nil
        textDocumentProxy.insertText("\n")
        endWord()
    }

    private func replaceLastCharacter(with character: String) {
        textDocumentProxy.deleteBackward()
        if !currentWord.isEmpty { currentWord.removeLast() }
        typeCharacter(character)
    }

    private func trackTyped(_ characters: String) {
        let isPunctuation = characters.unicodeScalars.allSatisfy(CharacterSet.punctuationCharacters.contains)
        guard EmojiSearchPolicy.isSearchableCharacter(characters), !isPunctuation else {
            endWord()
            return
        }
        currentWord += characters
        updateCandidates(for: currentWord)
    }

    private func updateCandidates(for query: String) {
        guard !query.isEmpty else {
            candidateStrip.showHandednessPicker(current: handedness)
            return
        }
        candidateStrip.update(candidates: EmojiSuggestions.candidates(for: query))
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
        candidateStrip.setLoading(true)
        Task { [weak self] in
            guard let self else { return }
            defer {
                // Only the newest request owns the dots; an older one
                // finishing late mustn't hide them early.
                if self.searchGeneration == generation { self.candidateStrip.setLoading(false) }
            }
            do {
                let ranked = try await self.jev.rank(
                    query: query, context: nil,
                    entries: EmojiCatalog.shared.searchableEntries, apiKey: apiKey
                )
                guard self.searchGeneration == generation, self.currentWord == query else { return }
                self.jevPacer.recordSuccess()
                // An empty ranking would blank the strip; keep what's there.
                guard !ranked.isEmpty else { return }
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
        // Orphan any in-flight Jev request so it can't touch the strip.
        searchGeneration += 1
        candidateStrip.showHandednessPicker(current: handedness)
    }
}

extension KeyboardViewController: EmojiCandidateStripViewDelegate {
    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect entry: EmojiEntry) {
        toggle = nil
        EmojiSuggestions.recordPick(entry)
        // Replace the typed word (if any) with the emoji.
        for _ in 0..<currentWord.count {
            textDocumentProxy.deleteBackward()
        }
        textDocumentProxy.insertText(entry.emoji)
        endWord()
    }

    func candidateStrip(_ stripView: EmojiCandidateStripView, didSelect handedness: KeyboardHandedness) {
        setHandedness(handedness)
    }
}
