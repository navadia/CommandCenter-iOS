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
    @State private var capture = CaptureCenter.shared

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
            .background { AppBackground() }
            .toolbar { toolbar }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $openItem) { EmailView(item: $0) }
            .navigationDestination(item: $openVenture) { VentureView(venture: $0) }
            .refreshable { await store.refresh() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: Bindable(capture).request) { AddTaskSheet(request: $0) }
            .fullScreenCover(isPresented: $showFocus) { FocusView() }
            .alert("Something went wrong", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
        .task {
            await store.refresh()
            if DemoData.isOn {
                if ProcessInfo.processInfo.arguments.contains("-demoFocus") { showFocus = true }
                if ProcessInfo.processInfo.arguments.contains("-demoSettings") { showSettings = true }
                if let venture = DemoData.argument(after: "-demoVenture") { openVenture = venture }
                if let id = DemoData.argument(after: "-demoEdit"), let item = store.items.first(where: { $0.id == id }) {
                    edit(item)
                }
                if let words = DemoData.argument(after: "-demoAdd") {
                    CaptureCenter.shared.request = CaptureRequest(input: .text(words), kind: .voice)
                }
            }
        }
        .onOpenURL { url in Task { await open(url) } }
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
                              onOpen: { if top.messageID != nil { openItem = top } else { edit(top) } },
                              onDone: { done([top.id]) })
                        .contextMenu { menu(for: top) }
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
        } else if store.hasToken && !store.isLoading && board.openCount == 0 {
            // Nothing urgent but items open: no card at all (the headline says it).
            // Only a completely empty list gets the "All clear" card.
            HStack(spacing: 16) {
                SunMark(width: 54)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All clear").font(.headline)
                    Text("New mail shows up here as it arrives.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .card(radius: 28)
            .padding(.horizontal, 16)
        }
    }

    private func peekCard(depth: Int) -> some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.clear)
            .card(radius: 28)
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
            .padding(.vertical, 4)
            .card(radius: 26)
            .padding(.horizontal, 16)
        }
        .animation(.default, value: board.rest.map(\.id))
    }

    private func tap(_ item: Item) {
        if selecting {
            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        } else if item.messageID != nil {
            openItem = item
        } else {
            edit(item)          // added by hand: no email, so open it to edit
        }
    }

    @ViewBuilder
    private func menu(for item: Item) -> some View {
        Button("Edit", systemImage: "pencil") { edit(item) }
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

    /// Links from Bark notifications:
    ///   commandcenter://today                 Today
    ///   commandcenter://item/<notion page id> that item's email (or its edit sheet)
    ///   commandcenter://mail?id=<msg id>&title=…   one email that isn't a row (FYI mail)
    private func open(_ url: URL) async {
        guard url.scheme == "commandcenter" else { return }
        showFocus = false
        showSettings = false
        capture.request = nil
        openVenture = nil
        openItem = nil
        switch url.host() {
        case "item":
            let wanted = url.lastPathComponent.replacingOccurrences(of: "-", with: "")
            let match = { store.items.first { $0.id.replacingOccurrences(of: "-", with: "") == wanted } }
            if match() == nil { await store.refresh() }
            guard let item = match() else { return }
            if item.messageID != nil { openItem = item } else { edit(item) }
        case "mail":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let id = query.first(where: { $0.name == "id" })?.value, !id.isEmpty else { return }
            let title = query.first(where: { $0.name == "title" })?.value ?? "Email"
            let link = "https://mail.google.com/mail/u/0/#search/rfc822msgid:" +
                (id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id)
            openItem = Item(id: "mail-\(id)", title: title, type: "todo", venture: "Personal",
                            amount: nil, due: nil, trial: false, link: link)
        default:
            break      // "today": the reset above is all it needs
        }
    }

    private func edit(_ item: Item) {
        capture.request = CaptureRequest(input: .edit(item), kind: .typed)
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
        if store.hasToken && !selecting {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Task", systemImage: "plus") {
                    CaptureCenter.shared.request = CaptureRequest(input: .text(""), kind: .typed)
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
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
                        .foregroundStyle(Color.onInk)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(.ink)
                .disabled(selection.isEmpty)
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Connect Notion", systemImage: "key.fill").font(.headline)
            Text("Add the Notion token your widget uses to see your items here.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button { showSettings = true } label: { Text("Add Token").foregroundStyle(Color.onInk) }
                .buttonStyle(.glassProminent)
                .tint(.ink)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 28)
        .padding(.horizontal, 16)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }
}

// MARK: - Pieces

struct ItemRow: View {
    let item: Item
    var showBadge = true
    var selecting = false
    var selected = false
    var snoozed = false
    var showDivider = true

    var body: some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.ink : Color.secondary)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            SenderAvatar(item: item, size: 40, showBadge: showBadge)
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
            .frame(minHeight: 64)
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
            HStack(alignment: .center, spacing: 8) {
                VentureBadge(venture: group.venture, size: 28, ring: nil)
                Spacer(minLength: 0)
                Text("\(group.items.count)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(style.short).font(.headline).lineLimit(1)
            if let top = group.items.first {
                Text(top.sender)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 140, height: 104, alignment: .topLeading)
        .background { VentureWash(style: style, radius: 20) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(style.short), \(group.items.count) open")
    }
}

/// The electricity row from the power check: one bar from 0 to the goal
/// (solid = used so far, dashed = where this pace ends, white tick = 1,000 kWh)
/// and one line saying what to do. Rows written before the check sent its
/// numbers fall back to the old text.
struct PowerCard: View {
    let item: Item

    var body: some View {
        Group {
            if let data = item.powerData { full(data) } else { legacy }
        }
        .padding(16)
        .card(radius: 24)
        .padding(.horizontal, 16)
    }

    // MARK: Progress bar

    private func full(_ d: PowerData) -> some View {
        let tint = d.tint
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                bolt(tint)
                Text("Electricity").font(.headline)
                Spacer(minLength: 8)
                Text(d.pill)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.16), in: .capsule)
            }
            PowerBar(data: d, tint: tint)
                .frame(height: 12)
                .padding(.top, 22)
                .padding(.bottom, 8)
            HStack {
                Text("\(Text("\(Int(d.used.rounded()))").fontWeight(.semibold)) used")
                Spacer()
                Text("on pace for \(d.proj.formatted())").foregroundStyle(.secondary)
                Spacer()
                Text(d.goal.formatted()).fontWeight(.semibold)
            }
            .font(.footnote)
            .monospacedDigit()
            footer(d)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func footer(_ d: PowerData) -> Text {
        let ends = "\(d.left) day\(d.left == 1 ? "" : "s") left · ends \(d.endText)"
        switch d.state {
        case "low":
            let perDay = Int((d.perday ?? 0).rounded())
            return Text("Use about \(Text("\(perDay) kWh a day").fontWeight(.semibold).foregroundStyle(.primary)) (now \(Int(d.pace.rounded()))) · \(ends)")
        case "high":
            return Text("Each kWh over 1,000 costs about \(Int((d.rate ?? 22).rounded()))¢ · \(ends)")
        default:
            return Text("Above 1,000 at this pace · \(ends)")
        }
    }

    private func bolt(_ tint: Color) -> some View {
        Image(systemName: "bolt.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Color.night)
            .frame(width: 30, height: 30)
            .background(tint, in: .circle)
    }

    // MARK: Before the power check sent numbers

    private var legacy: some View {
        HStack(spacing: 14) {
            bolt(.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.cleanTitle).font(.headline)
                Text("Stay above 1,000 kWh for the $125 credit").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Solid capsule for what's used, dashes out to the projection, a white tick at the goal.
private struct PowerBar: View {
    let data: PowerData
    let tint: Color

    var body: some View {
        Canvas { ctx, size in
            let scale = max(Double(data.goal), Double(data.proj), data.used) * (data.proj > data.goal ? 1.06 : 1.0)
            let x = { (v: Double) in size.width * min(max(v / scale, 0), 1) }
            let h = size.height
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: h), cornerRadius: h / 2),
                     with: .color(Color(uiColor: .tertiarySystemFill)))
            // Dashes from today to where this pace ends.
            var dash = x(data.used) + 3
            let end = x(Double(data.proj))
            while dash + 4 <= end {
                ctx.fill(Path(roundedRect: CGRect(x: dash, y: 0, width: 5, height: h), cornerRadius: 1.5),
                         with: .color(tint.opacity(0.45)))
                dash += 9
            }
            let used = max(x(data.used), h)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: used, height: h), cornerRadius: h / 2), with: .color(tint))
            // The 1,000 kWh line.
            let g = x(Double(data.goal))
            ctx.fill(Path(roundedRect: CGRect(x: min(g, size.width - 2), y: -6, width: 2, height: h + 12), cornerRadius: 1),
                     with: .color(.primary))
        }
        .accessibilityLabel("\(Int(data.used.rounded())) of \(data.goal) kilowatt hours used, on pace for \(data.proj)")
    }
}
