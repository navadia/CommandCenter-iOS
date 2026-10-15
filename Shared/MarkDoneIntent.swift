import AppIntents
import WidgetKit

/// Marks one item done in Notion. Used by the widget's circle buttons, so it
/// runs without opening the app; WidgetKit reloads the widget afterwards.
struct MarkDoneIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Done"
    static let isDiscoverable = false

    @Parameter(title: "Item ID")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        // Remove it locally first so the widget updates even if Notion is slow.
        SharedStore.removeFromSnapshot(itemID)
        if let token = TokenStore.load() {
            try await NotionClient(token: token).markDone(itemID)
        }
        return .result()
    }
}
