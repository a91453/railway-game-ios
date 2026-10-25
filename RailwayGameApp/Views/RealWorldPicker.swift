import GameCore
import GamePresentation
import MapKit
import SwiftUI

/// Chooses where a real-world game's map lies (Stage E2, ARCHITECTURE
/// decision 50), after the `Ci/` reference's city choice (`CITIES`, and
/// its "any city" from a point on the map): a place from the references'
/// list or from a search moves the map there, the player moves it to taste,
/// and the game's 16 km map starts with its middle at the middle of the
/// view. Or the player starts on the whole of Taiwan (decision 88). A place
/// of Taiwan starts with that square only, and buys the land round it as
/// the railway grows (decision 167). A tap on the map moves the square
/// there, and the list says how large it is and the places a game was
/// started at before (decision 312).
///
/// Only that middle is kept, as the world's anchor and in the list of recent
/// places (decision 312). A search's results are
/// Apple's map data, shown with the map and dropped (Attachment 6 §2.4 and
/// §2.5 of the Apple Developer Program License Agreement).
///
/// Taiwan's real railways (the `Railway/` site's) are drawn on the map, and
/// every one of their stations is a place to start at: by railway, and as
/// the player types a name, matched as the site matches names.
///
/// "Use my location" moves the square to where the device is, from one fix
/// asked for while the app is in use (decision 335): the fix only moves the
/// map, and is neither kept nor sent anywhere.
struct RealWorldPicker: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    /// The middle of the map in view: where the game's map would start.
    @State private var middle: CLLocationCoordinate2D
    @State private var query = ""
    @State private var search = PlaceSearch()
    /// The groups of the list that are open (decision 262).
    @State private var expandedGroups: Set<String> = ["country-TW"]
    /// Taiwan's real railways as the map draws them, made when the picker
    /// appears (it opens once the launcher has read them).
    @State private var railwayLines: [RailwayLineDrawing] = []
    /// How far the camera is from the map, kept so a tap moves the square
    /// without zooming.
    @State private var cameraDistance: Double?
    /// The places a game was started at on this device (decision 312,
    /// ``RecentStartPlaces``): only their middles.
    @AppStorage("realWorld.recentStarts") private var recentStarts = ""
    /// Decision 335: asks for the device's location once per tap; made at
    /// the first tap.
    @State private var locator: OneShotLocation?
    @State private var isLocating = false
    /// What the last "Use my location" says (``MyLocationStart``), shown
    /// over the map until the player moves on.
    @State private var locationMessage: String?
    /// What the last "Use my location" came to, so a fix's line goes once
    /// the map is moved elsewhere (``MyLocationStart/messageGoes(mapMiddleLatitude:longitude:)``).
    @State private var locationResult: MyLocationStart?
    /// A test build's line under the button: when it was last pressed and
    /// what that came to (``MyLocationTrace``); kept until the next press.
    @State private var locationTrace: MyLocationTrace?
    /// How wide the map is, so a tap on the location button's corner is
    /// not also taken as a tap on the map.
    @State private var mapWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(launcher: GameLauncher) {
        self.launcher = launcher
        let start = Self.coordinate(of: RealWorldPlace.standard.anchor)
        _position = State(initialValue: Self.camera(on: start))
        _middle = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                if proxy.size.width > proxy.size.height {
                    HStack(spacing: 0) {
                        preview
                        Divider()
                        places
                            .frame(width: min(360, proxy.size.width / 2))
                    }
                } else {
                    VStack(spacing: 0) {
                        preview
                            .frame(height: (proxy.size.height * 0.5).rounded())
                        Divider()
                        places
                    }
                }
            }
            .navigationTitle("Real-World Map")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onSubmit(of: .search) {
                search.find(query, near: middle)
            }
            .onChange(of: query) { _, text in
                if text.isEmpty {
                    search.clear()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Build Here") {
                        start()
                    }
                    .disabled(anchor == nil)
                    .accessibilityIdentifier("realWorld.start")
                }
            }
        }
    }

    /// Apple's map with the game's map drawn as a square round its middle.
    /// Moved and zoomed only, flat and north up, as the game's map is
    /// (decision 50): tilted, the "+" in the middle of the view was not
    /// over the middle of the region MapKit reported, so a game could
    /// start somewhere else than under it.
    private var preview: some View {
        MapReader { reader in
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(railwayLines) { line in
                    MapPolyline(coordinates: line.coordinates)
                        .stroke(Color(line.color(colorScheme == .dark ? .dark : .light)), lineWidth: 2)
                }
                .mapOverlayLevel(level: .aboveRoads)
                // Decision 312: the land the game starts with, drawn as the
                // land chosen to buy is (decision 160): green, dashed.
                MapPolygon(coordinates: square)
                    .foregroundStyle(Palette.metroGreen.opacity(0.18))
                    .stroke(Palette.metroGreen, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            // Decision 312: a tap moves the square there, kept on the map.
            .onTapGesture { location in
                // TestFlight 86.1 (an iPad): the tap on the location button
                // reached the map behind it too and moved the square to
                // the top right.
                guard !isLocating,
                      !MyLocationStart.isOnButton(x: location.x, y: location.y, mapWidth: mapWidth),
                      let tapped = reader.convert(location, from: .local),
                      let area = RealWorldStartArea(latitude: tapped.latitude, longitude: tapped.longitude)
                else { return }
                locationMessage = nil
                withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) {
                    position = Self.camera(on: Self.coordinate(of: area.middle), distance: cameraDistance)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mapWidth = $0 }
            .onAppear {
                if railwayLines.isEmpty {
                    railwayLines = (launcher.railways?.lines ?? []).map(RailwayLineDrawing.init)
                }
            }
            .onMapCameraChange(frequency: .continuous) { context in
                // Where the camera looks: under the "+".
                middle = context.camera.centerCoordinate
                cameraDistance = context.camera.distance
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                // Decision 335: a fix's line is about where the location put
                // the square; once the map is elsewhere it goes. Why there
                // is none stays until closed (TestFlight 86.1).
                guard locationMessage != nil, !isLocating, let locationResult else { return }
                let centre = context.camera.centerCoordinate
                if locationResult.messageGoes(mapMiddleLatitude: centre.latitude, longitude: centre.longitude) {
                    locationMessage = nil
                }
            }
            .overlay {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("realWorld.map")
            .overlay(alignment: .topLeading) { middleMark }
            // Decision 335: under the search field, at the map's corner as
            // the system's maps put it.
            .overlay(alignment: .topTrailing) {
                VStack(alignment: .trailing, spacing: 6) {
                    myLocationButton
                    if TestBuild.isTest, let locationTrace {
                        Text(verbatim: locationTrace.text(in: launcher.language))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassBackground(in: Capsule())
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("realWorld.locationTrace")
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .bottom) {
                if let locationMessage {
                    locationNote(locationMessage)
                        .padding(10)
                        .transition(.card(from: .bottom, reduceMotion: reduceMotion))
                }
            }
            .animation(MotionRule.change.layout(reduceMotion: reduceMotion), value: locationMessage)
        }
    }

    /// Under `-ui-testing`, in a Debug build, where the map's middle is,
    /// to a hundredth of a degree, for the UI test that the location
    /// button does not move it. Nothing otherwise.
    @ViewBuilder
    private var middleMark: some View {
        #if DEBUG
        if UITestTrace.isOn {
            Text(verbatim: String(format: "%.2f,%.2f", middle.latitude, middle.longitude))
                .font(.system(size: 1))
                .foregroundStyle(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("realWorld.middle")
        }
        #endif
    }

    /// Decision 335: moves the square to where the device is.
    private var myLocationButton: some View {
        Button {
            useMyLocation()
        } label: {
            Group {
                if isLocating {
                    ProgressView()
                } else {
                    Image(systemName: "location")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(width: 44, height: 44)
            .glassBackground(in: Circle(), interactive: true)
            // The whole circle, not only its glyph, is the button's.
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isLocating)
        .accessibilityLabel(Text(verbatim: launcher.language.text("Use My Location", "用我的位置")))
        .accessibilityIdentifier("realWorld.myLocation")
    }

    /// The line "Use my location" says, with a button to close it.
    private func locationNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("realWorld.locationMessage")
            Button {
                locationMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: launcher.language.text("Close", "關閉")))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Asks for one fix and moves the square there, kept on the map, or
    /// says why it could not (``MyLocationStart``). The fix is dropped.
    private func useMyLocation() {
        isLocating = true
        locationMessage = nil
        locationResult = nil
        if TestBuild.isTest {
            let now = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
            locationTrace = MyLocationTrace(hour: now.hour ?? 0, minute: now.minute ?? 0, second: now.second ?? 0)
        }
        let locator = locator ?? OneShotLocation()
        self.locator = locator
        Task {
            let result: MyLocationStart
            if let answer = Self.uiTestLocation {
                result = answer
            } else {
                result = await locator.locate()
            }
            isLocating = false
            locationMessage = result.message(in: launcher.language)
            locationResult = result
            if TestBuild.isTest {
                locationTrace?.outcome = Self.uiTestLocation == nil ? locator.lastOutcome ?? .locating
                    : result == .denied ? .denied : .failed(code: 0, description: "UI test")
            }
            if let area = result.area {
                withAnimation(MotionRule.change.layout(reduceMotion: reduceMotion)) {
                    position = Self.camera(on: Self.coordinate(of: area.middle))
                }
            }
        }
    }

    /// Under `-ui-testing`, in a Debug build, `-ui-test-location denied` or
    /// `failed` answers "Use my location" without asking the Simulator.
    private static var uiTestLocation: MyLocationStart? {
        #if DEBUG
        guard UITestTrace.isOn else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui-test-location"), arguments.indices.contains(index + 1) else { return nil }
        return switch arguments[index + 1] {
        case "denied": .denied
        case "failed": .failed
        default: nil
        }
        #else
        return nil
        #endif
    }

    private var places: some View {
        List {
            // Decision 262: the list's cities whose names match as the
            // player types.
            let cities = RealWorldPlace.matching(query)
            if !cities.isEmpty {
                Section {
                    ForEach(cities.prefix(50)) { place in
                        placeButton(place, id: "match")
                    }
                } header: {
                    Text(verbatim: launcher.language.text("Cities", "城市"))
                }
            }
            let stations = launcher.railways?.stations(matching: query) ?? []
            if !stations.isEmpty {
                Section("Railway Stations") {
                    ForEach(stations.prefix(50)) { station in
                        stationButton(station, showsSystem: true)
                    }
                }
            }
            // Decision 312: where games were started before, ahead of the
            // search; only while nothing is typed.
            let recent = RecentStartPlaces(stored: recentStarts).places
            if query.isEmpty, !recent.isEmpty {
                Section {
                    ForEach(Array(recent.enumerated()), id: \.offset) { index, place in
                        Button {
                            position = Self.camera(on: Self.coordinate(of: place))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.primary)
                                Text(verbatim: RecentStartPlaces.name(of: place, names: launcher.placeNames, language: launcher.language))
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .accessibilityIdentifier("recent.\(index)")
                    }
                } header: {
                    Text(verbatim: launcher.language.text("Recent", "最近用過"))
                }
            }
            if search.isSearching || search.results != nil {
                Section("Search Results") {
                    if search.isSearching {
                        ProgressView()
                    } else if let results = search.results, results.isEmpty {
                        Text("No places found.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(search.results ?? []) { result in
                        Button {
                            position = Self.camera(on: result.coordinate)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: result.name)
                                if !result.detail.isEmpty {
                                    Text(verbatim: result.detail)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Group {
                    // Decision 312: how large the start is, and whether it
                    // grows (decision 167: a place of Taiwan buys tile by tile).
                    if let startArea {
                        Text(verbatim: startArea.summary(in: launcher.language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityIdentifier("realWorld.area")
                    }
                    Text(verbatim: launcher.language.text(
                        "Tap the map or move it to place the square, then tap Build Here.",
                        "點地圖或移動地圖來放方框，再按「在這裡建造」。"
                    ))
                    // Decision 198: the ground chosen in the new game's options.
                    if launcher.newGameOptions.ground == .flat {
                        Text(verbatim: launcher.language.text(
                            "Flat ground: track on this map is always level. Change it in New Game Options.",
                            "地形平坦：這張地圖的軌道一律水平。可在「新遊戲選項」更改。"
                        ))
                    }
                }
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
            // Decision 262: by country where a country has many places, by
            // region for the rest; Taiwan's open, the others closed.
            ForEach(RealWorldPlace.groups) { group in
                Section {
                    DisclosureGroup(isExpanded: expansionBinding(group.id)) {
                        ForEach(group.places) { place in
                            placeButton(place)
                        }
                    } label: {
                        // On the label, not the group: a list's disclosure
                        // group passes its identifier to every row in it,
                        // which hid the places' own ("place.tra-taipei").
                        Text(verbatim: launcher.language.text(
                            "\(group.name(in: launcher.language)) (\(group.places.count))",
                            "\(group.name(in: launcher.language))（\(group.places.count)）"
                        ))
                        .accessibilityIdentifier("placeGroup.\(group.id)")
                    }
                }
                // Decision 88: one map of the whole of Taiwan, for lines from
                // one end of it to the other, after Taiwan's places (which
                // the UI tests tap without scrolling).
                if group.kind == .country("TW") {
                    Section {
                        Button {
                            dismiss()
                            launcher.startWholeTaiwan()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "map.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: launcher.language.text("The whole of Taiwan", "全台灣"))
                                        .font(.body)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(verbatim: launcher.language.text(
                                        "The main island and Penghu, about 286 by 390 km, all open from the start with no land to buy. Achievements and rankings do not count it. With a large network, older devices may slow down.",
                                        "本島加澎湖，約 286 × 390 公里，一開始全部開放、不用買地。不計成就與排名。路網蓋得大時，較舊的裝置可能變慢。"
                                    ))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .disabled(launcher.population == nil)
                        .accessibilityIdentifier("realWorld.wholeTaiwan")
                    }
                }
                if group.kind == .country("TW"), let railways = launcher.railways {
                    Section {
                        ForEach(RealRailways.System.all) { system in
                            let stations = railways.stations.filter { $0.system == system }
                            DisclosureGroup {
                                ForEach(stations) { station in
                                    stationButton(station, showsSystem: false)
                                }
                            } label: {
                                // On the label, as the places' groups above:
                                // on the group it hid the stations' own.
                                Text(verbatim: "\(system.name(in: launcher.language)) · \(stations.count)")
                                    .accessibilityIdentifier("railway.\(system.id)")
                            }
                        }
                    } header: {
                        Text("Railway Stations")
                    } footer: {
                        Text(verbatim: DataSourceCredits.railwaysOnMap(in: launcher.language))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Moves the map to one of the list's places.
    private func placeButton(_ place: RealWorldPlace, id prefix: String = "place") -> some View {
        Button {
            position = Self.camera(on: Self.coordinate(of: place.anchor))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primary)
                Text(verbatim: place.name(in: launcher.language))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .accessibilityIdentifier("\(prefix).\(place.id)")
    }

    /// Whether the group `id` of the list is open: only this view's, not
    /// the game's (Taiwan's open at first).
    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(id) },
            set: { open in
                if open { expandedGroups.insert(id) } else { expandedGroups.remove(id) }
            }
        )
    }

    /// Moves the map to a station of Taiwan's real railways.
    private func stationButton(_ station: RealRailways.Station, showsSystem: Bool) -> some View {
        Button {
            position = Self.camera(on: CLLocationCoordinate2D(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tram.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color(station.palette.color(.auto, on: colorScheme == .dark ? .dark : .light)))
                Text(verbatim: station.name(in: launcher.language))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if showsSystem {
                    Spacer()
                    Text(verbatim: station.system.name(in: launcher.language))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("station.\(station.id)")
    }

    /// The anchor at the middle of the view.
    private var anchor: GeoAnchor? {
        GeoAnchor(latitudeDegrees: middle.latitude, longitudeDegrees: middle.longitude)
    }

    /// The land a game here starts with (decision 312): the tile round the
    /// middle of the view where Taiwan's map is bought tile by tile
    /// (decision 167), the 16 km square otherwise.
    private var startArea: RealWorldStartArea? {
        anchor.map(RealWorldStartArea.init(middle:))
    }

    /// The corners of ``startArea``.
    private var square: [CLLocationCoordinate2D] {
        (startArea?.corners ?? []).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func start() {
        guard let anchor else { return }
        recentStarts = RecentStartPlaces(stored: recentStarts).adding(anchor).stored
        dismiss()
        launcher.openRealWorldGame(at: anchor)
    }

    // MARK: - The map

    private static func coordinate(of anchor: GeoAnchor) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees)
    }

    /// The camera on `point` with the whole game map in view, or, given
    /// the camera's `distance`, as far away as it is (a tap moves the map
    /// without zooming it).
    private static func camera(on point: CLLocationCoordinate2D, distance: Double? = nil) -> MapCameraPosition {
        if let distance {
            return .camera(MapCamera(centerCoordinate: point, distance: distance, heading: 0, pitch: 0))
        }
        let side = 2 * newMapHalfExtent.east * 1.4
        return .region(MKCoordinateRegion(center: point, latitudinalMeters: side, longitudinalMeters: side))
    }

    /// How far a new game's map reaches from its middle, in metres.
    private static let newMapHalfExtent = RealWorldFrame.halfExtent(of: GameWorld.newGameBounds)
}

/// A line of Taiwan's real railways on the picker's map: the line's own
/// colours (the site's auto track display).
struct RailwayLineDrawing: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let palette: RealRailways.Palette

    init(_ line: RealRailways.Line) {
        id = line.id
        coordinates = line.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        palette = line.palette
    }

    func color(_ theme: RealRailways.MapTheme) -> RealRailways.RGB {
        palette.color(.auto, on: theme)
    }
}

extension Color {
    /// The `Railway/` site's colour `#RRGGBB`.
    init(_ rgb: RealRailways.RGB) {
        self.init(.sRGB, red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }
}

/// A place found by a search: shown, then dropped.
struct PlaceSearchResult: Identifiable, Sendable {
    let id: Int
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Searches Apple's map for places by name, near where the map is.
@MainActor
@Observable
final class PlaceSearch {
    /// The places found by the last search; `nil` before one.
    private(set) var results: [PlaceSearchResult]?
    private(set) var isSearching = false
    @ObservationIgnored private var search: MKLocalSearch?
    /// Counts the searches, so only the last one's results are shown.
    @ObservationIgnored private var searches = 0

    func find(_ text: String, near point: CLLocationCoordinate2D) {
        clear()
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: point, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        let search = MKLocalSearch(request: request)
        self.search = search
        let number = searches
        isSearching = true
        // The search ends once, so holding `self` until then leaks nothing.
        search.start { response, _ in
            let found = (response?.mapItems ?? []).prefix(20).enumerated().map { index, item in
                PlaceSearchResult(
                    id: index,
                    name: item.name ?? "",
                    detail: item.placemark.title ?? "",
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
            }
            Task { @MainActor in
                guard self.searches == number else { return }
                self.results = found
                self.isSearching = false
            }
        }
    }

    func clear() {
        search?.cancel()
        search = nil
        searches += 1
        results = nil
        isSearching = false
    }
}
