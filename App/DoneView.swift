import SwiftUI

/// Everything marked done in the last week, newest first, by day: what you
/// ticked off and what the email sorter closed by itself (with the reason).
/// Tap to read the email or edit; Undo puts it back on the list.
struct DoneView: View {
    @Environment(ItemStore.self) private var store
    @State private var openMail: Item?
    @State private var reopening: Set<String> = []

    private var days: [(day: Date, items: [Item])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.recentlyDone) { cal.startOfDay(for: doneAt($0) ?? .distantPast) }
        return groups.keys.sorted(by: >).map { day in
            (day, (groups[day] ?? []).sorted { (doneAt($0) ?? .distantPast) > (doneAt($1) ?? .distantPast) })
        }
    }

    var body: some View {
        List {
            if store.doneLoaded && store.recentlyDone.isEmpty {
                ContentUnavailableView("Nothing Done Yet", systemImage: "checkmark.circle",
                                       description: Text("Items you mark done, and ones closed by a payment or cancellation email, show here for a week."))
            } else if !store.doneLoaded {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
            ForEach(days, id: \.day) { group in
                Section(dayTitle(group.day)) {
                    ForEach(group.items) { item in
                        row(item)
                            .contentShape(.rect)
                            .onTapGesture { if item.messageID != nil { openMail = item } }
                            .swipeActions(edge: .trailing) {
                                Button("Undo", systemImage: "arrow.uturn.backward") { reopen(item) }
                                    .tint(.orange)
                            }
                            .contextMenu {
                                Button("Undo — Put It Back", systemImage: "arrow.uturn.backward") { reopen(item) }
                                if item.messageID != nil {
                                    Button("Open Email", systemImage: "envelope") { openMail = item }
                                }
                            }
                    }
                }
            }
            if !store.recentlyDone.isEmpty {
                Text("The last 7 days. Swipe left on one to put it back on your list.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $openMail) { EmailView(item: $0) }
        .refreshable { await store.loadDone() }
        .task { await store.loadDone() }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            SenderAvatar(item: item, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sender).font(.body.weight(.semibold)).lineLimit(2)
                if !item.subject.isEmpty {
                    Text(item.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                if item.closedByItself {
                    Text("Closed by itself · \(item.noteText)")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                if let amount = item.amountText {
                    Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if reopening.contains(item.id) {
                    ProgressView().controlSize(.small)
                } else if let at = doneAt(item) {
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .opacity(reopening.contains(item.id) ? 0.5 : 1)
    }

    private func reopen(_ item: Item) {
        reopening.insert(item.id)
        Task {
            await store.reopen(item)
            reopening.remove(item.id)
        }
    }

    private func doneAt(_ item: Item) -> Date? {
        guard let s = item.edited else { return nil }
        return ISO8601DateFormatter.notion.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func dayTitle(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        if day == .distantPast { return "Earlier" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}
