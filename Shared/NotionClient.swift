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

    private func request(_ path: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.notion.com/v1/\(path)")!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }
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
    func create(title: String, type: String, venture: String, amount: Double?, due: String?, source: String) async throws -> Item? {
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
        return Self.item(from: json)
    }

    /// What changed on the Edit sheet; nil = leave as it is.
    struct Changes {
        var title: String?
        var type: String?
        var venture: String?
        var amount: Double??      // .some(nil) clears it
        var due: String??         // .some(nil) clears it
        var isEmpty: Bool { title == nil && type == nil && venture == nil && amount == nil && due == nil }
    }

    func update(_ id: String, _ c: Changes) async throws -> Item? {
        var props: [String: Any] = [:]
        if let title = c.title { props["Title"] = ["title": [["text": ["content": String(title.prefix(200))]]]] }
        if let type = c.type { props["Type"] = ["select": ["name": type]] }
        if let venture = c.venture { props["Venture"] = ["select": ["name": venture]] }
        if let amount = c.amount { props["Amount"] = ["number": amount.map { $0 as Any } ?? NSNull()] }
        if let due = c.due { props["Due"] = ["date": due.map { ["start": $0] as Any } ?? NSNull()] }
        let json = try await send(request("pages/\(id)", method: "PATCH", body: ["properties": props]))
        return Self.item(from: json)
    }

    // MARK: Categories (the "Categories" table beside Command Center)

    /// Finds the Categories table: Command Center's parent page, then its child
    /// databases. The email sorter creates the table on its first run.
    func categoriesDatabaseID() async throws -> String? {
        let db = try await send(request("databases/\(Self.databaseID)", method: "GET"))
        guard let parent = db["parent"] as? [String: Any], let page = parent["page_id"] as? String else { return nil }
        var cursor: String?
        repeat {
            let q = "blocks/\(page)/children?page_size=100" + (cursor.map { "&start_cursor=\($0)" } ?? "")
            let json = try await send(request(q, method: "GET"))
            for block in json["results"] as? [[String: Any]] ?? [] {
                if block["type"] as? String == "child_database",
                   (block["child_database"] as? [String: Any])?["title"] as? String == "Categories",
                   block["archived"] as? Bool != true,
                   let id = block["id"] as? String {
                    return id
                }
            }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return nil
    }

    func categories(in db: String) async throws -> [Category] {
        var list: [Category] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = ["page_size": 100]
            if let cursor { body["start_cursor"] = cursor }
            let json = try await send(request("databases/\(db)/query", method: "POST", body: body))
            for page in json["results"] as? [[String: Any]] ?? [] {
                if let c = Self.category(from: page) { list.append(c) }
            }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        return list
    }

    /// Creates the row when it has no id yet, otherwise updates it.
    func save(_ c: Category, in db: String) async throws -> Category {
        func text(_ s: String) -> [String: Any] {
            s.isEmpty ? ["rich_text": []] : ["rich_text": [["text": ["content": String(s.prefix(1_900))]]]]
        }
        let props: [String: Any] = [
            "Name": ["title": [["text": ["content": c.name]]]],
            "Rules": text(c.rulesText),
            "Order": ["number": c.order],
            "Icon": text(c.icon),
            "Color": text(c.color),
            "About": text(c.about),
        ]
        let json = c.id.isEmpty
            ? try await send(request("pages", method: "POST", body: ["parent": ["database_id": db], "properties": props]))
            : try await send(request("pages/\(c.id)", method: "PATCH", body: ["properties": props]))
        return Self.category(from: json) ?? c
    }

    /// Deleting a category archives its row (Notion keeps it in Trash).
    func archive(pageID: String) async throws {
        _ = try await send(request("pages/\(pageID)", method: "PATCH", body: ["archived": true]))
    }

    /// Moves every open row of one venture to another; done rows keep their name as history.
    func moveOpenItems(from old: String, to new: String) async throws -> Int {
        var ids: [String] = []
        var cursor: String?
        repeat {
            var body: [String: Any] = [
                "filter": ["and": [
                    ["property": "Venture", "select": ["equals": old]],
                    ["property": "Status", "select": ["does_not_equal": "done"]],
                ]],
                "page_size": 100,
            ]
            if let cursor { body["start_cursor"] = cursor }
            let json = try await send(request("databases/\(Self.databaseID)/query", method: "POST", body: body))
            ids += (json["results"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            cursor = (json["has_more"] as? Bool == true) ? json["next_cursor"] as? String : nil
        } while cursor != nil
        for id in ids {
            _ = try await send(request("pages/\(id)", method: "PATCH",
                                       body: ["properties": ["Venture": ["select": ["name": new]]]]))
        }
        return ids.count
    }

    private static func category(from page: [String: Any]) -> Category? {
        guard let id = page["id"] as? String, let p = page["properties"] as? [String: Any] else { return nil }
        func text(_ key: String) -> String {
            ((p[key] as? [String: Any])?["rich_text"] as? [[String: Any]] ?? [])
                .compactMap { $0["plain_text"] as? String }.joined()
        }
        let name = ((p["Name"] as? [String: Any])?["title"] as? [[String: Any]] ?? [])
            .compactMap { $0["plain_text"] as? String }.joined().trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let order = ((p["Order"] as? [String: Any])?["number"] as? Double).map { Int($0) } ?? 50
        return Category(id: id, name: name, rules: Category.rules(from: text("Rules")), order: order,
                        icon: text("Icon").trimmingCharacters(in: .whitespaces),
                        color: text("Color").trimmingCharacters(in: .whitespaces), about: text("About"))
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
