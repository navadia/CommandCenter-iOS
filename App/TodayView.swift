import SwiftUI

/// The Briefing, as a native list: large title, sections, swipe to complete.
struct TodayView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var selection = Set<String>()
    @State private var editMode = EditMode.inactive
    @State private var showSettings = false

    private var board: Board { store.board }

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasToken {
                    ContentUnavailableView {
                        Label("Connect Notion", systemImage: "key.fill")
                    } description: {
                        Text("Add the Notion token your widget uses to see your items here.")
                    } actions: {
                        Button("Add Token") { showSettings = true }
                            .buttonStyle(.glassProminent)
                    }
                } else if board.openCount == 0 && board.power.isEmpty && !store.isLoading {
                    ContentUnavailableView("Nothing Needs You", systemImage: "checkmark.circle",
                                           description: Text("New items appear here as mail arrives."))
                } else {
                    list
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .environment(\.editMode, $editMode)
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }

    // MARK: - List

    private var list: some View {
        List(selection: $selection) {
            ForEach(board.power) { item in
                PowerCard(item: item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            ForEach(board.lanes) { group in
                Section {
                    ForEach(group.items) { item in
                        ItemRow(item: item, lane: group.lane)
                            .tag(item.id)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("Done", systemImage: "checkmark") {
                                    Task { await store.markDone([item.id]) }
                                }
                                .tint(.green)
                            }
                            .swipeActions(edge: .leading) {
                                if let url = item.emailURL {
                                    Button("Open Email", systemImage: "envelope.fill") { openURL(url) }
                                        .tint(.blue)
                                }
                            }
                            .contextMenu {
                                if let url = item.emailURL {
                                    Button("Open Email", systemImage: "envelope") { openURL(url) }
                                }
                                Button("Mark Done", systemImage: "checkmark.circle") {
                                    Task { await store.markDone([item.id]) }
                                }
                            }
                    }
                } header: {
                    Label(group.lane.title, systemImage: group.lane.symbol)
                        .foregroundStyle(group.lane.color)
                        .badge(group.items.count)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: store.items)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        if store.hasToken && board.openCount > 0 {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode.isEditing ? "Cancel" : "Select") {
                    withAnimation {
                        editMode = editMode.isEditing ? .inactive : .active
                        selection.removeAll()
                    }
                }
            }
        }
        if editMode.isEditing {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let ids = selection
                    withAnimation {
                        editMode = .inactive
                        selection.removeAll()
                    }
                    Task { await store.markDone(ids) }
                } label: {
                    Text(selection.isEmpty ? "Select Items" : "Mark \(selection.count) Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.green)
                .disabled(selection.isEmpty)
            }
        }
    }

    // MARK: - Header text

    private var title: String {
        let due = board.dueNow.count
        return due > 0 ? "\(due) Due Now" : "Today"
    }

    private var subtitle: String {
        var parts = [Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if store.isLoading {
            parts.append("Updating…")
        } else {
            parts.append("\(board.openCount) open")
        }
        return parts.joined(separator: " · ")
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

// MARK: - Rows

struct ItemRow: View {
    let item: Item
    let lane: Lane

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.cleanTitle)
                    .font(.body)
                    .lineLimit(2)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if item.isUrgent || (item.daysUntilDue ?? 1) < 0, let due = item.dueText {
                Text(due)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [item.venture]
        if let amount = item.amountText { parts.append(amount) }
        if let due = item.dueText, !(item.isUrgent || (item.daysUntilDue ?? 1) < 0) {
            parts.append(lane == .trials ? "Converts \(due.lowercased())" : "Due \(due.lowercased())")
        }
        return parts.joined(separator: " · ")
    }
}

struct PowerCard: View {
    let item: Item

    private var isHigh: Bool { item.title.contains("Running high") }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.title2)
                .foregroundStyle(isHigh ? .blue : .orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.cleanTitle)
                    .font(.headline)
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var caption: String {
        let end = item.due.flatMap { Item.dayFormatter.date(from: String($0.prefix(10))) }
        let endText = end?.formatted(.dateTime.month(.abbreviated).day()) ?? "soon"
        return isHigh
            ? "Cycle ends \(endText) · each kWh over 1,000 costs about 21¢"
            : "Cycle ends \(endText) · stay above 1,000 kWh for the $125 credit"
    }
}
