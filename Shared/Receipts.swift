import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// One row of the Receipts table: an invoice, receipt, statement, payment or
/// refund email the sorter keeps for good (FYI is cleared after two weeks).
struct Receipt: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let title: String
    let vendor: String
    let amount: Double?
    let kind: String          // invoice, receipt, statement, payment, refund
    let category: String
    let date: Date?
    let link: String?
    let pdf: String?          // Drive copy of the attached PDF
    let hasAttachment: Bool

    var subject: String {
        if let r = title.range(of: ": "), title.distance(from: title.startIndex, to: r.lowerBound) <= 40 {
            return String(title[r.upperBound...])
        }
        return title
    }

    /// What it adds to a month's total: invoices and receipts count, refunds
    /// take away; statements and payments are left out so nothing counts twice.
    var spend: Double {
        guard let amount else { return 0 }
        switch kind {
        case "invoice", "receipt": return amount
        case "refund": return -amount
        default: return 0
        }
    }

    var kindLabel: String {
        switch kind {
        case "invoice": "Invoice"
        case "receipt": "Receipt"
        case "statement": "Statement"
        case "payment": "Payment"
        case "refund": "Refund"
        default: kind.capitalized
        }
    }

    /// The same mail as an Item, for the shared avatar and email screen.
    var asItem: Item {
        Item(id: "mail-\(id)", title: title, type: "money", venture: category, amount: amount, due: nil,
             trial: false, link: link, domain: nil, created: nil, source: vendor)
    }

    init(id: String, title: String, vendor: String, amount: Double?, kind: String, category: String,
         date: Date?, link: String?, pdf: String? = nil, hasAttachment: Bool = false) {
        self.id = id; self.title = title; self.vendor = vendor; self.amount = amount; self.kind = kind
        self.category = category; self.date = date; self.link = link; self.pdf = pdf
        self.hasAttachment = hasAttachment
    }

    init?(page: [String: Any]) {
        guard let id = page["id"] as? String, let p = page["properties"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String {
            let v = p[key] as? [String: Any]
            let parts = (v?["title"] ?? v?["rich_text"]) as? [[String: Any]] ?? []
            return parts.compactMap { $0["plain_text"] as? String }.joined()
        }
        func select(_ key: String) -> String? {
            ((p[key] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String
        }
        let day = ((p["Date"] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String
        self.init(
            id: id,
            title: text("Title"),
            vendor: text("Vendor"),
            amount: (p["Amount"] as? [String: Any])?["number"] as? Double,
            kind: select("Kind") ?? "receipt",
            category: select("Category") ?? "Personal",
            date: day.flatMap { Item.dayFormatter.date(from: String($0.prefix(10))) },
            link: (p["Link"] as? [String: Any])?["url"] as? String,
            pdf: (p["PDF"] as? [String: Any])?["url"] as? String,
            hasAttachment: (p["Attachment"] as? [String: Any])?["checkbox"] as? Bool ?? false
        )
    }
}

/// A spreadsheet (.csv) of receipts for Share / Save to Files.
struct ReceiptsExport: Transferable {
    let receipts: [Receipt]
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(export.name).csv")
            try export.csv.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }

    var csv: String {
        func cell(_ s: String) -> String {
            var v = s
            if let f = v.first, "=+-@".contains(f) { v = "'" + v }       // never a formula in Excel
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = ["Date,Vendor,Category,Kind,Amount,Subject,Email,PDF"]
        for r in receipts {
            lines.append([
                r.date.map { Item.dayFormatter.string(from: $0) } ?? "",
                cell(r.vendor), cell(VentureStyle.of(r.category).short), r.kindLabel,
                r.amount.map { String(format: "%.2f", $0) } ?? "",
                cell(r.subject), cell(r.link ?? ""), cell(r.pdf ?? ""),
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
