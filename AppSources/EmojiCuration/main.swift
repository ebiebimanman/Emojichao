import AppKit
import Foundation
import Carbon.HIToolbox

struct EmojiEntry: Codable {
    let emoji: String
    let name: String
    let englishName: String
    let keywords: [String]
}

@MainActor
final class CurationModel {
    let entries: [EmojiEntry]
    private(set) var decisions: [String: Bool]
    private(set) var history: [(String, Bool)] = []
    private let catalogURL: URL
    private let decisionsURL: URL
    private let curatedURL: URL
    private let sharedCuratedURL: URL

    var current: EmojiEntry? {
        entries.first { decisions[$0.emoji] == nil }
    }

    var decidedCount: Int { decisions.count }

    init() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = projectRoot.appendingPathComponent("AppSources/EmojiShortcut/Resources")
        catalogURL = resources.appendingPathComponent("emoji-catalog.json")
        decisionsURL = projectRoot.appendingPathComponent("emoji-curation-decisions.json")
        curatedURL = resources.appendingPathComponent("emoji-catalog-curated.json")
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EmojiShortcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        sharedCuratedURL = appSupport.appendingPathComponent("emoji-catalog-curated.json")
        let data = try Data(contentsOf: catalogURL)
        entries = try JSONDecoder().decode([EmojiEntry].self, from: data)
        if let saved = try? Data(contentsOf: decisionsURL),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: saved) {
            decisions = decoded
        } else {
            decisions = [:]
        }
    }

    func decide(_ keep: Bool) {
        guard let entry = current else { return }
        decisions[entry.emoji] = keep
        history.append((entry.emoji, keep))
        saveDecisions()
        if current == nil { apply() }
    }

    func undo() {
        guard let last = history.popLast() else { return }
        decisions.removeValue(forKey: last.0)
        saveDecisions()
    }

    func apply() {
        let kept = entries.filter { decisions[$0.emoji] == true }
        guard let data = try? JSONEncoder.pretty.encode(kept) else { return }
        try? data.write(to: curatedURL, options: .atomic)
        try? data.write(to: sharedCuratedURL, options: .atomic)
    }

    private func saveDecisions() {
        guard let data = try? JSONEncoder.pretty.encode(decisions) else { return }
        try? data.write(to: decisionsURL, options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

@MainActor
final class CurationView: NSView {
    let model: CurationModel
    private let emojiLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let helpLabel = NSTextField(labelWithString: "← 除外    → 残す    ↑ 取り消し")

    init(model: CurationModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        [emojiLabel, nameLabel, progressLabel, helpLabel].forEach {
            $0.alignment = .center
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        emojiLabel.font = .systemFont(ofSize: 150)
        nameLabel.font = .boldSystemFont(ofSize: 26)
        progressLabel.textColor = .secondaryLabelColor
        helpLabel.textColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -55),
            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: emojiLabel.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 16),
            helpLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            helpLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -28)
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case UInt16(kVK_LeftArrow): model.decide(false)
        case UInt16(kVK_RightArrow): model.decide(true)
        case UInt16(kVK_UpArrow): model.undo()
        default: super.keyDown(with: event); return
        }
        update()
    }

    func update() {
        if let entry = model.current {
            emojiLabel.stringValue = entry.emoji
            nameLabel.stringValue = "(entry.name)  ·  (entry.englishName)"
            progressLabel.stringValue = "(model.decidedCount) / (model.entries.count)"
        } else {
            emojiLabel.stringValue = "✅"
            nameLabel.stringValue = "仕分け完了"
            progressLabel.stringValue = "残す絵文字をアプリの候補リストへ反映しました"
        }
    }
}

@MainActor
final class CurationApp: NSObject, NSApplicationDelegate {
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let model = try CurationModel()
            let view = CurationView(model: model)
            window = NSWindow(contentRect: view.bounds, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "EmojiShortcut 絵文字仕分け"
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }
}

@main
@MainActor
struct CurationMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = CurationApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}
