import Foundation

/// Talks to the same Notion database the parser fills.
struct NotionClient: Sendable {
    let token: String
    static let databaseID = "000182fc-1746-4625-90d8-28e6aff5f02e"

    enum NotionError: LocalizedError {
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .http(401, _): "Notion rejected the token. Check it in Settings."
            case .http(404, _): "Notion can't see the Command Center database. Share it with your integration."
            case .http(let code, let message): "Notion error \(code): \(message)"
            }
        }
    }

    private func request(_ path: String, method: String, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.notion.com/v1/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        return req
    }

    private func send(_ req: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw NotionError.http(code, json["message"] as? String ?? "unknown")
        }
        return json
    }

    /// Every row that isn't done, soonest due first.
    func openItems() async throws -> [Item] {
        var items: [Item] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = [
                "filter": ["property": "Status", "select": ["does_not_equal": "done"]],
                "sorts": [["property": "Due", "direction": "ascending"]],
                "page_size": 100,
            ]
            if let cursor { body["start_cursor"] = cursor }
            let json = try await send(request("databases/\(Self.databaseID)/query", method: "POST", body: body))
            for page in json["results"] as? [[String: Any]] ?? [] {
                if let item = Self.item(from: page) { items.append(item) }
            }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return items
    }

    /// A new open row, added by hand (Add sheet, Action button, Back Tap).
    func create(title: String, type: String, venture: String, amount: Double?, due: String?, source: String) async throws -> String {
        func text(_ s: String) -> [String: Any] { ["rich_text": [["text": ["content": String(s.prefix(1_900))]]]] }
        var props: [String: Any] = [
            "Title": ["title": [["text": ["content": String(title.prefix(200))]]]],
            "Type": ["select": ["name": type]],
            "Venture": ["select": ["name": venture]],
            "Status": ["select": ["name": "open"]],
            "Source": text(source),
        ]
        if let amount { props["Amount"] = ["number": amount] }
        if let due { props["Due"] = ["date": ["start": due]] }
        let json = try await send(request("pages", method: "POST",
                                          body: ["parent": ["database_id": Self.databaseID], "properties": props]))
        return json["id"] as? String ?? ""
    }

    func markDone(_ id: String) async throws {
        let body: [String: Any] = ["properties": ["Status": ["select": ["name": "done"]]]]
        _ = try await send(request("pages/\(id)", method: "PATCH", body: body))
    }

    private static func item(from page: [String: Any]) -> Item? {
        guard let id = page["id"] as? String, let p = page["properties"] as? [String: Any] else { return nil }

        func select(_ key: String) -> String? {
            ((p[key] as? [String: Any])?["select"] as? [String: Any])?["name"] as? String
        }
        let titleParts = (p["Title"] as? [String: Any])?["title"] as? [[String: Any]] ?? []
        let title = titleParts.compactMap { $0["plain_text"] as? String }.joined()
        let due = ((p["Due"] as? [String: Any])?["date"] as? [String: Any])?["start"] as? String
        let sourceParts = (p["Source"] as? [String: Any])?["rich_text"] as? [[String: Any]] ?? []
        let source = sourceParts.compactMap { $0["plain_text"] as? String }.joined()
        let fpParts = (p["Fingerprint"] as? [String: Any])?["rich_text"] as? [[String: Any]] ?? []
        let fingerprint = fpParts.compactMap { $0["plain_text"] as? String }.joined()
        let domain = fingerprint.split(separator: "|").first.map(String.init).flatMap { $0.contains(".") ? $0 : nil }

        return Item(
            id: id,
            title: title.isEmpty ? "(untitled)" : title,
            type: select("Type") ?? "todo",
            venture: select("Venture") ?? "Personal",
            amount: (p["Amount"] as? [String: Any])?["number"] as? Double,
            due: due,
            trial: (p["Trial"] as? [String: Any])?["checkbox"] as? Bool ?? false,
            link: (p["Link"] as? [String: Any])?["url"] as? String,
            domain: domain,
            created: page["created_time"] as? String,
            source: source.isEmpty ? nil : source
        )
    }
}
