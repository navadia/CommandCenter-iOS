import AppIntents
import Foundation
import Observation
import UniformTypeIdentifiers

/// What the Add sheet should start from.
struct CaptureRequest: Identifiable {
    enum Input { case text(String), image(Data), edit(Item) }
    let id = UUID()
    let input: Input
    let kind: CaptureKind
}

/// The hand-off from a Shortcuts action (Action button, Back Tap, Siri) to
/// the app: the intent sets a request, Today opens the Add sheet for it.
@MainActor
@Observable
final class CaptureCenter {
    static let shared = CaptureCenter()
    var request: CaptureRequest?
}

/// "Add Task": opens the app with the text ready to check and save. In
/// Shortcuts, feed it Dictate Text for a voice task on the Action button.
struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription(
        "Opens Command Center with a new task to check and save. Give it dictated or typed text, or leave it empty to type in the app.")
    static let openAppWhenRun = true

    @Parameter(title: "Text")
    var text: String?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let words = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        CaptureCenter.shared.request = CaptureRequest(input: .text(words), kind: words.isEmpty ? .typed : .voice)
        return .result()
    }
}

/// "Add Task from Screenshot": reads the image on this iPhone and opens the
/// app with the task it found. In Shortcuts: Take Screenshot, then this,
/// on Back Tap.
struct AddFromScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task from Screenshot"
    static let description = IntentDescription(
        "Reads a screenshot or photo on this iPhone and opens Command Center with the task it found, to check and save. Nothing is uploaded.")
    static let openAppWhenRun = true

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        CaptureCenter.shared.request = CaptureRequest(input: .image(screenshot.data), kind: .screenshot)
        return .result()
    }
}

struct CommandCenterShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "Add to \(.applicationName)"],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
    }
}
