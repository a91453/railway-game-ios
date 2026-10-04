import GameCore
import GamePresentation
import MapKit
import SwiftUI

/// Chooses where a real-world game's map lies (Stage E2, ARCHITECTURE
/// decision 50), after the `Ci/` reference's city choice (`CITIES`, and
/// its "any city" from a point on the map): a place from the references'
/// list or from a search moves the map there, the player moves it to taste,
/// and the game's 16 km map starts with its middle at the middle of the
/// view.
///
/// Only that middle is kept, as the world's anchor. A search's results are
/// Apple's map data, shown with the map and dropped (Attachment 6 §2.4 and
/// §2.5 of the Apple Developer Program License Agreement).
struct RealWorldPicker: View {
    let launcher: GameLauncher
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    /// The middle of the map in view: where the game's map would start.
    @State private var middle: CLLocationCoordinate2D
    @State private var query = ""
    @State private var search = PlaceSearch()

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
    private var preview: some View {
        Map(position: $position) {
            MapPolygon(coordinates: Self.square(around: middle))
                .foregroundStyle(Palette.station.opacity(0.08))
                .stroke(Palette.station, lineWidth: 2)
        }
        .mapStyle(.standard(emphasis: .muted))
        .onMapCameraChange(frequency: .continuous) { context in
            middle = context.region.center
        }
        .overlay {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.station)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("realWorld.map")
    }

    private var places: some View {
        List {
            if search.isSearching || search.results != nil {
                Section("Search Results") {
                    if search.isSearching {
                        ProgressView()
                    } else if let results = search.results, results.isEmpty {
                        Text("No places found.")
                            .foregroundStyle(.secondary)
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
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Text("The square is your map, 16 km a side. Move the map to choose where its middle is, then tap Build Here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(RealWorldPlace.Region.allCases, id: \.self) { region in
                Section {
                    ForEach(RealWorldPlace.all.filter { $0.region == region }) { place in
                        Button {
                            position = Self.camera(on: Self.coordinate(of: place.anchor))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.station)
                                Text(verbatim: place.name(in: launcher.language))
                                    .font(.body)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .accessibilityIdentifier("place.\(place.id)")
                    }
                } header: {
                    Text(verbatim: region.name(in: launcher.language))
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// The anchor at the middle of the view.
    private var anchor: GeoAnchor? {
        GeoAnchor(latitudeDegrees: middle.latitude, longitudeDegrees: middle.longitude)
    }

    private func start() {
        guard let anchor else { return }
        dismiss()
        launcher.startNewGame(at: anchor)
    }

    // MARK: - The map

    private static func coordinate(of anchor: GeoAnchor) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: anchor.latitudeDegrees, longitude: anchor.longitudeDegrees)
    }

    /// The camera on `point` with the whole game map in view.
    private static func camera(on point: CLLocationCoordinate2D) -> MapCameraPosition {
        let side = 2 * newMapHalfExtent.east * 1.4
        return .region(MKCoordinateRegion(center: point, latitudinalMeters: side, longitudinalMeters: side))
    }

    /// The corners of a new game's map with its middle at `point`, laid
    /// over the Earth as the game lays it (``AppleMapBackground``): metres
    /// at `point`'s latitude in MapKit's map points.
    private static func square(around point: CLLocationCoordinate2D) -> [CLLocationCoordinate2D] {
        let middle = MKMapPoint(point)
        let pointsPerMetre = MKMapPointsPerMeterAtLatitude(point.latitude)
        let east = newMapHalfExtent.east * pointsPerMetre, south = newMapHalfExtent.south * pointsPerMetre
        let corners: [(x: Double, y: Double)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        return corners.map { corner in
            MKMapPoint(x: middle.x + corner.x * east, y: middle.y + corner.y * south).coordinate
        }
    }

    /// How far a new game's map reaches from its middle, in metres.
    private static let newMapHalfExtent = RealWorldFrame.halfExtent(of: GameWorld.newGameBounds)
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
