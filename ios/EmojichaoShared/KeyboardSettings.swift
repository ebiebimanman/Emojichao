import Foundation

/// Keyboard options chosen in the container app and read by the keyboard
/// extension, shared through the same App Group as JevKeyStore.
///
/// Like JevKeyStore.swift, this file belongs to BOTH targets.
enum KeyboardSettings {
    /// Matches the iPhone's own "フリックのみ" setting: taps never cycle
    /// (か → き); tapping twice types the character twice.
    static let flickOnlyKey = "FlickOnly"
    static let flickOnlyDefault = true

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: JevKeyStore.appGroupID)
    }

    static var flickOnly: Bool {
        defaults?.object(forKey: flickOnlyKey) as? Bool ?? flickOnlyDefault
    }
}
