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
                    openCard(group)
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

    /// The venture's colored card with its emails inside, each on a frosted
    /// glass tile (blurred, so the card behind barely shows through).
    private func openCard(_ group: VentureGroup) -> some View {
        let style = group.style
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: style.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(style.symbolColor)
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.22), in: .rect(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.short).font(.title.bold())
                    Text("\(group.items.count) open").font(.subheadline.weight(.medium)).opacity(0.9)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)

            VStack(spacing: 8) {
                ForEach(group.items) { item in
                    ItemRow(item: item, showBadge: false,
                            snoozed: store.board.snoozed.contains(item.id),
                            showDivider: false)
                        // Frosted glass: the venture color glows through softly,
                        // but blurred enough that the text stays easy to read.
                        .glassTile(radius: 18)
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
        }
        .padding(14)
        .padding(.top, 4)
        .background(alignment: .topTrailing) {
            Image(systemName: style.symbol)
                .font(.system(size: 92, weight: .bold))
                .foregroundStyle(style.symbolColor.opacity(0.16))
                .offset(x: 14, y: -12)
        }
        .background(style.fill, in: .rect(cornerRadius: 28, style: .continuous))
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
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
                        HStack(alignment: .center, spacing: 10) {
                            VentureBadge(venture: other.venture, size: 26, ring: nil)
                            Text(style.short).font(.headline)
                            Spacer()
                            Text("\(other.items.count) open")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let top = other.items.first {
                            Text(top.subject.isEmpty ? top.sender : "\(top.sender) · \(top.subject)")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                .padding(.leading, 36)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, minHeight: index == others.count - 1 ? 76 : 116, alignment: .topLeading)
                    // Muted on purpose: the open venture above is the one in focus.
                    .background { VentureWash(style: style, radius: 22) }
                    .shadow(color: .black.opacity(0.08), radius: 6, y: -2)
                }
                .buttonStyle(.plain)
                .offset(y: CGFloat(index) * 58)
            }
        }
        .frame(height: CGFloat(others.count - 1) * 58 + 76, alignment: .top)
    }
}
