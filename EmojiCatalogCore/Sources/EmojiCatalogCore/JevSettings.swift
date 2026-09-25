import Foundation

public enum JevSearchMode: String {
    case context
    case text
}

public enum JevSettings {
    public static let searchModeKey = "JevSearchMode"
    private static let legacySendPrecedingTextKey = "SendPrecedingTextToJev"

    public static func searchMode(using defaults: UserDefaults = .standard) -> JevSearchMode {
        if let value = defaults.string(forKey: searchModeKey),
           let mode = JevSearchMode(rawValue: value) {
            return mode
        }
        if let legacyValue = defaults.object(forKey: legacySendPrecedingTextKey) as? Bool {
            return legacyValue ? .context : .text
        }
        return .text
    }

    public static func setSearchMode(_ mode: JevSearchMode, using defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: searchModeKey)
    }
}
