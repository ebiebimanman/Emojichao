import Foundation

/// Shares the Jev API key between the container app (where it's entered)
/// and the keyboard extension (where it's used), via an App Group.
///
/// Requires the "App Groups" capability added to BOTH the container app
/// target and the keyboard extension target in Xcode (Signing &
/// Capabilities), with the exact same group ID entered in both. Update
/// `appGroupID` below to match whatever you create there.
///
/// Add this one file to BOTH targets' membership (unlike the other files in
/// ios/, which belong to only one target each).
enum JevKeyStore {
    static let appGroupID = "group.com.ebiebimanman.emojichao"
    private static let key = "JevAPIKey"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func read() -> String? {
        defaults?.string(forKey: key)
    }

    static func save(_ apiKey: String) {
        defaults?.set(apiKey, forKey: key)
    }

    static func clear() {
        defaults?.removeObject(forKey: key)
    }
}
