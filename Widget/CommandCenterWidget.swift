import AppIntents
import SwiftUI
import WidgetKit

@main
struct CommandCenterWidgets: WidgetBundle {
    var body: some Widget {
        PipelineTestWidget()
    }
}

// MARK: - Interactive button (runs without opening the app)

struct TapIntent: AppIntent {
    static let title: LocalizedStringResource = "Test tap"

    func perform() async throws -> some IntentResult {
        SharedStore.widgetTaps += 1
        return .result()
    }
}

// MARK: - Timeline

struct TestEntry: TimelineEntry {
    let date: Date
    let taps: Int
    let appOpenedAt: Date?
    let groupWorks: Bool
}

struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry {
        TestEntry(date: .now, taps: 0, appOpenedAt: nil, groupWorks: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func current() -> TestEntry {
        TestEntry(date: .now, taps: SharedStore.widgetTaps,
                  appOpenedAt: SharedStore.appOpenedAt, groupWorks: SharedStore.isGroupWorking)
    }
}

// MARK: - View

struct PipelineTestWidgetView: View {
    let entry: TestEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.groupWorks ? "Shared data OK" : "No App Group",
                  systemImage: entry.groupWorks ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.caption.bold())
                .foregroundStyle(entry.groupWorks ? .green : .red)
                .widgetAccentable()

            Text("\(entry.taps)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Text(entry.appOpenedAt.map { "App opened \($0.formatted(date: .omitted, time: .shortened))" }
                 ?? "Open the app once")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(intent: TapIntent()) {
                Label("Tap", systemImage: "hand.tap.fill")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .containerBackground(for: .widget) {
            // System glass takes over in the Clear and Tinted Home Screen styles.
            Color.clear
        }
    }
}

struct PipelineTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PipelineTest", provider: TestProvider()) { entry in
            PipelineTestWidgetView(entry: entry)
        }
        .configurationDisplayName("Command Center Test")
        .description("Check that the widget and app share data.")
        .supportedFamilies([.systemSmall])
    }
}
