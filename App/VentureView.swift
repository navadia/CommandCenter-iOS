import SwiftUI

/// One venture opened up as a big card with its emails; the other ventures
/// wait in a stack underneath, Wallet-style. Tap one to switch.
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
            VStack(spacing: 18) {
                if let group {
                    openCard(group)
                        .id(group.venture)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    Text("Nothing open here anymore.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
                if !others.isEmpty { stack }
            }
            .padding(16)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: current)
        }
        .scrollIndicators(.hidden)
        .background { SunriseBackground() }
        .navigationTitle("Ventures")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openItem) { EmailView(item: $0) }
    }

    private func openCard(_ group: VentureGroup) -> some View {
        let style = group.style
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: style.symbol)
                    .font(.title2.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.2), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(style.short).font(.title.bold())
                    Text("\(group.items.count) open").font(.subheadline.weight(.medium)).opacity(0.9)
                }
            }
            VStack(spacing: 8) {
                ForEach(group.items) { item in
                    Button { if item.messageID != nil { openItem = item } } label: {
                        HStack(spacing: 12) {
                            SenderAvatar(item: item, size: 40, showBadge: false)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.sender).font(.body.weight(.semibold)).lineLimit(1)
                                if !item.subject.isEmpty {
                                    Text(item.subject).font(.subheadline).opacity(0.9).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 2) {
                                if let amount = item.amountText {
                                    Text(amount).font(.subheadline.weight(.semibold)).monospacedDigit()
                                }
                                Text(item.whenText).font(.footnote).opacity(0.9)
                            }
                        }
                        .padding(12)
                        .background(.white.opacity(0.14), in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Mark Done", systemImage: "checkmark.circle") {
                            Task { await store.markDone([item.id]) }
                        }
                        Button("Later", systemImage: "moon") { store.snooze(item.id) }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            Image(systemName: style.symbol)
                .font(.system(size: 130, weight: .bold))
                .foregroundStyle(.white.opacity(0.12))
                .offset(x: 18, y: -10)
        }
        .background(style.fill, in: .rect(cornerRadius: 28))
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: style.color.opacity(0.35), radius: 18, y: 10)
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
                            Image(systemName: style.symbol).font(.title3).opacity(0.5)
                        }
                        if let top = other.items.first {
                            Text(top.subject.isEmpty ? top.sender : "\(top.sender) · \(top.subject)")
                                .font(.caption).opacity(0.9).lineLimit(1)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
                    .background(style.fill, in: .rect(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: -2)
                }
                .buttonStyle(.plain)
                .offset(y: CGFloat(index) * 58)
            }
        }
        .frame(height: CGFloat(others.count - 1) * 58 + 116, alignment: .top)
    }
}
