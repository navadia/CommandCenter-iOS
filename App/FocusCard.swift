import SwiftUI

/// The big card for one email: who, which venture, when, how much, a preview
/// of the email, and Later / Open / Done. Used at the top of Today and in Focus.
struct FocusCard: View {
    let item: Item
    var large = false
    var onLater: () -> Void
    var onOpen: () -> Void
    var onDone: () -> Void

    @Environment(ItemStore.self) private var store
    @State private var preview: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SenderAvatar(item: item, size: large ? 56 : 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sender)
                        .font(large ? .title2.bold() : .headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(VentureStyle.of(item.venture).short)
                        if !item.whenText.isEmpty {
                            Text("·")
                            Text(item.whenText)
                                .foregroundStyle(item.isUrgent || (item.daysUntilDue ?? 1) < 0 ? Color.red : Color.secondary)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !large, let amount = item.amountText {
                    Text(amount)
                        .font(.title2.bold())
                        .monospacedDigit()
                }
            }

            Text(item.subject.isEmpty ? item.cleanTitle : item.subject)
                .font(large ? .system(size: 26, weight: .bold) : .title3.weight(.semibold))
                .lineLimit(large ? 4 : 2)
                .padding(.top, large ? 20 : 12)

            if large, let amount = item.amountText {
                Text(amount)
                    .font(.system(size: 44, weight: .bold))
                    .monospacedDigit()
                    .padding(.top, 10)
            }

            if let preview, !preview.isEmpty {
                Text(preview)
                    .font(large ? .body : .subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(large ? 6 : 2)
                    .padding(.top, large ? 14 : 6)
                    .transition(.opacity)
            }

            if large { Spacer(minLength: 16) }

            if !large {
                HStack(spacing: 8) {
                    Button(action: onLater) {
                        Text("Later").fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    Button(action: onOpen) {
                        Text("Open").fontWeight(.semibold).lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(item.messageID == nil)
                    Button(action: onDone) {
                        Text("Done")
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .foregroundStyle(Color.onInk)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.ink)
                }
                .controlSize(.large)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            } else {
                HStack {
                    Label("Swipe to snooze", systemImage: "arrow.left")
                    Spacer()
                    Label("Swipe when done", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(large ? 22 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: large ? 34 : 28)
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.25), value: preview)
        .task(id: item.id) {
            preview = nil
            guard store.hasGmail, let id = item.messageID else { return }
            preview = try? await MailService.shared.message(id: id).previewText
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// Wraps a card so it can be flung right (done) or left (later).
struct SwipeToDecide<Content: View>: View {
    var onDone: () -> Void
    var onLater: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGSize = .zero
    private let threshold: CGFloat = 110

    var body: some View {
        content
            .overlay(alignment: .topLeading) {
                stamp("Done", systemImage: "checkmark.circle.fill", color: .green)
                    .opacity(Double(max(0, offset.width) / threshold))
                    .padding(18)
            }
            .overlay(alignment: .topTrailing) {
                stamp("Later", systemImage: "moon.fill", color: .indigo)
                    .opacity(Double(max(0, -offset.width) / threshold))
                    .padding(18)
            }
            .offset(x: offset.width, y: offset.height * 0.15)
            .rotationEffect(.degrees(Double(offset.width / 24)), anchor: .bottom)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { offset = $0.translation }
                    .onEnded { value in
                        if value.translation.width > threshold || value.predictedEndTranslation.width > threshold * 2.5 {
                            fling(right: true)
                        } else if value.translation.width < -threshold || value.predictedEndTranslation.width < -threshold * 2.5 {
                            fling(right: false)
                        } else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { offset = .zero }
                        }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: abs(offset.width) > threshold)
    }

    private func stamp(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color, in: .capsule)
    }

    private func fling(right: Bool) {
        withAnimation(.easeIn(duration: 0.2)) {
            offset = CGSize(width: right ? 700 : -700, height: offset.height)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            if right { onDone() } else { onLater() }
            offset = .zero
        }
    }
}
