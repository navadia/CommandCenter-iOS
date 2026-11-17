import AppIntents
import EventKit
import Foundation
import SwiftUI
import UIKit
import WidgetKit

// Everything the Now widget needs that the app also touches: weather,
// calendar events, world clock cities, which face is showing, and the
// see-through background. All kept in the App Group.

// MARK: - Weather (Open-Meteo, free, no key)

/// Where the weather is for. Garland until the user taps "Use My Current Location".
struct WeatherPlace: Codable, Sendable, Equatable {
    var name: String
    var lat: Double
    var lon: Double

    static let garland = WeatherPlace(name: "Garland", lat: 32.9126, lon: -96.6389)
    private static let key = "nowWeatherPlace"

    static var saved: WeatherPlace {
        guard let data = SharedStore.defaults.data(forKey: key),
              let place = try? JSONDecoder().decode(WeatherPlace.self, from: data) else { return .garland }
        return place
    }

    static func save(_ place: WeatherPlace) {
        guard let data = try? JSONEncoder().encode(place) else { return }
        SharedStore.defaults.set(data, forKey: key)
        WeatherStore.clear()
    }
}

struct WeatherHour: Codable, Sendable, Hashable {
    let date: Date
    let temp: Double
    let rain: Int        // chance, %
    let code: Int
}

struct WeatherReport: Codable, Sendable {
    let fetched: Date
    let place: String
    let lat: Double
    let lon: Double
    let temp: Double
    let feels: Double
    let code: Int
    let isDay: Bool
    let wind: Double
    let windDir: Double
    let high: Double
    let low: Double
    let sunrise: Date
    let sunset: Date
    let nextSunrise: Date?
    let hours: [WeatherHour]

    var symbol: String { WeatherCode.symbol(code, day: isDay) }
    var condition: String { WeatherCode.text(code, day: isDay) }

    /// "H63 L40"
    var highLow: String { "H\(Int(high.rounded())) L\(Int(low.rounded()))" }

    var windText: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let i = Int(((windDir.truncatingRemainder(dividingBy: 360)) + 22.5) / 45) % 8
        return "\(Int(wind.rounded())) \(dirs[max(0, i)])"
    }

    /// The next 12 hours, starting with the current hour.
    func hoursAhead(from date: Date, count: Int = 13) -> [WeatherHour] {
        let start = date.addingTimeInterval(-3600)
        return Array(hours.filter { $0.date > start }.prefix(count))
    }

    func rainChance(from date: Date) -> Int {
        hoursAhead(from: date).map(\.rain).max() ?? 0
    }

    /// One line worth showing on the Now face, or nil when the weather is unremarkable.
    func warning(at date: Date) -> String? {
        if WeatherCode.isWet(code) { return WeatherCode.isSnow(code) ? "Snowing now" : "Raining now" }
        let soon = hours.first { $0.date > date && $0.date < date.addingTimeInterval(12 * 3600)
            && ($0.rain >= 50 || (WeatherCode.isWet($0.code) && $0.rain >= 30)) }
        if let soon {
            let hour = soon.date.formatted(.dateTime.hour())
            return WeatherCode.isSnow(soon.code) ? "Snow around \(hour)" : "Rain around \(hour) · take an umbrella"
        }
        return nil
    }
}

enum WeatherCode {
    static func isWet(_ c: Int) -> Bool { (51...67).contains(c) || (71...86).contains(c) || (95...99).contains(c) }
    static func isSnow(_ c: Int) -> Bool { (71...77).contains(c) || (85...86).contains(c) }

    static func symbol(_ c: Int, day: Bool) -> String {
        switch c {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func text(_ c: Int, day: Bool) -> String {
        switch c {
        case 0: day ? "Sunny" : "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Storms"
        default: "Cloudy"
        }
    }
}

enum WeatherStore {
    private static let key = "nowWeather"

    static var cached: WeatherReport? {
        guard let data = SharedStore.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WeatherReport.self, from: data)
    }

    static func clear() { SharedStore.defaults.removeObject(forKey: key) }

    /// The cached report if it is fresh, otherwise a new one. Falls back to
    /// an older report (up to 6 hours) when Open-Meteo can't be reached.
    static func load(maxAge: TimeInterval = 30 * 60, allowNetwork: Bool = true) async -> WeatherReport? {
        let place = WeatherPlace.saved
        let old = cached.flatMap { $0.lat == place.lat && $0.lon == place.lon ? $0 : nil }
        if let old, Date.now.timeIntervalSince(old.fetched) < maxAge { return old }
        if allowNetwork, let fresh = try? await fetch(place) {
            if let data = try? JSONEncoder().encode(fresh) { SharedStore.defaults.set(data, forKey: key) }
            return fresh
        }
        if let old, Date.now.timeIntervalSince(old.fetched) < 6 * 3600 { return old }
        return nil
    }

    private struct Response: Decodable {
        let utc_offset_seconds: Int
        let current: Current
        let hourly: Hourly
        let daily: Daily

        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let is_day: Int
            let wind_speed_10m: Double?
            let wind_direction_10m: Double?
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let precipitation_probability: [Double?]?
            let weather_code: [Int?]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let sunrise: [String]
            let sunset: [String]
        }
    }

    static func fetch(_ place: WeatherPlace) async throws -> WeatherReport {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", place.lat)),
            .init(name: "longitude", value: String(format: "%.4f", place.lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_direction_10m"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "2"),
        ]
        var request = URLRequest(url: parts.url!)
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        let r = try JSONDecoder().decode(Response.self, from: data)

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let date = { (s: String) in f.date(from: s) }

        var hours: [WeatherHour] = []
        for (i, t) in r.hourly.time.enumerated() {
            guard let d = date(t), let temp = r.hourly.temperature_2m[safe: i] ?? nil else { continue }
            let rain = (r.hourly.precipitation_probability?[safe: i] ?? nil) ?? 0
            let code = (r.hourly.weather_code[safe: i] ?? nil) ?? 0
            hours.append(WeatherHour(date: d, temp: temp, rain: Int(rain), code: code))
        }
        guard let sunrise = r.daily.sunrise.first.flatMap(date),
              let sunset = r.daily.sunset.first.flatMap(date) else { throw URLError(.cannotParseResponse) }
        let c = r.current
        return WeatherReport(
            fetched: .now, place: place.name, lat: place.lat, lon: place.lon,
            temp: c.temperature_2m, feels: c.apparent_temperature, code: c.weather_code, isDay: c.is_day == 1,
            wind: c.wind_speed_10m ?? 0, windDir: c.wind_direction_10m ?? 0,
            high: (r.daily.temperature_2m_max.first ?? nil) ?? c.temperature_2m,
            low: (r.daily.temperature_2m_min.first ?? nil) ?? c.temperature_2m,
            sunrise: sunrise, sunset: sunset,
            nextSunrise: r.daily.sunrise.dropFirst().first.flatMap(date),
            hours: hours)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Calendar (iPhone Calendar app, timed events only)

struct DayEvent: Codable, Sendable, Hashable {
    let title: String
    let start: Date
    let end: Date
}

enum CalendarFeed {
    static var isAllowed: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Timed events from the start of today to the end of tomorrow. Skips
    /// all-day events, birthdays, cancelled ones and ones you declined.
    static func events(around date: Date = .now) -> [DayEvent] {
        guard isAllowed else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return [] }
        let store = EKEventStore()
        let calendars = store.calendars(for: .event).filter { $0.type != .birthday }
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .filter { event in
                guard !event.isAllDay, event.status != .canceled,
                      event.endDate.timeIntervalSince(event.startDate) <= 24 * 3600 else { return false }
                let me = event.attendees?.first { $0.isCurrentUser }
                return me?.participantStatus != .declined
            }
            .map { DayEvent(title: ($0.title ?? "").isEmpty ? "Busy" : $0.title!, start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }
    }
}

// MARK: - World clock

struct ClockCity: Codable, Sendable, Hashable, Identifiable {
    let name: String
    let zone: String
    var id: String { zone }
    var timeZone: TimeZone { TimeZone(identifier: zone) ?? .current }

    /// "Asia/Kolkata" -> "Kolkata"
    static func name(for zone: String) -> String {
        (zone.split(separator: "/").last.map(String.init) ?? zone).replacingOccurrences(of: "_", with: " ")
    }
}

enum WorldClockStore {
    private static let key = "nowWorldClock"
    static let maxCities = 3
    static let standard = [ClockCity(name: "India", zone: "Asia/Kolkata")]

    static var cities: [ClockCity] {
        guard let data = SharedStore.defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([ClockCity].self, from: data) else { return standard }
        return list
    }

    static func save(_ list: [ClockCity]) {
        guard let data = try? JSONEncoder().encode(Array(list.prefix(maxCities))) else { return }
        SharedStore.defaults.set(data, forKey: key)
    }
}

// MARK: - Which face the widget shows

enum NowFace: String, Sendable {
    case now, weather, world
}

enum NowFaceStore {
    private static let faceKey = "nowFace"
    private static let untilKey = "nowFaceUntil"
    /// How long Weather or World Clock stays up before the widget goes back to Now.
    static let holdMinutes = 15

    static func show(_ face: NowFace) {
        SharedStore.defaults.set(face.rawValue, forKey: faceKey)
        SharedStore.defaults.set(Date.now.addingTimeInterval(Double(holdMinutes) * 60), forKey: untilKey)
    }

    static func face(at date: Date) -> NowFace {
        guard let raw = SharedStore.defaults.string(forKey: faceKey), let face = NowFace(rawValue: raw),
              let until = SharedStore.defaults.object(forKey: untilKey) as? Date, date < until else { return .now }
        return face
    }

    /// Set when a face was just flipped, so the widget reloads from cache (fast) instead of the network.
    static var lastFlip: Date? { SharedStore.defaults.object(forKey: untilKey) as? Date }
}

/// The widget's tap targets: the date flips to World Clock, the weather to
/// Weather, and "Now" flips back. Runs in the widget, no app opening.
struct ShowNowFaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Widget Face"
    static let isDiscoverable = false

    @Parameter(title: "Face")
    var face: String

    init() {}

    init(_ face: NowFace) {
        self.face = face.rawValue
    }

    func perform() async throws -> some IntentResult {
        NowFaceStore.show(NowFace(rawValue: face) ?? .now)
        return .result()
    }
}

// MARK: - See-through background

/// A slice of the user's own wallpaper, cut out where the widget sits, so
/// the widget looks see-through in iPhone's normal (full color) mode.
/// Setup: the widget turns pink, the user screenshots page 1 (pink shows
/// where the widget is) and an empty home screen page (the bare wallpaper).
enum NowBackground {
    private static let setupKey = "nowBackgroundSetup"
    private static let fileName = "now-background.jpg"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.groupID)?
            .appendingPathComponent(fileName)
    }

    static var image: UIImage? {
        guard let url = fileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static var hasImage: Bool {
        guard let url = fileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// How much darker than the wallpaper the widget is (0 = invisible edges, up to 0.5).
    static var shade: Double {
        get { SharedStore.defaults.double(forKey: "nowShade") }
        set { SharedStore.defaults.set(min(0.5, max(0, newValue)), forKey: "nowShade") }
    }

    /// The warm/cool/indigo time-of-day wash over the wallpaper. Off by default.
    static var showsTint: Bool {
        get { SharedStore.defaults.bool(forKey: "nowTint") }
        set { SharedStore.defaults.set(newValue, forKey: "nowTint") }
    }

    static var isSettingUp: Bool {
        get { SharedStore.defaults.bool(forKey: setupKey) }
        set { SharedStore.defaults.set(newValue, forKey: setupKey) }
    }

    static func remove() {
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        isSettingUp = false
    }

    enum SetupError: LocalizedError {
        case noPink, noWallpaper, sizes, save
        var errorDescription: String? {
            switch self {
            case .noPink: "Couldn't find the pink widget. Pick the screenshot of page 1 taken while the widget was pink."
            case .noWallpaper: "Pick two screenshots: page 1 with the pink widget, and an empty home screen page."
            case .sizes: "The two screenshots are different sizes. Take both on this iPhone."
            case .save: "Couldn't save the background. Check Settings › Status › Shared storage."
            }
        }
    }

    /// Finds the pink widget in one screenshot and cuts the same spot out of the other.
    static func build(from images: [UIImage]) throws {
        let cgs = images.compactMap(\.cgImage)
        guard cgs.count == 2 else { throw SetupError.noWallpaper }
        let found = cgs.map(pinkRect)
        guard let index = found.firstIndex(where: { $0 != nil }), let rect = found[index] else { throw SetupError.noPink }
        let wallpaper = cgs[index == 0 ? 1 : 0]
        guard found[index == 0 ? 1 : 0] == nil else { throw SetupError.noWallpaper }
        guard wallpaper.width == cgs[index].width, wallpaper.height == cgs[index].height else { throw SetupError.sizes }
        guard let slice = wallpaper.cropping(to: rect),
              let data = UIImage(cgImage: slice).jpegData(compressionQuality: 0.9),
              let url = fileURL else { throw SetupError.save }
        do { try data.write(to: url, options: .atomic) } catch { throw SetupError.save }
        isSettingUp = false
    }

    /// The bounding box of the widget's pink fill, in pixels.
    private static func pinkRect(_ image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1, count = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                let i = (y * w + x) * 4
                if px[i] > 200 && px[i + 1] < 90 && px[i + 2] > 200 {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        // A real widget is thousands of pink pixels and wider than a third of the screen.
        guard count > 2000, maxX - minX > w / 3 else { return nil }
        // The bitmap's rows run top-down here, same as the image.
        return CGRect(x: minX, y: minY, width: maxX - minX + 2, height: maxY - minY + 2)
    }
}
