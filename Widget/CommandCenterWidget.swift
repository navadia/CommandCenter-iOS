import AppIntents
import SwiftUI
import WidgetKit

@main
struct CommandCenterWidgets: WidgetBundle {
    var body: some Widget {
        CommandCenterWidget()
    }
}

// MARK: - Configuration (no options; needed for the async provider)

struct CommandCenterConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Command Center"
    static let description = IntentDescription("See what needs you today and check items off.")
}

// MARK: - Timeline

struct CCEntry: TimelineEntry {
    let date: Date
    let board: Board
    let isStale: Bool      // showing the cached list because Notion couldn't be reached
    let hasToken: Bool
}

struct CCProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CCEntry {
        CCEntry(date: .now, board: Board(Self.sample), isStale: false, hasToken: true)
    }

    func snapshot(for configuration: CommandCenterConfig, in context: Context) async -> CCEntry {
        if context.isPreview {
            return CCEntry(date: .now, board: Board(Self.sample), isStale: false, hasToken: true)
        }
        return await load()
    }

    func timeline(for configuration: CommandCenterConfig, in context: Context) async -> Timeline<CCEntry> {
        Timeline(entries: [await load()], policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    private func load() async -> CCEntry {
        guard let token = TokenStore.load() else {
            return CCEntry(date: .now, board: Board(SharedStore.snapshot), isStale: false, hasToken: false)
        }
        do {
            let items = try await NotionClient(token: token).openItems()
            SharedStore.saveSnapshot(items)
            return CCEntry(date: .now, board: Board(items), isStale: false, hasToken: true)
        } catch {
            return CCEntry(date: SharedStore.snapshotDate ?? .now, board: Board(SharedStore.snapshot),
                           isStale: true, hasToken: true)
        }
    }

    static let sample: [Item] = [
        Item(id: "1", title: "GEICO: Your Payment is Due", type: "money", venture: "Personal",
             amount: 143, due: Item.dayFormatter.string(from: .now), trial: false, link: nil),
        Item(id: "2", title: "Robinhood: Statement is ready", type: "money", venture: "Shared/Household",
             amount: 413, due: nil, trial: false, link: nil),
        Item(id: "3", title: "Cloudflare: Renew SSL certificate", type: "todo", venture: "Credaxe",
             amount: nil, due: nil, trial: false, link: nil),
        Item(id: "4", title: "Capital One: Delhi trip details", type: "travel", venture: "Travel",
             amount: nil, due: nil, trial: false, link: nil),
    ]
}

// MARK: - Views

struct CommandCenterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CCEntry

    private var board: Board { entry.board }

    var body: some View {
        Group {
            if !entry.hasToken {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "key.fill").font(.title3).foregroundStyle(.secondary)
                    Text("Open Command Center to connect Notion.")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: list(maxRows: 3, showSections: false)
                default: list(maxRows: 8, showSections: true)
                }
            }
        }
        // System background in light/dark; iOS swaps in Liquid Glass when the
        // Home Screen uses the Clear or Tinted style.
        .containerBackground(.background, for: .widget)
    }

    // Header: the one bold element.
    private var header: some View {
        let due = board.dueNow.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(due)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(due > 0 ? .red : .primary)
                .contentTransition(.numericText())
                .widgetAccentable()
            Text(due > 0 ? "Due Now" : "All Clear")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(due > 0 ? .red : .primary)
            Spacer(minLength: 4)
            Text(entry.isStale ? "Offline" : "\(board.openCount) open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let top = board.urgentFirst.first {
                Text(top.cleanTitle)
                    .font(.subheadline)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Button(intent: MarkDoneIntent(itemID: top.id)) {
                    Label("Done", systemImage: "checkmark")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Spacer()
                Label("Nothing needs you", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func list(maxRows: Int, showSections: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if board.openCount == 0 {
                Spacer()
                Label("Nothing needs you", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
                Spacer()
            } else if showSections {
                let groups = fit(maxRows: maxRows)
                ForEach(groups) { group in
                    Label(group.lane.title.uppercased(), systemImage: group.lane.symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(group.lane.color)
                        .padding(.top, 2)
                    ForEach(group.items) { row($0) }
                }
                Spacer(minLength: 0)
                footer(shown: groups.reduce(0) { $0 + $1.items.count })
            } else {
                let rows = Array(board.urgentFirst.prefix(maxRows))
                ForEach(rows) { row($0) }
                Spacer(minLength: 0)
                footer(shown: rows.count)
            }
        }
    }

    /// Large: every section gets its top item first, leftovers go to the most urgent.
    private func fit(maxRows: Int) -> [LaneGroup] {
        let budget = board.lanes.count >= 5 ? maxRows - 1 : maxRows   // a 5th header costs a row
        var counts = board.lanes.map { _ in 0 }
        var used = 0
        for i in board.lanes.indices where used < budget { counts[i] = 1; used += 1 }
        for i in board.lanes.indices {
            while counts[i] > 0, counts[i] < board.lanes[i].items.count, used < budget {
                counts[i] += 1; used += 1
            }
        }
        return board.lanes.indices.compactMap { i in
            counts[i] > 0 ? LaneGroup(lane: board.lanes[i].lane, items: Array(board.lanes[i].items.prefix(counts[i]))) : nil
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 8) {
            Button(intent: MarkDoneIntent(itemID: item.id)) {
                Image(systemName: "circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.cleanTitle) done")

            Text(item.cleanTitle)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.isUrgent || (item.daysUntilDue ?? 1) < 0, let due = item.dueText {
                Text(due)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            } else if let amount = item.amountText {
                Text(amount)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func footer(shown: Int) -> some View {
        let hidden = board.openCount - shown
        return Text(hidden > 0 ? "\(hidden) more" : "Updated \(entry.date.formatted(date: .omitted, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

struct CommandCenterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CommandCenter", intent: CommandCenterConfig.self, provider: CCProvider()) { entry in
            CommandCenterWidgetView(entry: entry)
        }
        .configurationDisplayName("Command Center")
        .description("See what needs you today and check items off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
