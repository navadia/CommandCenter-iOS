import Foundation
import Security

/// Storage shared by the app and the widget.
///
/// SideStore (like AltStore) renames App Group IDs when it signs the app,
/// usually by appending your team ID, and is meant to record the real IDs in
/// the `ALTAppGroups` key of Info.plist. Some SideStore builds don't update
/// that key, so we also read the groups this copy was actually signed with
/// (the provisioning profile inside the app) and use the first one iOS
/// really opens. The app and the widget each do this and land on the same one.
enum SharedStore {
    static let fallbackGroup = "group.com.navadia.commandcenter"

    static let groupID: String = {
        let candidates = infoPlistGroups + profileGroups + [fallbackGroup]
        return candidates.first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? candidates.first ?? fallbackGroup
    }()

    /// What Settings shows when shared storage isn't working.
    static var groupDiagnostics: String {
        let list = { (groups: [String]) in groups.isEmpty ? "none" : groups.joined(separator: ", ") }
        return "Using \(groupID). Info.plist: \(list(infoPlistGroups)). Signed with: \(list(profileGroups))."
    }

    private static var infoPlistGroups: [String] {
        Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
    }

    /// The App Groups in embedded.mobileprovision (a signed plist).
    private static var profileGroups: [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return [] }
        return groups
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
