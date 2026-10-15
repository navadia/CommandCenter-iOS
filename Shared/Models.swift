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

    var isPower: Bool { title.hasPrefix("\u{26A1}") }

    /// "GEICO - geico at e.geico.com: See…" -> "GEICO: See…" (old SimpleLogin titles)
    var cleanTitle: String { Item.tidy(title) }

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
        default: return "In \(d) days"
        }
    }

    var isUrgent: Bool {
        guard let d = daysUntilDue else { return false }
        return d <= 0 && (type == "money" || trial)
    }

    var amountText: String? {
        amount.map { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    }

    /// Gmail app deep link from the stored web search link.
    var emailURL: URL? {
        guard let link else { return nil }
        if let range = link.range(of: "rfc822msgid:") {
            // The stored link may already be percent-encoded; normalize, then
            // encode like JavaScript's encodeURIComponent (what Gmail accepts).
            let raw = String(link[range.upperBound...])
            let id = raw.removingPercentEncoding ?? raw
            let query = "rfc822msgid:\(id)".addingPercentEncoding(withAllowedCharacters: Item.uriComponentAllowed) ?? ""
            return URL(string: "googlegmail:///search/\(query)")
        }
        return URL(string: link)
    }

    /// Same characters JavaScript's encodeURIComponent leaves alone.
    static let uriComponentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

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

/// The sections, in priority order. Same grouping as the Scriptable Briefing.
enum Lane: String, CaseIterable, Identifiable, Sendable {
    case money, trials, ventures, travel, todo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .money: "Money"
        case .trials: "Trials Ending"
        case .ventures: "Ventures"
        case .travel: "Travel"
        case .todo: "To-Do"
        }
    }

    var symbol: String {
        switch self {
        case .money: "creditcard.fill"
        case .trials: "hourglass"
        case .ventures: "briefcase.fill"
        case .travel: "airplane"
        case .todo: "checklist"
        }
    }

    var color: Color {
        switch self {
        case .money: .red
        case .trials: .orange
        case .ventures: .blue
        case .travel: .green
        case .todo: .gray
        }
    }
}

struct LaneGroup: Identifiable, Sendable {
    let lane: Lane
    let items: [Item]
    var id: Lane { lane }
}

struct Board: Sendable {
    let power: [Item]
    let lanes: [LaneGroup]

    static let ventureLanes: Set<String> = ["Credaxe", "Vishramo", "HotelOS", "7-Eleven",
                                            "Job (hired)", "Job Applications"]

    init(_ all: [Item]) {
        power = all.filter(\.isPower).filter { !$0.title.contains("On track") }
        let rest = all.filter { !$0.isPower }
        let order: (Item, Item) -> Bool = { ($0.daysUntilDue ?? 9_999) < ($1.daysUntilDue ?? 9_999) }

        let money = rest.filter { $0.type == "money" && !$0.trial }.sorted(by: order)
        let trials = rest.filter(\.trial).sorted(by: order)
        let ventures = rest.filter { Board.ventureLanes.contains($0.venture) && $0.type == "todo" && !$0.trial }
        let travel = rest.filter { $0.type == "travel" && !$0.trial }.sorted(by: order)
        let todos = rest.filter { $0.type == "todo" && !Board.ventureLanes.contains($0.venture) && !$0.trial }

        lanes = [LaneGroup(lane: .money, items: money),
                 LaneGroup(lane: .trials, items: trials),
                 LaneGroup(lane: .ventures, items: ventures),
                 LaneGroup(lane: .travel, items: travel),
                 LaneGroup(lane: .todo, items: todos)]
            .filter { !$0.items.isEmpty }
    }

    var allItems: [Item] { lanes.flatMap(\.items) }
    var openCount: Int { allItems.count }
    var dueNow: [Item] { allItems.filter(\.isUrgent) }

    var moneyTotal: Double {
        lanes.first { $0.lane == .money }?.items.compactMap(\.amount).reduce(0, +) ?? 0
    }

    /// Flat list in urgency order, for the small and medium widgets.
    var urgentFirst: [Item] {
        let urgent = dueNow
        return urgent + allItems.filter { !urgent.contains($0) }
    }
}
