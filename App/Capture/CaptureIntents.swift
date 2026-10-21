import AppIntents
import Foundation
import Observation
import UniformTypeIdentifiers
import WidgetKit

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

/// "Add Task Now": reads the text and saves the task straight away; the app
/// never opens. Shortcuts shows one line saying what was added and where.
/// Check or change it later from Today (long-press > Edit).
struct AddTaskNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task Now"
    static let description = IntentDescription(
        "Saves a task straight away from dictated or typed text, without opening Command Center. Change it later from Today if needed.")

    @Parameter(title: "Text")
    var text: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = try await QuickSave.save(.text(text), kind: .voice)
        return .result(dialog: "\(line)")
    }
}

/// "Add Task from Screenshot Now": Back Tap without opening the app.
struct AddFromScreenshotNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task from Screenshot Now"
    static let description = IntentDescription(
        "Reads a screenshot on this iPhone and saves the task it finds straight away, without opening Command Center. Nothing is uploaded.")

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = try await QuickSave.save(.image(screenshot.data), kind: .screenshot)
        return .result(dialog: "\(line)")
    }
}

/// The no-review path behind the "Now" actions: read, fill in, save, report.
@MainActor
enum QuickSave {
    enum Failure: LocalizedError {
        case nothingRead, noToken
        var errorDescription: String? {
            switch self {
            case .nothingRead: "Couldn't find a task in that. Try again, or use Add Task to type it."
            case .noToken: "Open Command Center and add your Notion token first."
            }
        }
    }

    static func save(_ input: CaptureRequest.Input, kind: CaptureKind) async throws -> String {
        let text: String
        switch input {
        case .text(let words): text = words
        case .image(let data): text = (try? await TaskReader.text(in: data)) ?? ""
        case .edit: text = ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.nothingRead }
        let draft = await TaskReader.draft(from: text, kind: kind)
        guard !draft.title.isEmpty else { throw Failure.nothingRead }
        guard let token = TokenStore.load() else { throw Failure.noToken }
        let due = draft.due.map { Item.dayFormatter.string(from: $0) }
        let saved = try await NotionClient(token: token).create(
            title: draft.notionTitle, type: draft.type, venture: draft.venture,
            amount: draft.amount, due: due, source: kind.rawValue)
        if let saved {
            SharedStore.saveSnapshot(SharedStore.snapshot + [saved])
            WidgetCenter.shared.reloadAllTimelines()
        }
        var line = "Added to \(VentureStyle.of(draft.venture).short): \(draft.notionTitle)"
        if let amount = draft.amount { line += " · $\(amount.formatted(.number.precision(.fractionLength(0...2))))" }
        if let date = draft.due { line += " · due \(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" }
        return line
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
        AppShortcut(
            intent: AddTaskNowIntent(),
            phrases: ["Quick add in \(.applicationName)", "Save a task in \(.applicationName)"],
            shortTitle: "Add Task Now",
            systemImageName: "bolt.circle"
        )
    }
}
