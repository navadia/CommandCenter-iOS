import SwiftUI

@main
struct CommandCenterApp: App {
    @State private var store = ItemStore()

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environment(store)
        }
    }
}
