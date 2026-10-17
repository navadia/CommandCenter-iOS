import SwiftUI

/// Round sender picture (website icon, or a Contacts-style monogram) with a
/// small venture badge in the corner: who sent it and what it's about.
struct SenderAvatar: View {
    let item: Item
    var size: CGFloat = 40
    var showBadge = true
    /// The surface behind the avatar, so the badge's ring blends in.
    var ring: Color = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            face
                .frame(width: size, height: size)
                .clipShape(Circle())
            if showBadge {
                VentureBadge(venture: item.venture, size: size * 0.46, ring: ring)
                    .offset(x: size * 0.08, y: size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var face: some View {
        if let icon = SenderIcons.image(for: item.domain) {
            Image(uiImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(size * 0.17)
                .frame(width: size, height: size)
                .background(Color.white)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        } else {
            // Like a contact without a photo.
            Text(item.initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [.hex(0xA5ABB8), .hex(0x858A95)],
                                           startPoint: .top, endPoint: .bottom))
        }
    }
}

/// The venture's color tile with its symbol, like a Settings icon.
struct VentureBadge: View {
    let venture: String
    var size: CGFloat = 20
    var ring: Color? = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        let style = VentureStyle.of(venture)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(style.fill)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(style.symbolColor)
            }
            .overlay {
                if let ring {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(ring, lineWidth: max(1.5, size * 0.09))
                }
            }
            .frame(width: size, height: size)
    }
}

extension VentureStyle {
    /// Shortcuts-style fill: the system color, a touch lighter at the top.
    var fill: LinearGradient {
        LinearGradient(colors: [color.mix(with: .white, by: 0.16), color],
                       startPoint: .top, endPoint: .bottom)
    }
}

extension View {
    /// A solid content card, like an inset grouped list in Settings.
    func card(radius: CGFloat = 26) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground),
                   in: .rect(cornerRadius: radius, style: .continuous))
    }
}

/// The plain system background used by Settings, Reminders and friends.
struct AppBackground: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
    }
}

/// The little sunrise from the app icon, for "All clear".
struct SunMark: View {
    var width: CGFloat = 44

    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 44
            var sun = Path()
            sun.addArc(center: CGPoint(x: 22 * s, y: 24 * s), radius: 14 * s,
                       startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            sun.closeSubpath()
            ctx.fill(sun, with: .linearGradient(Gradient(colors: [.amber, .coral]),
                                                startPoint: CGPoint(x: 0, y: 10 * s), endPoint: CGPoint(x: 0, y: 24 * s)))
            ctx.fill(Path(roundedRect: CGRect(x: 2 * s, y: 25.5 * s, width: 40 * s, height: 2.5 * s), cornerRadius: 1.25 * s),
                     with: .color(.coral))
        }
        .frame(width: width, height: width * 28 / 44)
        .accessibilityHidden(true)
    }
}
