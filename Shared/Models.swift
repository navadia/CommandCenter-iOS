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
    var source: String? = nil     // parser's "Sender name | destination"

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
        let known = sourceName
        if let r = t.range(of: ": ") {
            let prefix = String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty, prefix.count <= 40, known == nil || Item.sameSender(prefix, known!) {
                return (prefix, String(t[r.upperBound...]))
            }
        }
        if let known { return (known, t) }      // e.g. "Reminder: …" from Walgreens Photo
        return (t, "")
    }

    /// The sender name the parser saved in Source ("Walgreens Photo | to"),
    /// unless the row was added by hand.
    private var sourceName: String? {
        guard let source else { return nil }
        var name = (source.components(separatedBy: " | ").first ?? "").trimmingCharacters(in: .whitespaces)
        name = Item.replace(name, #" - \S+ at \S+$"#, "")        // SimpleLogin "Name - x at y"
        let lower = name.lowercased()
        if name.isEmpty || ["claude", "manual", "whatsapp", "quickadd", "fyi"].contains(lower) { return nil }
        if name == lower, let first = name.first { name = first.uppercased() + name.dropFirst() }
        return name
    }

    private static func sameSender(_ a: String, _ b: String) -> Bool {
        let x = a.lowercased(), y = b.lowercased()
        return x.contains(y) || y.contains(x)
            || x.split(separator: " ").first == y.split(separator: " ").first
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
            let word = ["Today", "Tomorrow", "Overdue"].contains(due) ? due.lowercased() : due
            if trial { return due == "Overdue" ? "Converted" : "Converts " + word }
            if type == "money" { return due == "Overdue" ? "Overdue" : "Due " + word }
            return due
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

    static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
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

    /// The venture's style, with the color the user picked in Settings if any.
    static func of(_ venture: String) -> VentureStyle {
        let base = standard(venture)
        guard let picked = VentureColors.picked(for: base.short) else { return base }
        return VentureStyle(short: base.short, color: picked, symbol: base.symbol, order: base.order)
    }

    static func standard(_ venture: String) -> VentureStyle {
        switch venture {
        case "Vishramo", "HotelOS": .init(short: "Vishramo", color: .purple, symbol: "bed.double.fill", order: 0)
        case "Credaxe": .init(short: "Credaxe", color: VentureColors.credaxeGold, symbol: "chart.line.uptrend.xyaxis", order: 1)
        case "7-Eleven": .init(short: "7-Eleven", color: .orange, symbol: "storefront.fill", order: 2)
        case "Job (hired)": .init(short: "Job", color: .brown, symbol: "briefcase.fill", order: 3)
        case "Banking": .init(short: "Banking", color: .mint, symbol: "building.columns.fill", order: 4)
        case "Personal": .init(short: "Personal", color: .indigo, symbol: "person.fill", order: 10)
        case "Shared/Household": .init(short: "Household", color: .green, symbol: "house.fill", order: 11)
        case "Family/General": .init(short: "Family", color: .pink, symbol: "figure.2.and.child.holdinghands", order: 12)
        case "Travel": .init(short: "Travel", color: .cyan, symbol: "airplane", order: 13)
        case "Job Applications": .init(short: "Jobs", color: .brown, symbol: "briefcase.fill", order: 14)
        case "Shopping": .init(short: "Shopping", color: .yellow, symbol: "bag.fill", order: 15)
        case "Food": .init(short: "Food", color: .red, symbol: "fork.knife", order: 16)
        case "Pseudo": .init(short: "Pseudo", color: .gray, symbol: "eye.slash.fill", order: 17)
        case "Social": .init(short: "Social", color: .teal, symbol: "bubble.left.and.bubble.right.fill", order: 18)
        case "Gaming": .init(short: "Gaming", color: .indigo, symbol: "gamecontroller.fill", order: 19)
        case "Streaming": .init(short: "Streaming", color: .red, symbol: "play.tv.fill", order: 20)
        case "Services": .init(short: "Services", color: .gray, symbol: "gearshape.fill", order: 21)
        default: .init(short: venture, color: .gray, symbol: "tray.fill", order: 30)
        }
    }
}

/// Colors the user can pick per venture (Settings), saved in the App Group
/// so the widget uses them too.
enum VentureColors {
    /// Credaxe's own brand gold (client/src/index.css: --color-primary #735C00).
    static let credaxeGold = Color.hex(0x8A6D00)

    static let palette: [(name: String, color: Color)] = [
        ("Purple", .purple), ("Indigo", .indigo), ("Blue", .blue), ("Cyan", .cyan), ("Teal", .teal),
        ("Mint", .mint), ("Green", .green), ("Gold", credaxeGold), ("Yellow", .yellow), ("Orange", .orange),
        ("Red", .red), ("Pink", .pink), ("Brown", .brown), ("Gray", .gray),
    ]

    private static let key = "ventureColors"

    static func pickedName(for short: String) -> String? {
        (SharedStore.defaults.dictionary(forKey: key) as? [String: String])?[short]
    }

    static func picked(for short: String) -> Color? {
        guard let name = pickedName(for: short) else { return nil }
        return palette.first { $0.name == name }?.color
    }

    /// nil = back to the standard color.
    static func set(_ name: String?, for short: String) {
        var all = SharedStore.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[short] = name
        SharedStore.defaults.set(all, forKey: key)
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

    /// Main button fill: Night in light mode, Cream in dark mode.
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.957, blue: 0.902, alpha: 1)
        : UIColor(red: 0.102, green: 0.086, blue: 0.2, alpha: 1) })
    /// Text on an `ink` fill.
    static let onInk = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.102, green: 0.086, blue: 0.2, alpha: 1)
        : UIColor(red: 1, green: 0.957, blue: 0.902, alpha: 1) })
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
