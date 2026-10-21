import SwiftUI

/// Focus: every open email, one big card at a time. Swipe right (or Done)
/// to finish it, left (or Later) to put it off until tomorrow morning.
struct FocusView: View {
    @Environment(ItemStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Item] = []
    @State private var index = 0
    @State private var doneCount = 0
    @State private var laterCount = 0
    @State private var openItem: Item?
    @State private var editing: Item?

    private var current: Item? { index < queue.count ? queue[index] : nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if !queue.isEmpty {
                    ProgressView(value: Double(min(index, queue.count)), total: Double(queue.count))
                        .tint(.brandOrange)
                        .padding(.horizontal, 4)
                }
                if let item = current {
                    SwipeToDecide(onDone: { finish(item) }, onLater: { later(item) }) {
                        FocusCard(item: item, large: true,
                                  onLater: { later(item) }, onOpen: { open(item) }, onDone: { finish(item) })
                            .frame(maxHeight: .infinity)
                    }
                    .id(item.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
                    .background {
                        if index + 1 < queue.count {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(.clear)
                                .card(radius: 34)
                                .opacity(0.6)
                                .padding(.horizontal, 16)
                                .offset(y: 14)
                        }
                    }
                    .padding(.bottom, 14)

                    HStack(spacing: 28) {
                        circleButton("Later", systemImage: "clock") { later(item) }
                        if item.messageID == nil {
                            circleButton("Edit", systemImage: "pencil") { editing = item }
                        } else {
                            circleButton("Open", systemImage: "envelope") { openItem = item }
                        }
                        circleButton("Done", systemImage: "checkmark", prominent: true) { finish(item) }
                    }
                } else {
                    Spacer()
                    allClear
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .animation(.spring(response: 0.4, dampingFraction: 0.82), value: index)
            .background { AppBackground() }
            .navigationTitle("Focus")
            .navigationSubtitle(current == nil ? "Finished" : "\(index + 1) of \(queue.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .navigationDestination(item: $openItem) { EmailView(item: $0) }
            .toolbar {
                if let item = current {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit", systemImage: "pencil") { editing = item }
                    }
                }
            }
            .sheet(item: $editing, onDismiss: syncCurrent) {
                AddTaskSheet(request: CaptureRequest(input: .edit($0), kind: .typed))
            }
        }
        .onAppear { queue = store.board.focusQueue }
        .sensoryFeedback(.success, trigger: doneCount)
    }

    private func open(_ item: Item) {
        if item.messageID != nil { openItem = item } else { editing = item }
    }

    /// After an edit: show the new text, or move on if it was marked done there.
    private func syncCurrent() {
        guard let item = current else { return }
        if let fresh = store.items.first(where: { $0.id == item.id }) {
            queue[index] = fresh
        } else {
            withAnimation { index += 1 }
        }
    }

    private func finish(_ item: Item) {
        doneCount += 1
        index += 1
        Task { await store.markDone([item.id]) }
    }

    private func later(_ item: Item) {
        laterCount += 1
        index += 1
        store.snooze(item.id)
    }

    private func circleButton(_ title: String, systemImage: String, prominent: Bool = false,
                              action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            if prominent {
                Button(action: action) {
                    Image(systemName: systemImage).font(.title2.bold()).foregroundStyle(Color.onInk)
                        .frame(width: 64, height: 64)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(.ink)
            } else {
                Button(action: action) {
                    Image(systemName: systemImage).font(.title2.weight(.semibold)).frame(width: 64, height: 64)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
            Text(title).font(.footnote.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var allClear: some View {
        VStack(spacing: 12) {
            SunMark(width: 88)
            Text("All clear").font(.largeTitle.bold())
            Text(queue.isEmpty ? "Nothing to go through right now."
                               : "\(doneCount) done · \(laterCount) for tomorrow")
                .font(.body)
                .foregroundStyle(.secondary)
            Button { dismiss() } label: { Text("Back to Today").foregroundStyle(Color.onInk) }
                .buttonStyle(.glassProminent)
                .tint(.ink)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .card(radius: 34)
    }
}
