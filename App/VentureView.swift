import SwiftUI

/// One venture: a colored header, its emails on a plain card, and the other
/// ventures stacked underneath like passes in Wallet. Tap one to switch.
struct VentureView: View {
    @Environment(ItemStore.self) private var store
    @State private var current: String
    @State private var openItem: Item?

    init(venture: String) {
        _current = State(initialValue: venture)
    }

    private var groups: [VentureGroup] { store.board.ventures }
    private var group: VentureGroup? { groups.first { $0.venture == current } }
    private var others: [VentureGroup] { groups.filter { $0.venture != current } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let group {
                    header(group)
                    list(group)
                } else {
                    Text("Nothing open here anymore.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                if !others.isEmpty {
                    Text("Other ventures")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .padding(.leading, 4)
                    stack
                }
            }
            .padding(16)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: current)
        }
        .scrollIndicators(.hidden)
        .background { AppBackground() }
        .navigationTitle(VentureStyle.of(current).short)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openItem) { EmailView(item: $0) }
    }

    private func header(_ group: VentureGroup) -> some View {
        let style = group.style
        return HStack(spacing: 14) {
            Image(systemName: style.symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.22), in: .rect(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(style.short).font(.title.bold())
                Text("\(group.items.count) open").font(.subheadline.weight(.medium)).opacity(0.9)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(style.fill, in: .rect(cornerRadius: 26, style: .continuous))
    }

    private func list(_ group: VentureGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                ItemRow(item: item, showBadge: false,
                        snoozed: store.board.snoozed.contains(item.id),
                        showDivider: index < group.items.count - 1)
                    .contentShape(.rect)
                    .onTapGesture { if item.messageID != nil { openItem = item } }
                    .contextMenu {
                        if item.messageID != nil {
                            Button("Open Email", systemImage: "envelope") { openItem = item }
                        }
                        Button("Mark Done", systemImage: "checkmark.circle") {
                            Task { await store.markDone([item.id]) }
                        }
                        Button("Later", systemImage: "moon") { store.snooze(item.id) }
                    }
            }
        }
        .padding(.vertical, 4)
        .card(radius: 26)
    }

    /// The other ventures, overlapping like passes in Wallet.
    private var stack: some View {
        ZStack(alignment: .top) {
            ForEach(Array(others.enumerated()), id: \.element.id) { index, other in
                let style = other.style
                Button {
                    current = other.venture
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(style.short).font(.headline)
                            Text("\(other.items.count) open").font(.caption.weight(.semibold)).opacity(0.85)
                            Spacer()
                            Image(systemName: style.symbol).font(.title3).opacity(0.6)
                        }
                        if let top = other.items.first {
                            Text(top.subject.isEmpty ? top.sender : "\(top.sender) · \(top.subject)")
                                .font(.caption).opacity(0.9).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    .frame(maxWidth: .infinity, minHeight: index == others.count - 1 ? 76 : 116, alignment: .topLeading)
                    .background(style.fill, in: .rect(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.10), radius: 5, y: -2)
                }
                .buttonStyle(.plain)
                .offset(y: CGFloat(index) * 58)
            }
        }
        .frame(height: CGFloat(others.count - 1) * 58 + 76, alignment: .top)
    }
}
