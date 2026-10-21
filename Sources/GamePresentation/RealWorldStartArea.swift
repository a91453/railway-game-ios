import Foundation
import GameCore

// The land a real-world game starts with, as the place picker draws it
// (ARCHITECTURE decision 312, the competitor study's 4.6): a frame on the
// map that a tap moves, with its area and whether more land can be bought
// later. A place of Taiwan starts with one tile and buys the rest
// (decision 167); a place elsewhere is the 16 km square, its whole map.
//
// The owner's references have no start area to port (gap): `MapBuilder/`
// and `Railway/city_world_reference/` have no chosen region on a map, and
// `Ci/`'s "any city" is a centre with no frame. The list of recent places
// follows `Ci/`'s recent aircraft (`flight_planner_panel`: newest first,
// no repeats, a few kept).

/// Where a real-world game starts: the land round `middle`.
public struct RealWorldStartArea: Hashable, Sendable {
    /// The middle of the land: where the player pointed.
    public let middle: GeoAnchor
    /// The map that buys its land tile by tile (decision 167), or `nil`
    /// where the start is the whole 16 km map.
    public let expansion: RealWorldExpansion?

    /// The start round `middle`.
    public init(middle: GeoAnchor) {
        self.middle = middle
        expansion = RealWorldExpansion(around: middle)
    }

    /// The start round the point nearest `latitude`°, `longitude`° whose
    /// land lies wholly on the map (``middle(latitude:longitude:)``), or
    /// `nil` for a point that is not one.
    public init?(latitude: Double, longitude: Double) {
        guard let middle = Self.middle(latitude: latitude, longitude: longitude) else { return nil }
        self.init(middle: middle)
    }

    /// Whether more land can be bought round it later (decision 167).
    public var buysMoreLand: Bool {
        expansion != nil
    }

    /// The land's width and height on the ground, in metres, along its
    /// middle's latitude and longitude. A new game's map is 16,384 m a
    /// side at its middle; a tile of Taiwan is 16,384 world metres, which
    /// are metres at the map's own anchor (``RealWorldExpansion/anchor``),
    /// so a little less on the ground north of it (about 16.2 km at
    /// Taipei).
    public var groundMetres: (width: Double, height: Double) {
        let corners = corners
        let metresPerDegree = 2 * Double.pi * RealWorldFrame.earthRadius / 360
        let width = (corners[1].longitude - corners[0].longitude) * metresPerDegree * cos(middle.latitudeDegrees * .pi / 180)
        let height = (corners[0].latitude - corners[3].latitude) * metresPerDegree
        return (width, height)
    }

    /// The area on the ground in square kilometres (about 268 for a map
    /// abroad, 262 for a tile at Taipei).
    public var squareKilometres: Double {
        let ground = groundMetres
        return ground.width * ground.height / 1_000_000
    }

    /// The area as the picker's card says it: "268 km²", the sides to a
    /// tenth of a kilometre ("16.4 × 16.4 km").
    public func areaText(in language: DisplayLanguage) -> String {
        let area = Int(squareKilometres.rounded())
        let ground = groundMetres
        let width = (ground.width / 100).rounded() / 10, height = (ground.height / 100).rounded() / 10
        return language.text(
            "\(area) km² (\(width) × \(height) km)",
            "\(area) 平方公里（\(width) × \(height) 公里）"
        )
    }

    /// What the card says of the start: its area, and whether the land can
    /// grow.
    public func summary(in language: DisplayLanguage) -> String {
        let area = areaText(in: language)
        if buysMoreLand {
            return language.text(
                "You start with \(area) of land. You can buy land later to grow it.",
                "一開始的土地約 \(area)，之後可以買地擴大。"
            )
        }
        return language.text(
            "Your map is \(area). It stays this size.",
            "地圖約 \(area)，之後不會再擴大。"
        )
    }

    /// The corners of the land on the Earth, north-west first and going
    /// clockwise, in degrees: where the map draws the frame. The same
    /// Web Mercator the game lays its world on (``RealWorldFrame``).
    public var corners: [(latitude: Double, longitude: Double)] {
        if let expansion {
            let frame = expansion.frame
            let length = Double(MapExpansion.tileLength)
            let west = Double(expansion.start.column) * length, north = Double(expansion.start.row) * length
            return [(west, north), (west + length, north), (west + length, north + length), (west, north + length)].map {
                frame.coordinate(worldX: $0.0, worldY: $0.1)
            }
        }
        let bounds = GameWorld.newGameBounds
        let frame = RealWorldFrame(anchor: middle, bounds: bounds)
        let width = Double(bounds.width), height = Double(bounds.height)
        return [(0, 0), (width, 0), (width, height), (0, height)].map { frame.coordinate(worldX: $0.0, worldY: $0.1) }
    }

    // MARK: - Where it can lie

    /// How far a new game's map reaches from its middle, in metres.
    static let newMapHalfExtent = RealWorldFrame.halfExtent(of: GameWorld.newGameBounds)

    /// The farthest north or south the middle can lie with the land wholly
    /// on the map: the map (Web Mercator, as MapKit's) ends at about
    /// 85.05°, and the land reaches half a side beyond its middle.
    public static let maximumLatitude: Double = {
        let half = newMapHalfExtent.south
        // Whether the land round `latitude` stays within the map's top.
        func fits(_ latitude: Double) -> Bool {
            let pointsPerMetre = RealWorldFrame.worldPoints / (2 * Double.pi * RealWorldFrame.earthRadius * cos(latitude * .pi / 180))
            return RealWorldFrame.mercatorY(latitude) - half * pointsPerMetre >= 0
        }
        var low = 0.0, high = 89.9
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        // Rounded down to the anchor's ten-millionth of a degree.
        return (low * GeoAnchor.unitsPerDegree).rounded(.down) / GeoAnchor.unitsPerDegree
    }()

    /// The middle nearest `latitude`°, `longitude`° whose land lies wholly
    /// on the map: the latitude kept within ±``maximumLatitude``, the
    /// longitude brought into -180° to 180°. `nil` for a point that is not
    /// a number.
    public static func middle(latitude: Double, longitude: Double) -> GeoAnchor? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        // The anchor brings the longitude round the Earth itself.
        return GeoAnchor(latitudeDegrees: min(max(latitude, -maximumLatitude), maximumLatitude), longitudeDegrees: longitude)
    }
}

/// The places a real-world game was started at on this device, newest
/// first, for the picker to list before its search (decision 312). Only
/// the middles are kept, never a search's results (Apple's map data,
/// which may not be kept; see ``RealWorldPlace``); the names are the
/// app's own, looked up as the list is shown.
public struct RecentStartPlaces: Hashable, Sendable {
    /// How many are kept.
    public static let limit = 5
    /// Starts nearer than this to one already listed replace it, in
    /// metres: the same place, moved a little.
    public static let samePlaceMetres = 1_000.0

    public private(set) var places: [GeoAnchor]

    public init(_ places: [GeoAnchor] = []) {
        self.places = Array(places.prefix(Self.limit))
    }

    /// The list with `place` first, without one that was the same place,
    /// and no longer than ``limit``.
    public func adding(_ place: GeoAnchor) -> RecentStartPlaces {
        let others = places.filter { Self.metres(from: $0, to: place) >= Self.samePlaceMetres }
        return RecentStartPlaces([place] + others)
    }

    /// The list as kept in the app's settings: each place's latitude and
    /// longitude in ten-millionths of a degree, `;` between places.
    public var stored: String {
        places.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";")
    }

    /// The list kept as ``stored``; a place that does not read is left out.
    public init(stored: String) {
        let places = stored.split(separator: ";").compactMap { item -> GeoAnchor? in
            let parts = item.split(separator: ",")
            guard parts.count == 2, let latitude = Int64(parts[0]), let longitude = Int64(parts[1]) else { return nil }
            return GeoAnchor(latitude: latitude, longitude: longitude)
        }
        self.init(places)
    }

    /// What the list calls `place`: the nearest name of the app's place
    /// names (a settlement, village or ward, else the township it is in),
    /// else the list's nearest place within 20 km, else its latitude and
    /// longitude.
    public static func name(of place: GeoAnchor, names: PlaceNames?, language: DisplayLanguage) -> String {
        let point = RealRailways.Coordinate(latitude: place.latitudeDegrees, longitude: place.longitudeDegrees)
        if let names, let name = names.nearby(point).first ?? names.township(containing: point) {
            return name.name(in: language)
        }
        let nearest = RealWorldPlace.all.min { metres(from: $0.anchor, to: place) < metres(from: $1.anchor, to: place) }
        if let nearest, metres(from: nearest.anchor, to: place) <= 20_000 {
            return nearest.name(in: language)
        }
        let latitude = String(format: "%.2f°%@", abs(place.latitudeDegrees), place.latitudeDegrees < 0 ? "S" : "N")
        let longitude = String(format: "%.2f°%@", abs(place.longitudeDegrees), place.longitudeDegrees < 0 ? "W" : "E")
        return "\(latitude) \(longitude)"
    }

    /// The distance between two places on the ground, in metres
    /// (haversine on a sphere of the Earth's mean radius).
    static func metres(from a: GeoAnchor, to b: GeoAnchor) -> Double {
        let radians = Double.pi / 180
        let dLatitude = (b.latitudeDegrees - a.latitudeDegrees) * radians
        let dLongitude = (b.longitudeDegrees - a.longitudeDegrees) * radians
        let h = sin(dLatitude / 2) * sin(dLatitude / 2)
            + cos(a.latitudeDegrees * radians) * cos(b.latitudeDegrees * radians) * sin(dLongitude / 2) * sin(dLongitude / 2)
        return 2 * 6_371_008.8 * asin(min(1, h.squareRoot()))
    }
}
