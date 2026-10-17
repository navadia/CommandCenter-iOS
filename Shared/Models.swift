import Foundation
import SwiftUI

/// One open row from the Command Center database.
struct Item: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let type: String          // money, travel, todo
    let venture: String
    let amount: Double?
    let due: String?          // yyyy-MM-dd or full ISO date
    let trial: Bool
    let link: String?
    var domain: String? = nil     // sender's site, from the parser's Fingerprint ("geico.com|…")
    var created: String? = nil    // Notion created_time (ISO 8601)

    var isPower: Bool { title.unicodeScalars.first == "\u{26A1}" }
    /// The parser's own bookkeeping row ("⚙️ Digest sent …"), never shown.
    var isInternal: Bool { title.unicodeScalars.first == "\u{2699}" }

    /// "GEICO - geico at e.geico.com: See…" -> "GEICO: See…" (old SimpleLogin titles)
    var cleanTitle: String { Item.tidy(title) }

    /// "GEICO: Your payment is due" -> ("GEICO", "Your payment is due").
    var sender: String { parts.sender }
    var subject: String { parts.subject }
    var initial: String { sender.first.map { String($0).uppercased() } ?? "•" }

    private var parts: (sender: String, subject: String) {
        let t = cleanTitle
        if let r = t.range(of: ": ") {
            let s = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty, s.count <= 40 { return (s, String(t[r.upperBound...])) }
        }
        return (t, "")
    }

    var daysUntilDue: Int? {
        guard let due, due.count >= 10, let date = Item.dayFormatter.date(from: String(due.prefix(10))) else {
            return nil
        }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: cal.startOfDay(for: date)).day
    }

    var dueText: String? {
        guard let d = daysUntilDue else { return nil }
        switch d {
        case ..<0: return "Overdue"
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2...6:
            let date = Calendar.current.date(byAdding: .day, value: d, to: .now) ?? .now
            return date.formatted(.dateTime.weekday(.wide))
        default:
            let date = Calendar.current.date(byAdding: .day, value: d, to: .now) ?? .now
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    /// Due now: money or a trial that is due today or overdue.
    var isUrgent: Bool {
        guard let d = daysUntilDue else { return false }
        return d <= 0 && (type == "money" || trial)
    }

    /// Goes in the "need you" stack: anything overdue, or money, trials and
    /// trips in the next two days.
    var needsYou: Bool {
        guard let d = daysUntilDue else { return false }
        return d <= 0 || (d <= 2 && (type == "money" || trial || type == "travel"))
    }

    var amountText: String? {
        amount.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    }

    /// "Due today", "Converts Monday", "Oct 24", or how long ago it arrived.
    var whenText: String {
        if let due = dueText {
            if trial { return "Converts " + due.lowercased() }
            return type == "money" ? "Due " + due.lowercased() : due
        }
        return createdText ?? ""
    }

    var createdText: String? {
        guard let created, let date = Item.isoParse(created) else { return nil }
        let mins = Int(Date.now.timeIntervalSince(date) / 60)
        if mins < 60 { return "\(max(mins, 1))m ago" }
        if mins < 24 * 60 { return "\(mins / 60)h ago" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        if mins < 7 * 24 * 60 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The email's Message-ID, taken from the stored Gmail search link
    /// (".../#search/rfc822msgid:<id>"). The app uses it to fetch the email
    /// from the hub over IMAP, since the Gmail app can't open one message by link.
    var messageID: String? {
        guard let link, let range = link.range(of: "rfc822msgid:") else { return nil }
        let raw = String(link[range.upperBound...])
        let id = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
        return id.isEmpty ? nil : id
    }

    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    static func isoParse(_ s: String) -> Date? {
        isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func tidy(_ s: String) -> String {
        var out = s
        out = replace(out, #"^Trial: "#, "")
        out = replace(out, #"^\x{26A1}\x{FE0F}?\s*"#, "")
        out = replace(out, #"^(.+?) - \S+ at \S+?: "#, "$1: ")
        out = replace(out, #"^\S+ at \S+?: "#, "")
        return out
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

// MARK: - Venture identity

/// One color and one symbol per venture, used in the app, the widget and badges.
struct VentureStyle: Sendable {
    let short: String
    let color: Color
    let symbol: String
    let order: Int       // businesses first

    static func of(_ venture: String) -> VentureStyle {
        switch venture {
        case "Vishramo", "HotelOS": .init(short: "Vishramo", color: .hex(0x8E44AD), symbol: "bed.double.fill", order: 0)
        case "Credaxe": .init(short: "Credaxe", color: .hex(0x1E40AF), symbol: "chart.line.uptrend.xyaxis", order: 1)
        case "7-Eleven": .init(short: "7-Eleven", color: .hex(0x0F766E), symbol: "storefront.fill", order: 2)
        case "Job (hired)": .init(short: "Job", color: .hex(0x7C5A3A), symbol: "briefcase.fill", order: 3)
        case "Banking": .init(short: "Banking", color: .hex(0x166534), symbol: "building.columns.fill", order: 4)
        case "Personal": .init(short: "Personal", color: .hex(0x5856D6), symbol: "person.fill", order: 10)
        case "Shared/Household": .init(short: "Household", color: .hex(0x248A3D), symbol: "house.fill", order: 11)
        case "Family/General": .init(short: "Family", color: .hex(0xBE185D), symbol: "figure.2.and.child.holdinghands", order: 12)
        case "Travel": .init(short: "Travel", color: .hex(0x0277B5), symbol: "airplane", order: 13)
        case "Job Applications": .init(short: "Jobs", color: .hex(0x7C5A3A), symbol: "briefcase.fill", order: 14)
        case "Shopping": .init(short: "Shopping", color: .hex(0xC2410C), symbol: "bag.fill", order: 15)
        case "Food": .init(short: "Food", color: .hex(0xA16207), symbol: "fork.knife", order: 16)
        case "Pseudo": .init(short: "Pseudo", color: .hex(0x4B5563), symbol: "eye.slash.fill", order: 17)
        case "Social": .init(short: "Social", color: .hex(0x0E7490), symbol: "bubble.left.and.bubble.right.fill", order: 18)
        case "Gaming": .init(short: "Gaming", color: .hex(0x4338CA), symbol: "gamecontroller.fill", order: 19)
        case "Streaming": .init(short: "Streaming", color: .hex(0xB91C1C), symbol: "play.tv.fill", order: 20)
        case "Services": .init(short: "Services", color: .hex(0x64748B), symbol: "gearshape.fill", order: 21)
        default: .init(short: venture, color: .hex(0x64748B), symbol: "tray.fill", order: 30)
        }
    }
}

extension Color {
    static func hex(_ v: UInt32, opacity: Double = 1) -> Color {
        Color(.sRGB,
              red: Double((v >> 16) & 0xFF) / 255,
              green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255,
              opacity: opacity)
    }

    static let night = Color.hex(0x1A1633)
    static let cream = Color.hex(0xFFF4E6)
    static let amber = Color.hex(0xFFB020)
    static let brandOrange = Color.hex(0xFF7A1A)
    static let coral = Color.hex(0xFF5A4E)
}

// MARK: - Snooze ("Later")

/// Items put off until tomorrow morning. Kept in the App Group so the
/// widget skips them too (per phone; Notion is not changed).
enum SnoozeStore {
    private static let key = "snoozedUntil"

    private static var all: [String: Date] {
        SharedStore.defaults.dictionary(forKey: key) as? [String: Date] ?? [:]
    }

    static func activeIDs() -> Set<String> {
        Set(all.filter { $0.value > .now }.keys)
    }

    static func snooze(_ id: String) {
        var current = all.filter { $0.value > .now }
        current[id] = nextMorning()
        SharedStore.defaults.set(current, forKey: key)
    }

    static func unsnooze(_ id: String) {
        var current = all
        current[id] = nil
        SharedStore.defaults.set(current, forKey: key)
    }

    static func nextMorning() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        return cal.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Board

struct VentureGroup: Identifiable, Sendable {
    let venture: String
    let items: [Item]
    var id: String { venture }
    var style: VentureStyle { .of(venture) }
}

/// Everything the screens show, worked out once from the open items.
struct Board: Sendable {
    let power: [Item]
    let all: [Item]          // urgency order, without power rows
    let needYou: [Item]      // the stack at the top (not snoozed)
    let rest: [Item]         // everything else
    let ventures: [VentureGroup]
    let snoozed: Set<String>

    init(_ items: [Item], snoozed: Set<String> = []) {
        self.snoozed = snoozed
        power = items.filter(\.isPower).filter { !$0.title.contains("On track") }
        all = items.filter { !$0.isPower && !$0.isInternal }.sorted { a, b in
            let da = a.daysUntilDue ?? 9_999, db = b.daysUntilDue ?? 9_999
            if da != db { return da < db }
            return (a.created ?? "") > (b.created ?? "")
        }
        needYou = all.filter { $0.needsYou && !snoozed.contains($0.id) }
        let top = Set(needYou.map(\.id))
        rest = all.filter { !top.contains($0.id) }
        ventures = Dictionary(grouping: all, by: \.venture)
            .map { VentureGroup(venture: $0.key, items: $0.value) }
            .sorted { a, b in
                let oa = a.style.order, ob = b.style.order
                return oa != ob ? oa < ob : a.items.count > b.items.count
            }
    }

    var openCount: Int { all.count }
    var dueNow: [Item] { all.filter(\.isUrgent) }

    /// Focus mode: the stack first, then everything else that isn't snoozed.
    var focusQueue: [Item] { needYou + rest.filter { !snoozed.contains($0.id) } }

    /// Widget order: the stack first, then the rest.
    var urgentFirst: [Item] { needYou + rest }
}
