import Foundation

/// One category (venture) from the Notion "Categories" table. The parser
/// routes email by its rules; the app shows it with its icon and color.
struct Category: Codable, Identifiable, Hashable, Sendable {
    var id: String              // Notion page id ("" until created)
    var name: String            // the Venture value on Command Center rows
    var rules: [Rule] = []
    var order: Int = 50
    var icon: String = ""       // SF Symbol; blank = the standard one for this name
    var color: String = ""      // palette name; blank = the standard one
    var about: String = ""      // one sentence for Apple Intelligence

    struct Rule: Codable, Hashable, Sendable, Identifiable {
        enum Kind: String, Codable, CaseIterable, Sendable { case from, to, subject }
        var id = UUID()
        var kind: Kind
        var needle: String

        var line: String { "\(kind.rawValue): \(needle)" }

        /// "to: store" -> Rule; nil for anything else.
        init?(line: String) {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let kind = Kind(rawValue: parts[0].lowercased()), !parts[1].isEmpty else { return nil }
            self.kind = kind
            self.needle = parts[1]
        }

        init(kind: Kind, needle: String) {
            self.kind = kind
            self.needle = needle
        }

        enum CodingKeys: String, CodingKey { case kind, needle }
    }

    static func rules(from text: String) -> [Rule] {
        text.split(whereSeparator: \.isNewline).compactMap { Rule(line: String($0)) }
    }

    var rulesText: String { rules.map(\.line).joined(separator: "\n") }
}

/// The list as last read from Notion, kept in the App Group so the widget and
/// a cold start have it too. Reading it registers SwiftUI observation (via
/// ColorPicks), so styles redraw when it changes.
enum CategoryStore {
    private static let key = "categories"

    static var all: [Category] {
        _ = ColorPicks.shared.version
        guard let data = SharedStore.defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Category].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [Category]) {
        let sorted = list.sorted { ($0.order, $0.name) < ($1.order, $1.name) }
        SharedStore.defaults.set(try? JSONEncoder().encode(sorted), forKey: key)
        ColorPicks.shared.version += 1
    }

    static func find(_ name: String) -> Category? {
        all.first { $0.name == name }
    }

    /// Icons offered when adding a category.
    static let icons = [
        "storefront.fill", "bed.double.fill", "chart.line.uptrend.xyaxis", "briefcase.fill", "building.columns.fill",
        "person.fill", "house.fill", "figure.2.and.child.holdinghands", "airplane", "car.fill", "bag.fill",
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "heart.fill", "cross.case.fill", "graduationcap.fill",
        "book.fill", "hammer.fill", "wrench.and.screwdriver.fill", "creditcard.fill", "dollarsign.circle.fill",
        "gift.fill", "gamecontroller.fill", "play.tv.fill", "music.note", "pawprint.fill", "leaf.fill",
        "bolt.fill", "phone.fill", "envelope.fill", "star.fill", "tray.fill", "eye.slash.fill",
    ]
}
