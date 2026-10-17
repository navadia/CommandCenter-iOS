import SwiftUI

/// Round sender picture (website icon, or colored initial) with a small
/// venture badge in the corner: who sent it and what it's about, at a glance.
struct SenderAvatar: View {
    let item: Item
    var size: CGFloat = 40
    var showBadge = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            face
                .frame(width: size, height: size)
                .clipShape(Circle())
            if showBadge {
                VentureBadge(venture: item.venture, size: size * 0.46)
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
        } else {
            let tint = Pastel.for(item.sender)
            Text(item.initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(tint.ink)
                .frame(width: size, height: size)
                .background(tint.paper)
        }
    }
}

/// The venture's color tile with its symbol.
struct VentureBadge: View {
    let venture: String
    var size: CGFloat = 20
    var ring = true

    var body: some View {
        let style = VentureStyle.of(venture)
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(style.color)
            .overlay {
                Image(systemName: style.symbol)
                    .font(.system(size: size * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .overlay {
                if ring {
                    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .strokeBorder(Color(uiColor: .systemBackground), lineWidth: max(1.5, size * 0.09))
                }
            }
            .frame(width: size, height: size)
    }
}

/// Soft background colors for letter avatars, picked from the sender name
/// so a sender always gets the same one.
enum Pastel {
    private static let pairs: [(UInt32, UInt32)] = [
        (0xE0E7FF, 0x3730A3), (0xDCFCE7, 0x166534), (0xFCE7F3, 0x9D174D), (0xFEF3C7, 0x92400E),
        (0xE0F2FE, 0x075985), (0xF3E8FF, 0x6B21A8), (0xFFE4E6, 0x9F1239), (0xE2E8F0, 0x334155)
    ]

    static func `for`(_ name: String) -> (paper: Color, ink: Color) {
        var hash: UInt32 = 5381
        for scalar in name.lowercased().unicodeScalars { hash = (hash &* 33) &+ scalar.value }
        let pair = pairs[Int(hash % UInt32(pairs.count))]
        return (.hex(pair.0), .hex(pair.1))
    }
}

extension VentureStyle {
    /// The venture card fill: its color, slightly deeper toward the corner.
    var fill: LinearGradient {
        LinearGradient(colors: [color, color.mix(with: .black, by: 0.22)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The sunrise behind everything: warm cream by day, deep night with an
/// ember glow in dark mode.
struct SunriseBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                if scheme == .dark {
                    Color.hex(0x14112A)
                    RadialGradient(colors: [.hex(0x312A6E), .clear],
                                   center: UnitPoint(x: 0, y: 0), startRadius: 0, endRadius: w * 1.1)
                    RadialGradient(colors: [.brandOrange.opacity(0.38), .clear],
                                   center: UnitPoint(x: 0.5, y: 1.08), startRadius: 0, endRadius: max(w, h * 0.5))
                } else {
                    Color.cream
                    RadialGradient(colors: [.hex(0xFFD59A), .clear],
                                   center: UnitPoint(x: 0.1, y: -0.05), startRadius: 0, endRadius: w * 1.2)
                    RadialGradient(colors: [.hex(0xFFB8A6), .clear],
                                   center: UnitPoint(x: 1.05, y: 0.18), startRadius: 0, endRadius: w * 0.95)
                    RadialGradient(colors: [.hex(0xE6D9FF), .clear],
                                   center: UnitPoint(x: 0.5, y: 1.05), startRadius: 0, endRadius: max(w, h * 0.5))
                }
            }
        }
        .ignoresSafeArea()
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
