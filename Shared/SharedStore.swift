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

/// A secret in the Keychain, shared with the widget through the App Group
/// (an App Group ID doubles as a Keychain access group). If the Keychain
/// refuses the shared group, it falls back to the App Group's private
/// storage, which only this app and its widget can read.
struct KeychainSecret: Sendable {
    let service: String
    let fallbackKey: String

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccessGroup as String: SharedStore.groupID]
    }

    func load() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
           let data = out as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        let fallback = SharedStore.defaults.string(forKey: fallbackKey)
        return (fallback?.isEmpty ?? true) ? nil : fallback
    }

    /// Returns where the value was stored, for the Settings screen.
    @discardableResult
    func save(_ value: String) -> String {
        SecItemDelete(query() as CFDictionary)
        var q = query()
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(q as CFDictionary, nil) == errSecSuccess {
            SharedStore.defaults.removeObject(forKey: fallbackKey)
            return "Keychain"
        }
        SharedStore.defaults.set(value, forKey: fallbackKey)
        return "App Group"
    }

    func delete() {
        SecItemDelete(query() as CFDictionary)
        SharedStore.defaults.removeObject(forKey: fallbackKey)
    }
}

/// The Notion token (app + widget).
enum TokenStore {
    private static let secret = KeychainSecret(service: "com.navadia.commandcenter.notion",
                                               fallbackKey: "notionTokenFallback")

    static func load() -> String? { secret.load() }

    @discardableResult
    static func save(_ token: String) -> String { secret.save(token) }

    static func delete() { secret.delete() }
}

/// Sign-in for the hub Gmail, used only to open emails inside the app.
/// The address sits in the App Group defaults; the app password in the Keychain.
struct GmailCredentials: Sendable {
    let address: String
    let password: String

    private static let secret = KeychainSecret(service: "com.navadia.commandcenter.gmail",
                                               fallbackKey: "gmailPasswordFallback")

    static var savedAddress: String {
        SharedStore.defaults.string(forKey: "gmailAddress") ?? ""
    }

    static func load() -> GmailCredentials? {
        let address = savedAddress
        guard !address.isEmpty, let password = secret.load() else { return nil }
        return GmailCredentials(address: address, password: password)
    }

    static func saveAddress(_ address: String) {
        SharedStore.defaults.set(address, forKey: "gmailAddress")
    }

    /// Google shows app passwords as "abcd efgh ijkl mnop"; IMAP wants them without spaces.
    static func clean(_ password: String) -> String {
        password.filter { !$0.isWhitespace }
    }

    static func savePassword(_ password: String) {
        secret.save(clean(password))
    }

    static func delete() {
        secret.delete()
    }
}
