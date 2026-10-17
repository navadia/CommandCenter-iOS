import Foundation
import FoundationModels
import Vision

/// A task waiting to be checked and saved: what came in, and what the app
/// made of it. Everything here is editable on the Add sheet before saving.
struct TaskDraft: Equatable {
    var from = ""
    var title = ""
    var type = "todo"
    var venture = "Personal"
    var amount: Double?
    var due: Date?
    var readBy: Reader = .rules

    enum Reader { case model, rules }

    /// The Notion title, in the same "Sender: subject" shape the parser uses.
    var notionTitle: String {
        let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return f.isEmpty ? t : "\(f): \(t)"
    }

    /// The venture names as they are in Notion's Venture column.
    static let ventures = ["Vishramo", "Credaxe", "7-Eleven", "Job (hired)", "Personal", "Shared/Household",
                           "Family/General", "Travel", "Job Applications", "Banking"]
    static let types = ["todo", "money", "travel"]
}

/// What started the capture, so the row's Source says where it came from.
enum CaptureKind: String {
    case typed = "quickadd", voice, screenshot
}

/// Turns spoken / typed text or a screenshot into a TaskDraft, all on this
/// iPhone: Vision reads the screenshot, Apple Intelligence picks out the task.
/// Without Apple Intelligence it falls back to simple rules.
enum TaskReader {
    /// The text on a screenshot, top to bottom.
    static func text(in image: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let lines = try await request.perform(on: image)
        return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func draft(from text: String, kind: CaptureKind) async -> TaskDraft {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3_000))
        guard !trimmed.isEmpty else { return TaskDraft() }
        var draft = await modelDraft(trimmed, kind: kind) ?? ruleDraft(trimmed, kind: kind)
        if let remembered = VentureMemory.venture(for: draft.from, in: trimmed) {
            draft.venture = remembered
        }
        return draft
    }

    // MARK: Apple Intelligence

    @Generable
    struct Parsed {
        @Guide(description: "Who the task is from or about: a company or a person, e.g. McLane, GEICO, AWS, Priya. Empty if there is none.")
        var from: String
        @Guide(description: "A short task title of at most 8 words. Start with a verb when it is something to do, e.g. 'Pay invoice #4471' or 'Reply about Diwali dinner'. Don't repeat the from name.")
        var title: String
        @Guide(description: "money for a bill, invoice, payment, refund, renewal or subscription; travel for a flight, hotel, booking or trip; todo for anything else.",
               .anyOf(TaskDraft.types))
        var type: String
        @Guide(description: "Which part of Parth's life this belongs to.", .anyOf(TaskDraft.ventures))
        var venture: String
        @Guide(description: "The amount of money in US dollars, or 0 if none is mentioned.")
        var amount: Double
        @Guide(description: "The due date as YYYY-MM-DD, or empty if there is none.")
        var due: String
    }

    private static func modelDraft(_ text: String, kind: CaptureKind) async -> TaskDraft? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let today = Item.dayFormatter.string(from: .now)
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        let instructions = """
        You turn a note into one task for Parth's to-do list. Today is \(weekday), \(today).
        Ventures: Vishramo = his hotel software company (AWS, Vercel, servers, hotels, customers). \
        Credaxe = his other software company. 7-Eleven = the 7-Eleven store he runs (McLane, vendors, \
        store staff, store bills). Job (hired) = his employer. Job Applications = job hunting, recruiters, \
        interviews. Shared/Household = home bills and chores shared with his wife (rent, power, internet). \
        Family/General = family plans and events. Travel = flights and trips. Banking = bank accounts. \
        Personal = anything else of his own (insurance, health, shopping).
        Relative dates like "Friday" or "tomorrow" mean the next such day from today.
        """
        let source = kind == .screenshot
            ? "This is the text on a screenshot of his iPhone screen. Ignore the clock, battery and app buttons; find the thing he needs to do."
            : "This is what he said or typed."
        do {
            let session = LanguageModelSession(instructions: instructions)
            let reply = try await session.respond(to: "\(source)\n\n\(text)", generating: Parsed.self)
            let p = reply.content
            var draft = TaskDraft(readBy: .model)
            draft.from = p.from.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.title = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.type = TaskDraft.types.contains(p.type) ? p.type : "todo"
            draft.venture = TaskDraft.ventures.contains(p.venture) ? p.venture : "Personal"
            draft.amount = p.amount > 0 ? p.amount : nil
            draft.due = Item.dayFormatter.date(from: p.due)
            if draft.title.isEmpty { return nil }
            return draft
        } catch {
            return nil      // guardrails, too long, model busy: rules take over
        }
    }

    // MARK: Rules (no Apple Intelligence)

    static func ruleDraft(_ text: String, kind: CaptureKind) -> TaskDraft {
        var draft = TaskDraft(readBy: .rules)
        draft.title = kind == .screenshot ? bestLine(text) : firstSentence(text)
        draft.amount = amount(in: text)
        draft.due = date(in: text)
        let lower = text.lowercased()
        draft.venture = keywordVenture(lower) ?? "Personal"
        if draft.amount != nil || ["invoice", "bill", "payment", "due", "renew"].contains(where: { lower.contains($0) }) {
            draft.type = "money"
        } else if ["flight", "airways", "airline", "boarding", "check-in", "itinerary"].contains(where: { lower.contains($0) }) {
            draft.type = "travel"
        }
        return draft
    }

    private static let keywords: [(needles: [String], venture: String)] = [
        (["vishramo", "hotelos", "aws", "vercel", "cloudwatch", "fly.io", "neon"], "Vishramo"),
        (["credaxe"], "Credaxe"),
        (["7-eleven", "7eleven", "7 eleven", "mclane"], "7-Eleven"),
        (["interview", "recruiter", "application", "greenhouse", "linkedin"], "Job Applications"),
        (["flight", "airways", "airline", "boarding", "itinerary"], "Travel"),
        (["rent", "electric", "energy", "internet", "water bill"], "Shared/Household"),
    ]

    private static func keywordVenture(_ lower: String) -> String? {
        keywords.first { entry in entry.needles.contains { needle in lower.contains(needle) } }?.venture
    }

    static func amount(in text: String) -> Double? {
        guard let match = text.firstMatch(of: /\$\s?([0-9][0-9,]*(?:\.[0-9]{1,2})?)/) else { return nil }
        return Double(match.1.replacingOccurrences(of: ",", with: ""))
    }

    static func date(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        for match in detector.matches(in: text, range: range) {
            guard var date = match.date, let r = Range(match.range, in: text) else { continue }
            let words = text[r]
            // "1,284" or "7:58" alone aren't due dates.
            guard words.contains(where: \.isLetter) || words.contains("/") else { continue }
            // "Wednesday" can come back as last Wednesday: move it to the next one.
            while date < start, words.lowercased().contains("day"),
                  let next = calendar.date(byAdding: .day, value: 7, to: date) {
                date = next
            }
            if date >= start { return calendar.startOfDay(for: date) }
        }
        return nil
    }

    private static func firstSentence(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let sentence = line.split(separator: ".", maxSplits: 1).first.map(String.init) ?? line
        return String(sentence.prefix(120)).trimmingCharacters(in: .whitespaces)
    }

    /// Screenshots start with the clock and buttons; take the first line that
    /// reads like a sentence.
    private static func bestLine(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 4 && $0.contains(where: \.isLetter) && $0.firstMatch(of: /^\d{1,2}:\d{2}/) == nil }
        let sentence = lines.first { $0.split(separator: " ").count >= 3 && $0.count <= 100 }
        return String((sentence ?? lines.first ?? "").prefix(120))
    }
}

/// When you correct a venture on the Add sheet, the app remembers it for that
/// sender (on this iPhone), so "McLane" lands in 7-Eleven next time.
enum VentureMemory {
    private static let key = "ventureMemory"

    private static var all: [String: String] {
        SharedStore.defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }

    static func remember(from: String, venture: String) {
        let name = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard name.count >= 2 else { return }
        var map = all
        map[name] = venture
        SharedStore.defaults.set(map, forKey: key)
    }

    static func venture(for from: String, in text: String) -> String? {
        let map = all
        let name = from.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = map[name] { return exact }
        let lower = text.lowercased()
        return map.first { lower.contains($0.key) }?.value
    }
}
