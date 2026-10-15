import Foundation

/// Data shared between the app and the widget through an App Group.
///
/// SideStore (like AltStore) rewrites App Group IDs when it signs the app,
/// usually by appending your team ID, and records the real IDs in the
/// `ALTAppGroups` key of Info.plist. We read that key first so the app and
/// widget always agree on the container, whatever SideStore renamed it to.
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

    /// True when the App Group container really exists (the key test result).
    static var isGroupWorking: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    // MARK: - Test values

    static var appOpenedAt: Date? {
        get { defaults.object(forKey: "appOpenedAt") as? Date }
        set { defaults.set(newValue, forKey: "appOpenedAt") }
    }

    static var widgetTaps: Int {
        get { defaults.integer(forKey: "widgetTaps") }
        set { defaults.set(newValue, forKey: "widgetTaps") }
    }
}
