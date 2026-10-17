import SwiftUI

/// Today: what needs you (one card at a time), your ventures, then everything else.
struct TodayView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var openItem: Item?
    @State private var openVenture: String?
    @State private var showSettings = false
    @State private var showFocus = false
    @State private var selecting = false
    @State private var selection = Set<String>()

    private var board: Board { store.board }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if !store.hasToken {
                        connectCard
                    } else {
                        ForEach(board.power) { PowerCard(item: $0) }
                        needYou
                        if !board.ventures.isEmpty { venturesRow }
                        if !board.rest.isEmpty { everythingElse }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background { SunriseBackground() }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openItem) { EmailView(item: $0) }
            .navigationDestination(item: $openVenture) { VentureView(venture: $0) }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showFocus) { FocusView() }
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(greeting)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(headline)
                .font(.system(size: 34, weight: .bold))
                .contentTransition(.numericText())
            if store.isLoading {
                Text("Updating…").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .animation(.default, value: board.needYou.count)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<12: "Good morning"
        case ..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    private var headline: String {
        switch board.needYou.count {
        case 0: board.openCount == 0 ? "All clear" : "Nothing urgent"
        case 1: "1 thing needs you"
        case let n: "\(n) things need you"
        }
    }

    // MARK: - Need you (card stack)

    @ViewBuilder
    private var needYou: some View {
        if let top = board.needYou.first {
            VStack(spacing: 8) {
                SwipeToDecide(onDone: { done([top.id]) }, onLater: { store.snooze(top.id) }) {
                    FocusCard(item: top,
                              onLater: { withAnimation { store.snooze(top.id) } },
                              onOpen: { openItem = top },
                              onDone: { done([top.id]) })
                }
                .id(top.id)
                .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                        removal: .opacity))
                .background {
                    // The next cards peeking out underneath.
                    ZStack {
                        if board.needYou.count > 2 { peekCard(depth: 2) }
                        if board.needYou.count > 1 { peekCard(depth: 1) }
                    }
                }
                .padding(.bottom, CGFloat(min(board.needYou.count - 1, 2)) * 12)
                Text(board.needYou.count > 1
                     ? "1 of \(board.needYou.count) · swipe right when done, left for later"
                     : "Swipe right when done, left for later")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: top.id)
        } else if store.hasToken && !store.isLoading {
            HStack(spacing: 16) {
                SunMark(width: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text(board.openCount == 0 ? "All clear" : "Nothing due soon").font(.headline)
                    Text(board.openCount == 0 ? "New mail shows up here as it arrives."
                                              : "\(board.openCount) open below whenever you have a minute.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .padding(.horizontal, 16)
        }
    }

    private func peekCard(depth: Int) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.clear)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
            .opacity(depth == 1 ? 0.9 : 0.55)
            .padding(.horizontal, CGFloat(depth) * 13)
            .offset(y: CGFloat(depth) * 12)
            .allowsHitTesting(false)
    }

    // MARK: - Ventures

    private var venturesRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ventures")
                .font(.title2.bold())
                .padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(board.ventures) { group in
                        Button { openVenture = group.venture } label: {
                            VentureCard(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Everything else

    private var everythingElse: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Everything else")
                .font(.title2.bold())
                .padding(.horizontal, 20)
            VStack(spacing: 0) {
                ForEach(Array(board.rest.enumerated()), id: \.element.id) { index, item in
                    ItemRow(item: item,
                            selecting: selecting,
                            selected: selection.contains(item.id),
                            snoozed: board.snoozed.contains(item.id),
                            showDivider: index < board.rest.count - 1)
                        .contentShape(.rect)
                        .onTapGesture { tap(item) }
                        .contextMenu { menu(for: item) }
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 26))
            .padding(.horizontal, 16)
        }
        .animation(.default, value: board.rest.map(\.id))
    }

    private func tap(_ item: Item) {
        if selecting {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else if item.messageID != nil {
            openItem = item
        }
    }

    @ViewBuilder
    private func menu(for item: Item) -> some View {
        if item.messageID != nil {
            Button("Open Email", systemImage: "envelope") { openItem = item }
        }
        Button("Mark Done", systemImage: "checkmark.circle") { done([item.id]) }
        if board.snoozed.contains(item.id) {
            Button("Bring Back", systemImage: "sun.max") { store.unsnooze(item.id) }
        } else {
            Button("Later", systemImage: "moon") { store.snooze(item.id) }
        }
    }

    private func done(_ ids: Set<String>) {
        withAnimation { Task { await store.markDone(ids) } }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Settings", systemImage: "gearshape") { showSettings = true }
        }
        if store.hasToken && board.openCount > 0 {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Focus", systemImage: "rectangle.stack") { showFocus = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Cancel" : "Select") {
                    withAnimation {
                        selecting.toggle()
                        selection.removeAll()
                    }
                }
            }
        }
        if selecting {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    let ids = selection
                    withAnimation {
                        selecting = false
                        selection.removeAll()
                    }
                    done(ids)
                } label: {
                    Text(selection.isEmpty ? "Select Items" : "Mark \(selection.count) Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.night)
                .disabled(selection.isEmpty)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect Notion", systemImage: "key.fill").font(.headline)
            Text("Add the Notion token your widget uses to see your items here.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Add Token") { showSettings = true }
                .buttonStyle(.glassProminent)
                .tint(.night)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 16)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

// MARK: - Pieces

struct ItemRow: View {
    let item: Item
    var selecting = false
    var selected = false
    var snoozed = false
    var showDivider = true

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.night : Color.secondary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            SenderAvatar(item: item, size: 40)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sender)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if !item.subject.isEmpty {
                        Text(item.subject)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    if let amount = item.amountText {
                        Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    HStack(spacing: 4) {
                        if snoozed { Image(systemName: "moon.fill").foregroundStyle(.indigo) }
                        Text(item.whenText)
                    }
                    .font(.footnote)
                    .foregroundStyle((item.daysUntilDue ?? 1) < 0 ? Color.red : Color.secondary)
                }
            }
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
                if showDivider { Divider() }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .accessibilityElement(children: .combine)
    }
}

struct VentureCard: View {
    let group: VentureGroup

    var body: some View {
        let style = group.style
        VStack(alignment: .leading, spacing: 2) {
            Text(style.short).font(.headline)
            Text("\(group.items.count) open").font(.caption.weight(.semibold)).opacity(0.85)
            Spacer(minLength: 0)
            if let top = group.items.first {
                Text(top.subject.isEmpty ? top.sender : "\(top.sender) · \(top.subject)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(12)
        .frame(width: 156, height: 110, alignment: .topLeading)
        .background(alignment: .bottomTrailing) {
            Image(systemName: style.symbol)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white.opacity(0.2))
                .offset(x: 10, y: 12)
        }
        .background(style.fill, in: .rect(cornerRadius: 20))
        .clipShape(.rect(cornerRadius: 20))
        .shadow(color: style.color.opacity(0.3), radius: 10, y: 6)
    }
}

struct PowerCard: View {
    let item: Item

    private var isHigh: Bool { item.title.contains("Running high") }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "bolt.fill")
                .font(.headline)
                .foregroundStyle(Color.night)
                .frame(width: 36, height: 36)
                .background(Color.amber, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.cleanTitle).font(.headline)
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 16)
    }

    private var caption: String {
        let end = item.due.flatMap { Item.dayFormatter.date(from: String($0.prefix(10))) }
        let endText = end?.formatted(.dateTime.month(.abbreviated).day()) ?? "soon"
        return isHigh
            ? "Cycle ends \(endText) · each kWh over 1,000 costs about 21¢"
            : "Cycle ends \(endText) · stay above 1,000 kWh for the $125 credit"
    }
}
