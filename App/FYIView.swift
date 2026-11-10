import SwiftUI

/// Everything the email sorter filed as "for your information": receipts,
/// sign-in notices, statements, delivery mail. Newest first, by day. Tap one
/// to read it; swipe or long-press to turn it into a task if it matters.
struct FYIView: View {
    @Environment(ItemStore.self) private var store
    @State private var query = ""
    @State private var openMail: Item?
    @State private var madeTask: String?
    @State private var error: String?

    private var shown: [FYIMail] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.fyi }
        return store.fyi.filter {
            $0.title.lowercased().contains(q) || $0.from.lowercased().contains(q)
                || VentureStyle.of($0.venture).short.lowercased().contains(q)
        }
    }

    private var days: [(day: Date, mail: [FYIMail])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: shown) { cal.startOfDay(for: $0.received ?? .distantPast) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if store.fyiLoaded && store.fyi.isEmpty {
                ContentUnavailableView("No FYI Mail", systemImage: "tray",
                                       description: Text("Receipts, notices and sign-in alerts land here. Nothing needs you."))
            } else if !store.fyiLoaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(days, id: \.day) { group in
                Section(dayTitle(group.day)) {
                    ForEach(group.mail) { mail in
                        Button { openMail = mail.asItem } label: { row(mail) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button("Make Task", systemImage: "plus.circle") { Task { await makeTask(mail) } }
                                    .tint(.ink)
                            }
                            .contextMenu {
                                Button("Make It a Task", systemImage: "plus.circle") { Task { await makeTask(mail) } }
                                if mail.link != nil {
                                    Button("Open Email", systemImage: "envelope") { openMail = mail.asItem }
                                }
                            }
                    }
                }
            }
            if !store.fyi.isEmpty && query.isEmpty {
                Text("Kept for two weeks. Swipe right on one to make it a task.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .searchable(text: $query, prompt: "Search FYI")
        .navigationTitle("FYI")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $openMail) { EmailView(item: $0) }
        .refreshable { await store.loadFYI() }
        .task { if !store.fyiLoaded { await store.loadFYI() } }
        .sensoryFeedback(.success, trigger: madeTask)
        .overlay(alignment: .bottom) {
            if let madeTask {
                Label("Added to \(madeTask)", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect()
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: madeTask)
        .alert("Couldn't add it", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func row(_ mail: FYIMail) -> some View {
        HStack(spacing: 12) {
            SenderAvatar(item: mail.asItem, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(mail.sender).font(.body.weight(.semibold)).lineLimit(1)
                    if mail.security {
                        Image(systemName: "lock.shield.fill").foregroundStyle(.orange).font(.footnote)
                            .accessibilityLabel("Security notice")
                    }
                    if mail.paid {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.footnote)
                            .accessibilityLabel("Payment received")
                    }
                    if mail.count > 1 {
                        Text("×\(mail.count)").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(mail.subject.isEmpty ? mail.title : mail.subject)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if let date = mail.received {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if day == .distantPast { return "Earlier" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func makeTask(_ mail: FYIMail) async {
        do {
            try await store.makeTask(from: mail)
            madeTask = VentureStyle.of(mail.venture).short
            try? await Task.sleep(for: .seconds(2))
            madeTask = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
