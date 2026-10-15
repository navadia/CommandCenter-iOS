import SwiftUI
import WidgetKit

@main
struct CommandCenterApp: App {
    var body: some Scene {
        WindowGroup {
            PipelineTestView()
        }
    }
}

/// Step 1 test screen: proves the build → SideStore → phone pipeline works,
/// and that the app and widget can share data. Replaced by the real app next.
struct PipelineTestView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var openedAt = SharedStore.appOpenedAt
    @State private var widgetTaps = SharedStore.widgetTaps
    @State private var groupWorks = SharedStore.isGroupWorking

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Pipeline works", systemImage: "checkmark.seal.fill")
                            .font(.title2.bold())
                        Text("Built on a cloud Mac, installed with SideStore.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 12) {
                        row("App Group", groupWorks ? "Working" : "Not available",
                            symbol: groupWorks ? "checkmark.circle.fill" : "xmark.octagon.fill",
                            tint: groupWorks ? .green : .red)
                        row("Group ID", SharedStore.groupID, symbol: "person.2.fill", tint: .secondary)
                        row("Widget button taps", "\(widgetTaps)", symbol: "hand.tap.fill", tint: .orange)
                    }
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 24))

                    Text("Add the Command Center widget to your Home Screen, tap its button a few times, then come back here. The tap count should match.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            SharedStore.appOpenedAt = .now
            openedAt = SharedStore.appOpenedAt
            widgetTaps = SharedStore.widgetTaps
            groupWorks = SharedStore.isGroupWorking
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func row(_ title: String, _ value: String, symbol: String, tint: Color) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .foregroundStyle(tint)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}
