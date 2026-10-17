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

/// How frosted the app's glass is: 0 = clear glass, 1 = solid. One setting
/// for the whole app (Settings › Appearance), saved in the App Group.
enum GlassPreference {
    static let key = "glassFrost"
    static let standard = 0.6
}

/// Frosted glass behind content. Mixes the system's thinnest blur with the
/// card color by the user's Glass setting; fully solid when the iPhone's
/// Reduce Transparency is on.
struct Frosted<S: InsettableShape>: ViewModifier {
    let shape: S
    var edge = false

    @AppStorage(GlassPreference.key, store: SharedStore.defaults) private var frost = GlassPreference.standard
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                let surface = Color(uiColor: .secondarySystemGroupedBackground)
                if reduceTransparency || frost >= 0.99 {
                    shape.fill(surface)
                } else {
                    ZStack {
                        shape.fill(.ultraThinMaterial)
                        shape.fill(surface.opacity(frost))
                    }
                }
            }
            .overlay {
                if edge && !reduceTransparency && frost < 0.99 {
                    shape.strokeBorder(.white.opacity(0.28), lineWidth: 0.75)
                }
            }
    }
}

extension View {
    /// A content card on the app's glass (see `Frosted`).
    func card(radius: CGFloat = 26) -> some View {
        modifier(Frosted(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
    }

    /// A glass tile with a faint light edge, for rows sitting on a colored card.
    func glassTile(radius: CGFloat = 18) -> some View {
        modifier(Frosted(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), edge: true))
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

/// A solid red "Due today" / "Overdue" pill, only for things due now, so the
/// one thing that can't wait never blends in with the rest of the card.
struct DueTag: View {
    let text: String

    init?(item: Item) {
        guard let d = item.daysUntilDue, d <= 0 else { return nil }
        text = (d < 0 || item.type == "money" || item.trial) ? item.whenText : "Due today"
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red, in: .capsule)
            .fixedSize()
    }
}

/// A quiet venture surface: the plain card with a faint wash of the venture's
/// color. The badge carries the identity, so the open venture or the card that
/// needs you stays the loudest thing on screen.
struct VentureWash: View {
    let style: VentureStyle
    var radius: CGFloat = 20

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
            shape.fill(style.color.opacity(0.10))
            shape.strokeBorder(style.color.opacity(0.22), lineWidth: 0.75)
        }
    }
}
