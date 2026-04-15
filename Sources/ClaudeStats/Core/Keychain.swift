import Foundation

/// Stored in UserDefaults (plaintext in the app's preferences plist).
/// Simpler than Keychain — no permission prompts — at the cost of encryption-at-rest.
enum Keychain {
    private static let prefix = "claudestats."

    static func set(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }

    static func get(_ key: String) -> String? {
        UserDefaults.standard.string(forKey: prefix + key)
    }

    static func remove(_ key: String) {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}
