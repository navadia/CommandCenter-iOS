import CoreLocation
import EventKit
import PhotosUI
import SwiftUI
import WidgetKit

/// Settings › Now Widget: calendar access, weather location, world clock
/// cities and the see-through background.
struct NowWidgetSettingsView: View {
    @State private var calendarAllowed = CalendarFeed.isAllowed
    @State private var calendarDenied = EKEventStore.authorizationStatus(for: .event) == .denied
    @State private var place = WeatherPlace.saved
    @State private var locating = false
    @State private var locationError: String?
    @State private var cities = WorldClockStore.cities
    @State private var settingUp = NowBackground.isSettingUp
    @State private var hasBackground = NowBackground.hasImage
    @State private var picks: [PhotosPickerItem] = []
    @State private var backgroundError: String?
    @State private var working = false

    var body: some View {
        Form {
            calendarSection
            weatherSection
            worldClockSection
            backgroundSection
        }
        .navigationTitle("Now Widget")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picks) { _, new in
            guard !new.isEmpty else { return }
            Task { await buildBackground(from: new) }
        }
    }

    // MARK: Calendar

    private var calendarSection: some View {
        Section {
            LabeledContent("Calendar") {
                Text(calendarAllowed ? "Allowed" : (calendarDenied ? "Off" : "Not set"))
                    .foregroundStyle(calendarAllowed ? .green : .secondary)
            }
            if !calendarAllowed {
                if calendarDenied {
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else {
                    Button("Allow Calendar") { Task { await allowCalendar() } }
                }
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text("The widget shows your next timed event from the iPhone Calendar app, including Google or Outlook calendars added there. Birthdays and all-day events are skipped.")
        }
    }

    private func allowCalendar() async {
        let granted = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
        calendarAllowed = granted && CalendarFeed.isAllowed
        calendarDenied = !calendarAllowed
        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
    }

    // MARK: Weather

    private var weatherSection: some View {
        Section {
            TextField("Place name", text: $place.name)
                .onSubmit { savePlace() }
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    Text("Use My Current Location")
                    Spacer()
                    if locating { ProgressView() }
                }
            }
            .disabled(locating)
            if let locationError {
                Text(locationError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Weather")
        } footer: {
            Text("Weather is for \(place.name) (\(String(format: "%.2f, %.2f", place.lat, place.lon))). It's set once and doesn't follow you around. Forecasts come from Open-Meteo, which is free.")
        }
        .onDisappear { savePlace() }
    }

    private func savePlace() {
        let name = place.name.trimmingCharacters(in: .whitespaces)
        place.name = name.isEmpty ? "Here" : name
        guard place != WeatherPlace.saved else { return }
        WeatherPlace.save(place)
        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
    }

    private func useCurrentLocation() async {
        locating = true
        locationError = nil
        defer { locating = false }
        let session = CLServiceSession(authorization: .whenInUse)
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    place.lat = location.coordinate.latitude
                    place.lon = location.coordinate.longitude
                    savePlace()
                    break
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    locationError = "Location is off for Command Center. Turn it on in iPhone Settings › Privacy › Location Services."
                    break
                }
            }
        } catch {
            locationError = "Couldn't get your location. Try again outside or with Wi-Fi on."
        }
        _ = session
    }

    // MARK: World clock

    private var worldClockSection: some View {
        Section {
            ForEach(cities) { city in
                LabeledContent(city.name) {
                    Text(city.timeZone.localizedName(for: .shortGeneric, locale: .current) ?? city.zone)
                }
            }
            .onDelete { offsets in
                cities.remove(atOffsets: offsets)
                saveCities()
            }
            if cities.count < WorldClockStore.maxCities {
                NavigationLink("Add City") {
                    CityPicker { city in
                        cities.append(city)
                        saveCities()
                    }
                }
            }
        } header: {
            Text("World Clock")
        } footer: {
            Text("Tap the date on the widget to see these next to your own time. Up to \(WorldClockStore.maxCities). iPhone doesn't let other apps read the Clock app's list, so they're set here.")
        }
    }

    private func saveCities() {
        WorldClockStore.save(cities)
        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
    }

    // MARK: See-through background

    private var backgroundSection: some View {
        Section {
            LabeledContent("See-through") {
                Text(hasBackground ? "On" : (settingUp ? "Waiting for screenshots" : "Off"))
                    .foregroundStyle(hasBackground ? .green : .secondary)
            }
            if settingUp {
                PhotosPicker(selection: $picks, maxSelectionCount: 2, matching: .screenshots) {
                    HStack {
                        Text("Pick the 2 Screenshots")
                        Spacer()
                        if working { ProgressView() }
                    }
                }
                .disabled(working)
                Button("Cancel", role: .cancel) {
                    NowBackground.isSettingUp = false
                    settingUp = false
                    WidgetCenter.shared.reloadTimelines(ofKind: "Now")
                }
            } else {
                Button(hasBackground ? "Set Up Again" : "Make It See-Through") {
                    NowBackground.isSettingUp = true
                    settingUp = true
                    backgroundError = nil
                    WidgetCenter.shared.reloadTimelines(ofKind: "Now")
                }
                if hasBackground {
                    Button("Turn Off", role: .destructive) {
                        NowBackground.remove()
                        hasBackground = false
                        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
                    }
                }
            }
            if let backgroundError {
                Text(backgroundError).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Background")
        } footer: {
            Text(settingUp
                 ? "1. Go to the home screen. The Now widget turns pink; take a screenshot of that page.\n2. Long-press an empty spot, swipe left to an empty page, take a screenshot, then press Done.\n3. Come back here and pick both screenshots."
                 : "Shows your own wallpaper behind the widget so it looks see-through, like the rest of your home screen. Set it up again if you change your wallpaper or move the widget. If your home screen is set to Clear or Tinted, iPhone draws its own glass instead.")
        }
    }

    private func buildBackground(from items: [PhotosPickerItem]) async {
        working = true
        defer {
            working = false
            picks = []
        }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        do {
            try NowBackground.build(from: images)
            settingUp = false
            hasBackground = true
            backgroundError = nil
        } catch {
            backgroundError = error.localizedDescription
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
    }
}

/// Every time zone iPhone knows, searchable by city.
private struct CityPicker: View {
    let onPick: (ClockCity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.filter { $0.contains("/") && !$0.hasPrefix("Etc") }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.lowercased().replacingOccurrences(of: "_", with: " ").contains(q) }
    }

    var body: some View {
        List(zones, id: \.self) { zone in
            Button {
                onPick(ClockCity(name: ClockCity.name(for: zone), zone: zone))
                dismiss()
            } label: {
                LabeledContent(ClockCity.name(for: zone)) {
                    Text(zone.split(separator: "/").first.map(String.init) ?? "")
                }
            }
            .foregroundStyle(.primary)
        }
        .searchable(text: $search, prompt: "City, like Kolkata or London")
        .navigationTitle("Add City")
        .navigationBarTitleDisplayMode(.inline)
    }
}
