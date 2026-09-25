import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import os

/// The kana being composed (未確定文字) and its kanji conversions, backed by
/// AzooKeyKanaKanjiConverter's on-device dictionary — nothing typed here
/// leaves the device.
///
/// The reading updates immediately on every keystroke; conversions are
/// computed off the main thread and arrive through `onCandidatesChanged`,
/// so typing never waits on the dictionary.
@MainActor
final class KanaKanjiEngine {
    private let worker = ConversionWorker()
    private var composing = ComposingText()
    private var candidates: [Candidate] = []
    private var generation = 0

    /// Called on the main thread when `candidateTexts` catches up with the
    /// reading.
    var onCandidatesChanged: (() -> Void)?

    /// The hiragana typed so far, e.g. "きょうは".
    var reading: String { composing.convertTarget }
    var isComposing: Bool { !composing.isEmpty }
    /// The conversions for the reading, best first (猫, ねこ, ネコ …).
    var candidateTexts: [String] { candidates.map(\.text) }
    /// Conversions of exactly the reading (ほし → 星, 干し), without the
    /// predictions that run past it (欲しい): learned predictions can fill
    /// the top of the list and push the plain words out of emoji search.
    var readingConversions: [String] {
        let length = composing.convertTarget.count
        let exact = candidates.filter { $0.rubyCount == length }.map(\.text)
        return exact.isEmpty ? candidateTexts : exact
    }
    /// False between a keystroke and its conversions arriving; picks made
    /// in that gap would apply to the previous reading.
    private(set) var candidatesAreCurrent = true

    /// Open the dictionary in the background before the first keystroke.
    func warmUp() {
        worker.warmUp()
    }

    func insert(_ text: String) {
        composing.insertAtCursorPosition(text, inputStyle: .direct)
        refresh()
    }

    /// Swap the last kana for another (トグル input, 小゛゜) in one refresh.
    func replaceLast(with text: String) {
        composing.deleteBackwardFromCursorPosition(count: 1)
        composing.insertAtCursorPosition(text, inputStyle: .direct)
        refresh()
    }

    func deleteBackward() {
        composing.deleteBackwardFromCursorPosition(count: 1)
        refresh()
    }

    /// What the document should show if the candidate at `index` were
    /// picked: its text plus whatever reading it doesn't cover yet (a
    /// first-clause candidate like 今日 for きょうはいい leaves はいい).
    func preview(at index: Int) -> String {
        guard candidatesAreCurrent, candidates.indices.contains(index) else { return reading }
        let candidate = candidates[index]
        var rest = composing
        rest.prefixComplete(composingCount: candidate.composingCount)
        return candidate.text + rest.convertTarget
    }

    /// Commit the candidate at `index` and return its text; any reading it
    /// didn't cover stays composing.
    @discardableResult
    func complete(at index: Int) -> String? {
        guard candidatesAreCurrent, candidates.indices.contains(index) else { return nil }
        let candidate = candidates[index]
        worker.complete(candidate)
        composing.prefixComplete(composingCount: candidate.composingCount)
        if composing.isEmpty {
            reset()
        } else {
            refresh()
        }
        return candidate.text
    }

    /// Drop the composition (after committing it as-is, or on an emoji) and
    /// save what was learned.
    func reset() {
        composing = ComposingText()
        candidates = []
        candidatesAreCurrent = true
        generation += 1
        worker.stop(saveLearning: true)
    }

    private func refresh() {
        generation += 1
        guard !composing.isEmpty else {
            candidates = []
            candidatesAreCurrent = true
            worker.stop(saveLearning: false)
            return
        }
        candidatesAreCurrent = false
        let expected = generation
        worker.requestCandidates(for: composing, generation: expected) { [weak self] results in
            guard let self, self.generation == expected else { return }
            self.candidates = results
            self.candidatesAreCurrent = true
            self.onCandidatesChanged?()
        }
    }
}

/// Owns the converter on one serial queue: its lattice cache assumes calls
/// arrive in order, and keeping it off the main thread keeps keys snappy.
private final class ConversionWorker: @unchecked Sendable {
    private static let maxCandidates = 12

    private let queue = DispatchQueue(label: "Emojichao.KanaKanji", qos: .userInitiated)
    /// Touched only on `queue`.
    private var converter: KanaKanjiConverter?
    /// The newest request; queued requests older than this are skipped, so
    /// fast typing only converts what's still on screen.
    private let latestGeneration = OSAllocatedUnfairLock(initialState: 0)

    func warmUp() {
        queue.async { _ = self.loadedConverter() }
    }

    func requestCandidates(
        for composing: ComposingText,
        generation: Int,
        completion: @escaping @MainActor @Sendable ([Candidate]) -> Void
    ) {
        latestGeneration.withLock { $0 = generation }
        queue.async {
            guard self.latestGeneration.withLock({ $0 }) == generation else { return }
            var seen = Set<String>()
            let results = self.loadedConverter()
                .requestCandidates(composing, options: Self.options)
                .mainResults
                // Emoji have their own row; keep this one to words.
                .filter { !Self.isEmojiOnly($0.text) && seen.insert($0.text).inserted }
                .prefix(Self.maxCandidates)
            let candidates = Array(results)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(candidates) }
            }
        }
    }

    func complete(_ candidate: Candidate) {
        queue.async {
            let converter = self.loadedConverter()
            converter.setCompletedData(candidate)
            converter.updateLearningData(candidate)
        }
    }

    func stop(saveLearning: Bool) {
        queue.async {
            guard let converter = self.converter else { return }
            converter.stopComposition()
            if saveLearning { converter.commitUpdateLearningData() }
        }
    }

    private static func isEmojiOnly(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { character in
            let scalars = character.unicodeScalars
            guard let first = scalars.first, first.properties.isEmoji else { return false }
            // Digits and # are "emoji" too; count them only as keycaps.
            return first.properties.isEmojiPresentation || scalars.count > 1
        }
    }

    /// Opened on first use: loading the dictionary costs memory, and a
    /// keyboard that's only used for ABC/☆123 shouldn't pay it.
    private func loadedConverter() -> KanaKanjiConverter {
        if let converter { return converter }
        let converter = KanaKanjiConverter.withDefaultDictionary()
        self.converter = converter
        return converter
    }

    private static let options: ConvertRequestOptions = {
        // Learning data lives in the App Group so it survives the extension
        // being torn down; fall back to the extension's own caches.
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: JevKeyStore.appGroupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let memory = base.appendingPathComponent("KanaKanji", isDirectory: true)
        try? FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
        return ConvertRequestOptions(
            requireJapanesePrediction: true,
            requireEnglishPrediction: false,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: memory,
            sharedContainerURL: memory,
            textReplacer: .empty,
            specialCandidateProviders: nil,
            metadata: .init(versionString: "Emojichao")
        )
    }()
}
