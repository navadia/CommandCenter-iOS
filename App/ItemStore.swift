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
        } catch {
            errorMessage = error.localizedDescription
        }
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
