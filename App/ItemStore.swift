import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class ItemStore {
    private(set) var items: [Item] = SharedStore.snapshot
    private(set) var lastUpdated: Date? = SharedStore.snapshotDate
    private(set) var isLoading = false
    var errorMessage: String?
    var hasToken = TokenStore.load() != nil
    var hasGmail = GmailCredentials.load() != nil
    private(set) var snoozed = SnoozeStore.activeIDs()

    var board: Board { Board(items, snoozed: snoozed) }

    func refresh() async {
        if DemoData.isOn {
            items = DemoData.items
            hasToken = true
            lastUpdated = .now
            let domains = items.compactMap(\.domain)
            await SenderIcons.prefetch(domains)
            items = items
            return
        }
        guard let token = TokenStore.load() else {
            hasToken = false
            return
        }
        hasToken = true
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await NotionClient(token: token).openItems()
            items = fresh
            lastUpdated = .now
            errorMessage = nil
            SharedStore.saveSnapshot(fresh)
            snoozed = SnoozeStore.activeIDs()
            WidgetCenter.shared.reloadAllTimelines()
            let domains = fresh.compactMap(\.domain)
            Task {
                await SenderIcons.prefetch(domains)
                self.items = self.items      // redraw with any new icons
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch is CancellationError {
            // A newer refresh or the system cut this one off: keep what we have.
        } catch let error as URLError where error.code == .cancelled {
            // Same, from URLSession.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a task from the Add sheet, then shows it.
    func add(_ draft: TaskDraft, kind: CaptureKind) async throws {
        let due = draft.due.map { Item.dayFormatter.string(from: $0) }
        if DemoData.isOn {
            items.append(Item(id: UUID().uuidString, title: draft.notionTitle, type: draft.type, venture: draft.venture,
                              amount: draft.amount, due: due, trial: false, link: nil))
            return
        }
        guard let token = TokenStore.load() else {
            throw NotionClient.NotionError.http(401, "No Notion token")
        }
        let saved = try await NotionClient(token: token).create(
            title: draft.notionTitle, type: draft.type, venture: draft.venture,
            amount: draft.amount, due: due, source: kind.rawValue)
        // Show it right away; the next refresh brings it back from Notion anyway.
        if let saved, !items.contains(where: { $0.id == saved.id }) {
            items.append(saved)
            SharedStore.saveSnapshot(items)
            WidgetCenter.shared.reloadAllTimelines()
        }
        Task { await self.refresh() }
    }

    /// Saves edits from the Edit sheet; the row updates at once.
    func update(_ item: Item, _ changes: NotionClient.Changes) async throws {
        guard !changes.isEmpty else { return }
        let edited = Item(id: item.id, title: changes.title ?? item.title, type: changes.type ?? item.type,
                          venture: changes.venture ?? item.venture,
                          amount: changes.amount ?? item.amount, due: changes.due ?? item.due,
                          trial: item.trial, link: item.link, domain: item.domain,
                          created: item.created, source: item.source)
        func put(_ row: Item) {
            if let i = items.firstIndex(where: { $0.id == row.id }) { items[i] = row }
            SharedStore.saveSnapshot(items)
            WidgetCenter.shared.reloadAllTimelines()
        }
        if DemoData.isOn { put(edited); return }
        guard let token = TokenStore.load() else { throw NotionClient.NotionError.http(401, "No Notion token") }
        let saved = try await NotionClient(token: token).update(item.id, changes)
        put(saved.map { row in
            Item(id: row.id, title: row.title, type: row.type, venture: row.venture, amount: row.amount, due: row.due,
                 trial: row.trial, link: row.link, domain: row.domain ?? item.domain, created: row.created, source: row.source)
        } ?? edited)
    }

    /// Optimistic: rows disappear at once; any that fail come back with an error.
    func markDone(_ ids: Set<String>) async {
        if DemoData.isOn { items.removeAll { ids.contains($0.id) }; return }
        guard let token = TokenStore.load(), !ids.isEmpty else { return }
        let removed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        SharedStore.saveSnapshot(items)
        WidgetCenter.shared.reloadAllTimelines()

        let client = NotionClient(token: token)
        var failed: [Item] = []
        for item in removed {        // one at a time: Notion allows ~3 requests a second
            do { try await client.markDone(item.id) } catch { failed.append(item) }
        }
        if !failed.isEmpty {
            items.append(contentsOf: failed)
            SharedStore.saveSnapshot(items)
            errorMessage = "\(failed.count) item\(failed.count == 1 ? "" : "s") couldn't be marked done. Try again."
        }
    }

    /// "Later": hide from the stack and Focus until tomorrow morning.
    func snooze(_ id: String) {
        SnoozeStore.snooze(id)
        snoozed = SnoozeStore.activeIDs()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func unsnooze(_ id: String) {
        SnoozeStore.unsnooze(id)
        snoozed = SnoozeStore.activeIDs()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Redraw everything (and the widget) after a venture color change.
    func ventureColorsChanged() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    func saveToken(_ token: String) async -> String {
        let place = TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        await refresh()
        return place
    }
}
