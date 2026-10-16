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

    var board: Board { Board(items) }

    func refresh() async {
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
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Optimistic: rows disappear at once; any that fail come back with an error.
    func markDone(_ ids: Set<String>) async {
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

    func saveToken(_ token: String) async -> String {
        let place = TokenStore.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
        await refresh()
        return place
    }
}
