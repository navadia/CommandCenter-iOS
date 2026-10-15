import Foundation
import Security

/// Storage shared by the app and the widget.
///
/// SideStore (like AltStore) renames App Group IDs when it signs the app by
/// appending your team ID, and records the real IDs in the `ALTAppGroups`
/// key of Info.plist. We read that key first so the app and widget always
/// agree on the container.
enum SharedStore {
    static let fallbackGroup = "group.com.navadia.commandcenter"

    static var groupID: String {
        if let groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String],
           let first = groups.first {
            return first
        }
        return fallbackGroup
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static var isGroupWorking: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    // MARK: - Snapshot (last good list, so the widget always has something)

    static var snapshot: [Item] {
        guard let data = defaults.data(forKey: "snapshot"),
              let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }
        return items
    }

    static var snapshotDate: Date? {
        defaults.object(forKey: "snapshotDate") as? Date
    }

    static func saveSnapshot(_ items: [Item]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: "snapshot")
        defaults.set(Date.now, forKey: "snapshotDate")
    }

    static func removeFromSnapshot(_ id: String) {
        saveSnapshot(snapshot.filter { $0.id != id })
    }
}

/// The Notion token lives in the Keychain, shared with the widget through the
/// App Group (an App Group ID doubles as a Keychain access group). If the
/// Keychain refuses the shared group, it falls back to the App Group's
/// private storage, which only this app and its widget can read.
enum TokenStore {
    private static let service = "com.navadia.commandcenter.notion"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccessGroup as String: SharedStore.groupID]
    }

    static func load() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty {
            return token
        }
        let fallback = SharedStore.defaults.string(forKey: "notionTokenFallback")
        return (fallback?.isEmpty ?? true) ? nil : fallback
    }

    /// Returns where the token was stored, for the Settings screen.
    @discardableResult
    static func save(_ token: String) -> String {
        SecItemDelete(query() as CFDictionary)
        var q = query()
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(q as CFDictionary, nil) == errSecSuccess {
            SharedStore.defaults.removeObject(forKey: "notionTokenFallback")
            return "Keychain"
        }
        SharedStore.defaults.set(token, forKey: "notionTokenFallback")
        return "App Group"
    }

    static func delete() {
        SecItemDelete(query() as CFDictionary)
        SharedStore.defaults.removeObject(forKey: "notionTokenFallback")
    }
}
