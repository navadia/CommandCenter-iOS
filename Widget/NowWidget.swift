import AppIntents
import SwiftUI
import WidgetKit

// The "Now" widget: a wide widget for the top of the home screen.
// Now face: next calendar event, the top Command Center item with Done,
// weather on top, the day along the bottom. Tap the weather for the
// Weather face, the date for World Clock; both flip back after 15 minutes.

struct NowConfig: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Now"
    static let description = IntentDescription("Your next event, what needs you, weather and world clock.")
}

struct NowEntry: TimelineEntry {
    let date: Date
    let face: NowFace
    let board: Board
    let hasToken: Bool
    let events: [DayEvent]
    let calendarAllowed: Bool
    let weather: WeatherReport?
    let cities: [ClockCity]
    let settingUp: Bool
}

struct NowProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NowEntry { Self.sampleEntry() }

    func snapshot(for configuration: NowConfig, in context: Context) async -> NowEntry {
        if context.isPreview { return Self.sampleEntry() }
        return await entries(minutes: 1).first ?? Self.sampleEntry()
    }

    func timeline(for configuration: NowConfig, in context: Context) async -> Timeline<NowEntry> {
        let list = await entries(minutes: 60)
        let next = list.last?.date.addingTimeInterval(60) ?? .now.addingTimeInterval(15 * 60)
        return Timeline(entries: list, policy: .after(next))
    }

    /// One entry per minute, so countdowns and the clock stay right without
    /// spending the widget's reload budget.
    private func entries(minutes: Int) async -> [NowEntry] {
        // Right after a face flip, use what's cached so the flip is instant.
        let justFlipped = NowFaceStore.lastFlip.map { abs($0.timeIntervalSinceNow - Double(NowFaceStore.holdMinutes) * 60) < 20 } ?? false
        let snoozed = SnoozeStore.activeIDs()
        let token = TokenStore.load()
        var items = SharedStore.snapshot
        if let token, !justFlipped, let fresh = try? await NotionClient(token: token).openItems() {
            SharedStore.saveSnapshot(fresh)
            items = fresh
        }
        let board = Board(items, snoozed: snoozed)
        let weather = await WeatherStore.load(allowNetwork: !justFlipped)
        let events = CalendarFeed.events()
        let cities = WorldClockStore.cities
        let settingUp = NowBackground.isSettingUp

        let cal = Calendar.current
        let start = cal.dateInterval(of: .minute, for: .now)?.start ?? .now
        return (0..<minutes).map { i in
            let date = start.addingTimeInterval(Double(i) * 60)
            return NowEntry(date: date, face: NowFaceStore.face(at: date), board: board, hasToken: token != nil,
                            events: events, calendarAllowed: CalendarFeed.isAllowed, weather: weather,
                            cities: cities, settingUp: settingUp)
        }
    }

    static func sampleEntry() -> NowEntry {
        let now = Date.now
        let cal = Calendar.current
        let event = DayEvent(title: "Standup", start: now.addingTimeInterval(95 * 60), end: now.addingTimeInterval(125 * 60))
        let hours = (0..<14).map { i in
            WeatherHour(date: now.addingTimeInterval(Double(i) * 3600), temp: 59 + 4 * sin(Double(i) / 3) - Double(i), rain: 0, code: 0)
        }
        let weather = WeatherReport(fetched: now, place: "Garland", lat: 0, lon: 0, temp: 59, feels: 57, code: 0, isDay: true,
                                    wind: 8, windDir: 180, high: 63, low: 40,
                                    sunrise: cal.date(bySettingHour: 6, minute: 58, second: 0, of: now) ?? now,
                                    sunset: cal.date(bySettingHour: 17, minute: 23, second: 0, of: now) ?? now,
                                    nextSunrise: nil, hours: hours)
        return NowEntry(date: now, face: .now, board: Board(CCProvider.sample), hasToken: true, events: [event],
                        calendarAllowed: true, weather: weather, cities: WorldClockStore.standard, settingUp: false)
    }
}

// MARK: - Look

private enum NowLook {
    static let secondary = Color.white.opacity(0.78)
    static let orange = Color.hex(0xFF9F0A)
    static let red = Color.hex(0xFF8A80)
    static let amber = Color.hex(0xFFCC66)

    static func label(_ text: String, _ color: Color = NowLook.secondary) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    static func big(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .rounded) }

    /// A soft wash that follows the time of day: warm morning, cool midday,
    /// orange evening, indigo night.
    static func tint(at date: Date) -> Color {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: .hex(0xFF9F0A, opacity: 0.22)
        case 11..<17: .hex(0x64AAFF, opacity: 0.18)
        case 17..<20: .hex(0xFF7A1A, opacity: 0.18)
        default: .hex(0x5E5CE6, opacity: 0.32)
        }
    }

    static func time(_ date: Date, in zone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "h:mm"
        return f.string(from: date)
    }

    static func countdown(to date: Date, from now: Date) -> String {
        let mins = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if mins < 60 { return "\(mins) min" }
        let h = mins / 60, m = mins % 60
        if h >= 24 { return "\(h / 24)d \(h % 24)h" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Views

struct NowWidgetView: View {
    let entry: NowEntry
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if entry.settingUp {
                VStack(spacing: 4) {
                    Text("Take a screenshot of this page")
                        .font(.subheadline.weight(.semibold))
                    Text("Then follow the steps in Command Center")
                        .font(.caption)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch entry.face {
                case .now: NowFaceView(entry: entry)
                case .weather: WeatherFaceView(entry: entry)
                case .world: WorldFaceView(entry: entry)
                }
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(renderingMode == .fullColor ? 0.25 : 0), radius: 2, y: 1)
        .containerBackground(for: .widget) {
            NowBackgroundView(date: entry.date, settingUp: entry.settingUp)
        }
        .widgetURL(URL(string: "commandcenter://today"))
    }
}

struct NowBackgroundView: View {
    let date: Date
    let settingUp: Bool

    var body: some View {
        if settingUp {
            Color(red: 1, green: 0, blue: 1)
        } else {
            ZStack {
                if let image = NowBackground.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                    // Shade from Settings › Now Widget; 0 = no edge at all.
                    Color.black.opacity(NowBackground.shade)
                } else {
                    Color(white: 0.12)
                }
                if NowBackground.showsTint || NowBackground.image == nil {
                    RadialGradient(colors: [NowLook.tint(at: date), .clear], center: .topLeading, startRadius: 0, endRadius: 300)
                }
            }
        }
    }
}

// MARK: Now face

private struct NowFaceView: View {
    let entry: NowEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topLine
            HStack(alignment: .top, spacing: 14) {
                EventBlock(entry: entry)
                    .frame(width: 128, alignment: .leading)
                ItemBlock(entry: entry)
            }
            Spacer(minLength: 0)
            if let alert {
                NowLook.label(alert, NowLook.amber)
            }
            DayBar(date: entry.date, events: entry.events)
        }
    }

    /// The big clock sits in the event spot when there's no event coming,
    /// so the time only goes in the top line when an event is shown.
    private var bigClockShown: Bool {
        entry.calendarAllowed && !entry.events.contains { $0.end > entry.date }
    }

    private var dateLine: String {
        let date = entry.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return bigClockShown ? date : "\(date) · \(entry.date.formatted(date: .omitted, time: .shortened))"
    }

    private var alert: String? {
        if let w = entry.weather?.warning(at: entry.date) { return w }
        if let power = entry.board.power.first?.powerData, power.state != "ok" { return "⚡ " + power.pill }
        return nil
    }

    private var topLine: some View {
        HStack(spacing: 6) {
            Button(intent: ShowNowFaceIntent(.world)) {
                NowLook.label(dateLine)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show world clock")
            Spacer(minLength: 6)
            if let w = entry.weather {
                Button(intent: ShowNowFaceIntent(.weather)) {
                    HStack(spacing: 4) {
                        Image(systemName: w.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 12))
                        Text("\(Int(w.temp.rounded()))°").font(NowLook.big(14))
                        Text(w.highLow).font(.system(size: 11, weight: .semibold)).foregroundStyle(NowLook.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show weather")
            }
        }
        .frame(height: 18)
    }
}

private struct EventBlock: View {
    let entry: NowEntry

    var body: some View {
        let now = entry.date
        let current = entry.events.filter { $0.start <= now && $0.end > now }.min { $0.end < $1.end }
        let next = entry.events.first { $0.start > now }
        if entry.calendarAllowed && current == nil && next == nil {
            // Nothing on the calendar: the big clock. Tapping it opens World Clock.
            Button(intent: ShowNowFaceIntent(.world)) {
                VStack(alignment: .leading, spacing: 0) {
                    NowLook.label("No events left")
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(NowLook.time(now)).font(NowLook.big(40)).widgetAccentable()
                        Text(Calendar.current.component(.hour, from: now) < 12 ? "AM" : "PM")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NowLook.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show world clock")
        } else {
            Link(destination: calendarURL(current?.start ?? next?.start ?? now)) {
                if !entry.calendarAllowed {
                    VStack(alignment: .leading, spacing: 3) {
                        NowLook.label("Calendar", NowLook.orange)
                        Text("Open Command Center › Settings › Now Widget to allow Calendar")
                            .font(.system(size: 12))
                            .foregroundStyle(NowLook.secondary)
                            .lineLimit(4)
                    }
                } else if let current {
                    inProgress(current, now: now)
                } else if let next {
                    VStack(alignment: .leading, spacing: 2) {
                        NowLook.label(dayLabel(next.start, from: now), NowLook.orange)
                        Text("\(next.title) · \(NowLook.time(next.start))")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(NowLook.countdown(to: next.start, from: now))
                            .font(NowLook.big(30))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                }
            }
        }
    }

    private func inProgress(_ event: DayEvent, now: Date) -> some View {
        let total = max(60, event.end.timeIntervalSince(event.start))
        let done = min(1, max(0, now.timeIntervalSince(event.start) / total))
        let left = max(1, Int((event.end.timeIntervalSince(now) / 60).rounded(.up)))
        return HStack(spacing: 9) {
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: 1 - done)
                    .stroke(NowLook.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                VStack(spacing: -2) {
                    Text(left >= 60 ? "\(left / 60)h" : "\(left)").font(NowLook.big(17))
                    Text(left >= 60 ? "\(left % 60)m" : "min").font(.system(size: 10, weight: .semibold))
                }
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 1) {
                NowLook.label("Now", NowLook.orange)
                Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text("until \(NowLook.time(event.end))").font(.system(size: 11)).foregroundStyle(NowLook.secondary)
            }
        }
    }

    private func dayLabel(_ date: Date, from now: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return "Next" }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private func calendarURL(_ date: Date) -> URL {
        URL(string: "calshow:\(Int(date.timeIntervalSinceReferenceDate))") ?? URL(string: "calshow:")!
    }
}

private struct ItemBlock: View {
    let entry: NowEntry

    var body: some View {
        let board = entry.board
        if !entry.hasToken {
            VStack(alignment: .leading, spacing: 3) {
                NowLook.label("Command Center")
                Text("Open the app to connect Notion.").font(.system(size: 13)).foregroundStyle(NowLook.secondary)
            }
        } else if let item = board.needYou.first ?? board.urgentFirst.first {
            VStack(alignment: .leading, spacing: 6) {
                label(for: item)
                HStack(spacing: 8) {
                    Link(destination: URL(string: "commandcenter://item/\(item.id)")!) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.sender)
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(subtitle(item))
                                .font(.system(size: 13))
                                .foregroundStyle(NowLook.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button(intent: MarkDoneIntent(itemID: item.id)) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(Color(white: 0.11))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.92), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mark \(item.sender) done")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                NowLook.label("Command Center")
                HStack(spacing: 8) {
                    SunMark(width: 30)
                    Text("All clear").font(.system(size: 15, weight: .semibold))
                }
            }
        }
    }

    private func label(for item: Item) -> some View {
        let overdue = entry.board.all.filter { ($0.daysUntilDue ?? 1) < 0 }.count
        if (item.daysUntilDue ?? 1) < 0 {
            return NowLook.label("\(overdue) overdue", NowLook.red)
        }
        if item.needsYou {
            return NowLook.label(item.whenText, item.isUrgent ? NowLook.red : NowLook.amber)
        }
        return NowLook.label("Up next for you")
    }

    private func subtitle(_ item: Item) -> String {
        let more = entry.board.openCount - 1
        let rest = more > 0 ? "+\(more) more" : item.subject
        return item.amountText.map { "\($0) · \(rest)" } ?? (more > 0 ? "+\(more) more open" : item.subject)
    }
}

/// The day from 6 AM to midnight: what's gone, your events, and a "now" marker.
private struct DayBar: View {
    let date: Date
    let events: [DayEvent]

    var body: some View {
        let cal = Calendar.current
        let dayStart = cal.date(bySettingHour: 6, minute: 0, second: 0, of: date) ?? date
        let dayEnd = cal.date(byAdding: .hour, value: 18, to: dayStart) ?? date
        let span = dayEnd.timeIntervalSince(dayStart)
        let pos = { (d: Date) in min(1, max(0, d.timeIntervalSince(dayStart) / span)) }
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white.opacity(0.36)).frame(width: w * pos(date))
                ForEach(events.filter { $0.end > dayStart && $0.start < dayEnd }, id: \.self) { e in
                    let on = e.start <= date && e.end > date
                    let past = e.end <= date
                    Capsule()
                        .fill(on ? NowLook.orange : Color.white.opacity(past ? 0.5 : 1))
                        .frame(width: max(4, w * (pos(e.end) - pos(e.start))))
                        .offset(x: w * pos(e.start))
                        .shadow(color: past ? Color.clear : (on ? NowLook.orange : Color.white).opacity(0.6), radius: 3)
                }
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(NowLook.orange)
                    .frame(width: 3, height: 13)
                    .offset(x: w * pos(date) - 1.5)
                    .shadow(color: NowLook.orange.opacity(0.8), radius: 3)
                    .widgetAccentable()
            }
        }
        .frame(height: 5)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }
}

// MARK: Weather face

private struct BackToNow: View {
    var body: some View {
        Button(intent: ShowNowFaceIntent(.now)) {
            Text("Now")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.white.opacity(0.18), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Now")
    }
}

private struct WeatherFaceView: View {
    let entry: NowEntry

    var body: some View {
        if let w = entry.weather {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    NowLook.label("\(w.place) · \(w.condition) · \(w.highLow)")
                    Spacer(minLength: 6)
                    BackToNow()
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 18))
                            Text("\(Int(w.temp.rounded()))°").font(NowLook.big(36)).widgetAccentable()
                        }
                        Text("Feels \(Int(w.feels.rounded()))°")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NowLook.secondary)
                    }
                    .fixedSize()
                    TempCurve(hours: w.hoursAhead(from: entry.date), sunrise: w.nextSunrise, sunset: w.sunset)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    chip("Sunrise", NowLook.time(entry.date < w.sunrise ? w.sunrise : (w.nextSunrise ?? w.sunrise)))
                    chip("Sunset", NowLook.time(w.sunset))
                    chip("Rain", "\(w.rainChance(from: entry.date))%")
                    chip("Wind", w.windText)
                }
            }
        } else {
            VStack(alignment: .leading) {
                HStack { NowLook.label("Weather"); Spacer(); BackToNow() }
                Spacer()
                Text("Weather isn't available right now. It comes back when the iPhone is online.")
                    .font(.system(size: 13))
                    .foregroundStyle(NowLook.secondary)
                Spacer()
            }
        }
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11)).foregroundStyle(NowLook.secondary)
            Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

/// The next 12 hours of temperature, with the night shaded.
private struct TempCurve: View {
    let hours: [WeatherHour]
    let sunrise: Date?
    let sunset: Date

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                let temps = hours.map(\.temp)
                let lo = (temps.min() ?? 0) - 1, hi = (temps.max() ?? 1) + 1
                let first = hours.first?.date ?? .now
                let last = hours.last?.date ?? .now.addingTimeInterval(3600)
                let span = max(3600, last.timeIntervalSince(first))
                let x = { (d: Date) in w * min(1, max(0, d.timeIntervalSince(first) / span)) }
                let y = { (t: Double) in h - 4 - (h - 10) * (t - lo) / max(1, hi - lo) }
                ZStack(alignment: .topLeading) {
                    // Night: from sunset (if ahead) to sunrise (or the end).
                    if sunset > first && sunset < last {
                        let endX = sunrise.map { $0 < last ? x($0) : w } ?? w
                        Rectangle()
                            .fill(Color.hex(0x5E5CE6, opacity: 0.22))
                            .frame(width: max(0, endX - x(sunset)), height: h)
                            .offset(x: x(sunset))
                        Rectangle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 1, height: h)
                            .offset(x: x(sunset))
                    }
                    Path { p in
                        for (i, hour) in hours.enumerated() {
                            let pt = CGPoint(x: x(hour.date), y: y(hour.temp))
                            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(Color.hex(0xFFD60A), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .widgetAccentable()
                    if let top = hours.max(by: { $0.temp < $1.temp }) {
                        Text("\(Int(top.temp.rounded()))°")
                            .font(.system(size: 10, weight: .semibold))
                            .offset(x: min(w - 22, x(top.date) + 2), y: max(0, y(top.temp) - 14))
                    }
                }
            }
            HStack {
                ForEach(Array(stride(from: 0, to: hours.count, by: 4)), id: \.self) { i in
                    Text(hours[i].date.formatted(.dateTime.hour()).lowercased().replacingOccurrences(of: " ", with: ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NowLook.secondary)
                    if i + 4 < hours.count { Spacer(minLength: 0) }
                }
            }
        }
        .frame(height: 66)
        .clipped()
        .accessibilityHidden(true)
    }
}

// MARK: World clock face

private struct WorldFaceView: View {
    let entry: NowEntry

    var body: some View {
        let here = ClockCity(name: WeatherPlace.saved.name, zone: TimeZone.current.identifier)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NowLook.label("World clock")
                Spacer(minLength: 6)
                BackToNow()
            }
            HStack(spacing: 6) {
                tile(here, isHere: true)
                ForEach(entry.cities.prefix(WorldClockStore.maxCities)) { tile($0, isHere: false) }
            }
        }
    }

    private func tile(_ city: ClockCity, isHere: Bool) -> some View {
        let now = entry.date
        let zone = city.timeZone
        var zoneCal = Calendar.current
        zoneCal.timeZone = zone
        let hourOfDay = zoneCal.component(.hour, from: now)
        let ampm = hourOfDay < 12 ? "AM" : "PM"
        return VStack(alignment: .leading, spacing: 1) {
            Text(city.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(NowLook.time(now, in: zone)).font(NowLook.big(26)).minimumScaleFactor(0.6).lineLimit(1)
                Text(ampm).font(.system(size: 10, weight: .semibold)).foregroundStyle(NowLook.secondary)
            }
            .widgetAccentable(isHere)
            Spacer(minLength: 0)
            Text(isHere ? "Here" : offsetText(zone, now: now))
                .font(.system(size: 11))
                .foregroundStyle(NowLook.secondary)
                .lineLimit(1)
            Image(systemName: (6..<18).contains(hourOfDay) ? "sun.max.fill" : "moon.fill")
                .font(.system(size: 11))
                .foregroundStyle(NowLook.secondary)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(isHere ? 0.16 : 0.1), in: .rect(cornerRadius: 14))
    }

    /// "+11:30 · Wed" relative to here.
    private func offsetText(_ zone: TimeZone, now: Date) -> String {
        let diff = zone.secondsFromGMT(for: now) - TimeZone.current.secondsFromGMT(for: now)
        let sign = diff >= 0 ? "+" : "−"
        let h = abs(diff) / 3600, m = (abs(diff) % 3600) / 60
        let offset = m == 0 ? "\(sign)\(h)h" : "\(sign)\(h):\(String(format: "%02d", m))"
        var local = Calendar.current
        local.timeZone = .current
        var there = Calendar.current
        there.timeZone = zone
        let hereDay = local.component(.weekday, from: now)
        let thereDay = there.component(.weekday, from: now)
        guard hereDay != thereDay else { return offset }
        let f = DateFormatter()
        f.timeZone = zone
        f.dateFormat = "EEE"
        return "\(offset) · \(f.string(from: now))"
    }
}

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Now", intent: NowConfig.self, provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Now")
        .description("Your next event, what needs you, the weather and a world clock. Tap the weather or the date for more.")
        .supportedFamilies([.systemMedium])
    }
}
