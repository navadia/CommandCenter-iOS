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
        let snoozed = SnoozeStore.activeIDs()
        guard let token = TokenStore.load() else {
            return CCEntry(date: .now, board: Board(SharedStore.snapshot, snoozed: snoozed), isStale: false, hasToken: false)
        }
        do {
            let items = try await NotionClient(token: token).openItems()
            SharedStore.saveSnapshot(items)
            let board = Board(items, snoozed: snoozed)
            // Icons for the rows the widget can show; letters if this is slow.
            await withTimeout(seconds: 6) {
                await SenderIcons.prefetch(board.urgentFirst.prefix(8).compactMap(\.domain), limit: 8)
            }
            return CCEntry(date: .now, board: board, isStale: false, hasToken: true)
        } catch {
            return CCEntry(date: SharedStore.snapshotDate ?? .now, board: Board(SharedStore.snapshot, snoozed: snoozed),
                           isStale: true, hasToken: true)
        }
    }

    private func withTimeout(seconds: Double, _ work: @escaping @Sendable () async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: .seconds(seconds)) }
            await group.next()
            group.cancelAll()
        }
    }

    static let sample: [Item] = [
        Item(id: "1", title: "GEICO: Your payment is due", type: "money", venture: "Personal",
             amount: 143, due: Item.dayFormatter.string(from: .now), trial: false, link: nil),
        Item(id: "2", title: "AWS: CloudWatch alarm: disk at 91%", type: "todo", venture: "Vishramo",
             amount: nil, due: nil, trial: false, link: nil),
        Item(id: "3", title: "Cloudflare: Renew SSL certificate", type: "todo", venture: "Credaxe",
             amount: nil, due: nil, trial: false, link: nil),
        Item(id: "4", title: "Express Energy: Your October bill is ready", type: "money", venture: "Shared/Household",
             amount: 167, due: nil, trial: false, link: nil),
        Item(id: "5", title: "Qatar Airways: Check-in opens", type: "travel", venture: "Travel",
             amount: nil, due: nil, trial: false, link: nil),
    ]
}

// MARK: - Views

struct CommandCenterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CCEntry

    private var board: Board { entry.board }
    private var top: Item? { board.needYou.first }

    var body: some View {
        Group {
            if !entry.hasToken {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "key.fill").font(.title3).foregroundStyle(.secondary)
                    Text("Open Command Center to connect Notion.").font(.subheadline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                switch family {
                case .systemSmall: small
                case .systemMedium: medium
                default: large
                }
            }
        }
        .containerBackground(for: .widget) { WidgetSunrise() }
    }

    // MARK: Header

    private var header: some View {
        let n = board.needYou.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(n)")
                .font(.system(.title, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .widgetAccentable()
            Text(n == 0 ? "All clear" : "need you")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            Text(entry.isStale ? "Offline" : "\(board.openCount) open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Large

    private var large: some View {
        let rows = Array((top == nil ? board.urgentFirst : Array(board.urgentFirst.dropFirst())).prefix(top == nil ? 7 : 5))
        return VStack(alignment: .leading, spacing: 8) {
            header
            if let top { topPanel(top) }
            if board.openCount == 0 {
                Spacer()
                allClearLine
                Spacer()
            } else {
                ForEach(rows) { row($0) }
                Spacer(minLength: 0)
                footer(shown: rows.count + (top == nil ? 0 : 1))
            }
        }
    }

    private func topPanel(_ item: Item) -> some View {
        HStack(spacing: 10) {
            SenderAvatar(item: item, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.amountText.map { "\(item.sender) · \($0)" } ?? item.sender)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(item.subject.isEmpty ? item.whenText : "\(item.whenText) · \(item.subject)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.isUrgent ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(intent: MarkDoneIntent(itemID: item.id)) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.onInk)
                    .frame(width: 36, height: 36)
                    .background(Color.ink, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.sender) done")
        }
        .padding(10)
        .background(.background.opacity(0.55), in: .rect(cornerRadius: 18))
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 9) {
            SenderAvatar(item: item, size: 26)
            Text("\(Text(item.sender).fontWeight(.semibold)) \(Text(item.subject).foregroundStyle(.secondary))")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(item.amountText ?? item.whenText)
                .font(.caption)
                .foregroundStyle((item.daysUntilDue ?? 1) < 0 ? Color.red : Color.secondary)
            Button(intent: MarkDoneIntent(itemID: item.id)) {
                Image(systemName: "circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(item.sender) done")
        }
    }

    private func footer(shown: Int) -> some View {
        let hidden = board.openCount - shown
        let updated = "Updated \(entry.date.formatted(date: .omitted, time: .shortened))"
        return Text(hidden > 0 ? "\(hidden) more · \(updated)" : updated)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    // MARK: Medium: venture cards

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if board.ventures.isEmpty {
                Spacer()
                allClearLine
                Spacer()
            } else {
                HStack(spacing: 8) {
                    ForEach(board.ventures.prefix(4)) { group in
                        let style = group.style
                        VStack(alignment: .leading, spacing: 2) {
                            Image(systemName: style.symbol).font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Text("\(group.items.count)")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                            Text(style.short)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(style.fill, in: .rect(cornerRadius: 16))
                    }
                }
            }
        }
    }

    // MARK: Small: the one thing

    @ViewBuilder
    private var small: some View {
        if let item = top ?? board.urgentFirst.first {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    SenderAvatar(item: item, size: 32)
                    Text(item.whenText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.isUrgent ? Color.red : Color.secondary)
                        .lineLimit(1)
                }
                Text(item.amountText.map { "\(item.sender) · \($0)" } ?? item.sender)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text(item.subject)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button(intent: MarkDoneIntent(itemID: item.id)) {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.onInk)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(Color.ink, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                SunMark(width: 48)
                Spacer(minLength: 0)
                Text("All clear").font(.title3.bold())
                Text("Nothing needs you").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var allClearLine: some View {
        HStack(spacing: 10) {
            SunMark(width: 36)
            Text("Nothing needs you").font(.subheadline.weight(.semibold))
        }
    }
}

/// A gentler sunrise for widgets (the system swaps it for glass in Clear/Tinted).
struct WidgetSunrise: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                Color.hex(0x17132F)
                RadialGradient(colors: [.brandOrange.opacity(0.3), .clear],
                               center: UnitPoint(x: 0.5, y: 1.2), startRadius: 0, endRadius: 260)
            } else {
                Color.hex(0xFFF7EE)
                RadialGradient(colors: [.hex(0xFFE0B5), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 260)
                RadialGradient(colors: [.hex(0xFFD3C8).opacity(0.8), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 220)
            }
        }
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
