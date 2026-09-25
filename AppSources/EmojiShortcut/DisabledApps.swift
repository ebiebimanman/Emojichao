import Foundation

// Apps where the ':' trigger must stay out of the way. Slack and other chat
// clients open their own emoji picker on ':', and two pickers racing over the
// same keystroke leave the wrong text in the message box.
enum DisabledApps {
    static let defaultsKey = "DisabledAppBundleIdentifiers"
    static let didChangeNotification = Notification.Name("EmojichaoDisabledAppsDidChange")

    /// Bundle identifiers are compared case-insensitively, but the stored
    /// spelling is kept so the settings list can show it when the app is not
    /// installed on this Mac.
    static func canonical(_ bundleIdentifier: String?) -> String? {
        guard let trimmed = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func identifiers(using defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.array(forKey: defaultsKey) as? [String] ?? []
        var seen: Set<String> = []
        return stored.compactMap(canonical).filter { seen.insert($0.lowercased()).inserted }
    }

    static func isDisabled(
        _ bundleIdentifier: String?, using defaults: UserDefaults = .standard
    ) -> Bool {
        guard let identifier = canonical(bundleIdentifier)?.lowercased() else { return false }
        return identifiers(using: defaults).contains { $0.lowercased() == identifier }
    }

    @discardableResult
    static func setDisabled(
        _ disabled: Bool,
        for bundleIdentifier: String?,
        using defaults: UserDefaults = .standard
    ) -> [String] {
        guard let identifier = canonical(bundleIdentifier) else {
            return identifiers(using: defaults)
        }
        var identifiers = identifiers(using: defaults)
        let key = identifier.lowercased()
        if disabled {
            guard !identifiers.contains(where: { $0.lowercased() == key }) else {
                return identifiers
            }
            identifiers.append(identifier)
        } else {
            let remaining = identifiers.filter { $0.lowercased() != key }
            guard remaining.count != identifiers.count else { return identifiers }
            identifiers = remaining
        }
        store(identifiers, using: defaults)
        return identifiers
    }

    private static func store(_ identifiers: [String], using defaults: UserDefaults) {
        defaults.set(identifiers, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
