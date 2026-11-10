import Foundation

/// One row of the "FYI Mail" table: mail the sorter filed as not needing you
/// (receipts, notices, sign-ins). Shown on the FYI screen, never on Today.
struct FYIMail: Identifiable, Codable, Hashable, Sendable {
    let id: String            // Notion page id
    let title: String         // "Sender: Subject" (or just the subject)
    let from: String          // parser's "Sender name | destination"
    let venture: String
    let received: Date?
    let link: String?
    let messageID: String?
    let security: Bool        // account / sign-in notice
    let paid: Bool            // a payment receipt
    let count: Int            // repeats merged into this row the same day
    let domain: String?

    var sender: String {
        let name = from.split(separator: "|").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty ? (asItem.sender) : name
    }

    var subject: String {
        if title.hasPrefix(sender + ": ") { return String(title.dropFirst(sender.count + 2)) }
        if let r = title.range(of: ": "), title.distance(from: title.startIndex, to: r.lowerBound) <= 40 {
            return String(title[r.upperBound...])          // "Robinhood Credit Card: Thank you…"
        }
        return title
    }

    /// The same mail as an Item, so the shared avatar and email screen work on it.
    /// The "mail-" id marks it as not a Command Center row (no Mark Done).
    var asItem: Item {
        Item(id: "mail-\(id)", title: title, type: "todo", venture: venture, amount: nil, due: nil,
             trial: false, link: link, domain: domain, created: nil, source: from)
    }

    init(id: String, title: String, from: String, venture: String, received: Date?, link: String?,
         messageID: String?, security: Bool = false, paid: Bool = false, count: Int = 1, domain: String?) {
        self.id = id; self.title = title; self.from = from; self.venture = venture; self.received = received
        self.link = link; self.messageID = messageID; self.security = security; self.paid = paid
        self.count = count; self.domain = domain
    }

    init?(page: [String: Any]) {
        guard let id = page["id"] as? String, let p = page["properties"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String {
            let v = p[key] as? [String: Any]
            let parts = (v?["title"] ?? v?["rich_text"]) as? [[String: Any]] ?? []
            return parts.compactMap { $0["plain_text"] as? String }.joined()
        }
        func check(_ key: String) -> Bool { (p[key] as? [String: Any])?["checkbox"] as? Bool ?? false }
        let created = (page["created_time"] as? String).flatMap { ISO8601DateFormatter.notion.date(from: $0) }
        let fingerprint = text("Fingerprint")
        self.init(
            id: id,
            title: text("Title").isEmpty ? "(no subject)" : text("Title"),
            from: text("From"),
            venture: ((p["Venture"] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String ?? "Personal",
            received: created,
            link: (p["Link"] as? [String: Any])?["url"] as? String,
            messageID: text("MsgID").isEmpty ? nil : text("MsgID"),
            security: check("Security"),
            paid: check("Paid"),
            count: (p["Count"] as? [String: Any])?["number"] as? Int ?? 1,
            domain: fingerprint.split(separator: "|").first.map(String.init).flatMap { $0.contains(".") ? $0 : nil }
        )
    }
}

extension ISO8601DateFormatter {
    /// Notion's created_time: "2026-11-10T14:37:00.000Z".
    nonisolated(unsafe) static let notion: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
