import Foundation
import GameCore

// Real stations as suggested sites (ARCHITECTURE decision 295; NEXT_PRIORITIES
// §17.1 first, the City Transport Manager study 4.5): on a real-world map,
// while the platform tool is chosen, the real stations on the company's land
// that no station of the world is yet are offered as faint pins. A tap on
// one picks the nearest place on the track within reach of it for the next
// platform and names the station after it; the player builds it with the
// map's ✓ as after any tap on the track. Nothing here changes the world.
//
// ``GameSession/nearestRealStation(to:within:)`` is the one query that finds
// the real station at a place; transfer stations (R1, §17) use it too.

/// A real station the map offers: one place, with every real station there
/// of the same name (台北: the TRA's, the high-speed railway's and the
/// metro's), where it is on the world's map and the name a station built
/// after it takes.
public struct RealStationSuggestion: Identifiable, Hashable, Sendable {
    /// The real stations at the place, in the site's order: the first is
    /// the one the place is named and drawn after.
    public let stations: [RealRailways.Station]
    /// Where the first one is, in world units.
    public let point: PlanPoint
    /// How far it is from the point asked about, in metres; 0 for the map's
    /// pins, which are not asked about from a point.
    public let distanceMetres: Double

    public var id: String { stations[0].id }

    /// The name a station built after it takes in `language`.
    public func name(in language: DisplayLanguage) -> String {
        stations[0].name(in: language)
    }

    /// The systems that stop there, without repeats, in the site's order.
    public var systems: [RealRailways.System] {
        var seen: Set<String> = []
        return stations.map(\.system).filter { seen.insert($0.id).inserted }
    }

    /// About a pin's size on the screen, in points, with a little room
    /// round it: a ring and a name of three or four characters.
    public static let pinWidth: Double = 76
    public static let pinHeight: Double = 26

    /// The pins of `pins`, at their (`x`, `y`) on the screen, to draw: each
    /// that overlaps none already kept, a place more systems stop at
    /// first, then in the order given. Every one shows again as the map is
    /// brought closer, as the sights do (decision 250).
    public static func shown(_ pins: [(suggestion: RealStationSuggestion, x: Double, y: Double)]) -> Set<String> {
        var kept: [(x: Double, y: Double)] = []
        var ids: Set<String> = []
        let ordered = pins.enumerated().sorted {
            let a = $0.element.suggestion.systems.count, b = $1.element.suggestion.systems.count
            return a != b ? a > b : $0.offset < $1.offset
        }
        for pin in ordered.map(\.element)
        where kept.allSatisfy({ abs($0.x - pin.x) >= pinWidth || abs($0.y - pin.y) >= pinHeight }) {
            kept.append((pin.x, pin.y))
            ids.insert(pin.suggestion.id)
        }
        return ids
    }
}

extension GameSession {
    /// How far from a pin the track may be for a tap on it to put the
    /// platform there: 400 m, so the station's middle stays within the
    /// 450 m at which it is recognised as the real one
    /// (``RealRailways/stations(named:near:)``) when the platform moves
    /// along the track to fit on it.
    public static let realStationTrackReachMetres = 400.0

    /// The real stations of the map in world units round `point` within
    /// `metres`, nearest first, one for each place
    /// (``RealStationSuggestion``); none on a blank map or without the
    /// railways. The query every use of "the real station here" goes
    /// through.
    public func realStations(near point: PlanPoint, within metres: Double) -> [RealStationSuggestion] {
        guard let railways, let frame = RealWorldFrame(world: world) else { return [] }
        let coordinate = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
        let near = railways.nearbyStations(
            to: RealRailways.Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
            maximumDistanceMetres: metres
        )
        return Self.places(near.map(\.station), railways: railways).compactMap { stations in
            let first = stations[0]
            let distance = near.first { $0.station == first }?.distanceMetres ?? 0
            return suggestion(stations, frame: frame, distanceMetres: distance)
        }.sorted { ($0.distanceMetres, $0.id) < ($1.distanceMetres, $1.id) }
    }

    /// The real station nearest `point`, if one is within `metres`: by
    /// default the site's transfer distance (450 m), at which a station of
    /// the world named after it is that real station.
    public func nearestRealStation(to point: PlanPoint, within metres: Double? = nil) -> RealStationSuggestion? {
        let reach = metres ?? railways?.transfers?.maximumDistanceMetres ?? 450
        return realStations(near: point, within: reach).first
    }

    /// Whether the map offers real stations now: on a real-world map with
    /// the railways, while a platform's place is being chosen.
    public var offersRealStations: Bool {
        tool == .network && networkMode == .platform && railways != nil && RealWorldFrame(world: world) != nil
    }

    /// The pins the map draws (``offersRealStations``): every place with a
    /// real station inside the world on land the company owns that no
    /// station of the world is yet, in the site's order. A station of the
    /// world is a real one when it has its name, in any language or
    /// spelling, within 450 m (``realStations(named:at:)``), as the station
    /// card already tells.
    public var realStationSuggestions: [RealStationSuggestion] {
        guard offersRealStations, let railways, let frame = RealWorldFrame(world: world) else { return [] }
        let region = WorldRegion(bounds: world.bounds)
        let corners = [
            frame.coordinate(worldX: region.minX, worldY: region.minY),
            frame.coordinate(worldX: region.maxX, worldY: region.maxY),
        ]
        let latitudes = corners.map(\.latitude), longitudes = corners.map(\.longitude)
        let inside = railways.stations.filter {
            (latitudes.min()!...latitudes.max()!).contains($0.coordinate.latitude)
                && (longitudes.min()!...longitudes.max()!).contains($0.coordinate.longitude)
        }
        var built: Set<String> = []
        for station in world.stations {
            for real in realStations(named: station.name, at: station.location) {
                built.insert(real.id)
            }
        }
        return Self.places(inside, railways: railways).compactMap { stations in
            guard stations.allSatisfy({ !built.contains($0.id) }),
                  let found = suggestion(stations, frame: frame, distanceMetres: 0),
                  world.bounds.contains(found.point), world.ownsGround(at: found.point) else { return nil }
            return found
        }
    }

    /// Picks the place for the next platform on the track nearest
    /// `suggestion`, within ``realStationTrackReachMetres``, as a tap there
    /// would (``tapNetwork(at:reach:)``), and names a new station after
    /// it, replacing even a name the player typed: the pin was asked for.
    /// A platform beside a station of the world joins that one, as any
    /// other does. Where no track is that near, says so and picks nothing.
    public func pickRealStation(_ suggestion: RealStationSuggestion) {
        guard networkMode == .platform else { return }
        message = nil
        let reach = Int64(Self.realStationTrackReachMetres * Double(WorldCoordinate.unitsPerMetre))
        guard let place = world.trackEdgePoint(near: suggestion.point, within: reach) else {
            networkEdgePoint = nil
            platformStationID = nil
            let name = suggestion.name(in: language)
            message = StatusMessage(kind: .failure, text: language.text(
                "No track within 400 m of \(name) yet. Lay track there first, then tap \(name) again.",
                "\(name) 400 公尺內還沒有軌道。先在那裡鋪軌，再點一次 \(name)。"
            ))
            return
        }
        pickPlatformPlace(place, named: suggestion.name(in: language))
    }

    /// The stations of `stations` grouped by place: those with the same
    /// name key (``RealRailways/stationKey(_:)``) within the site's
    /// transfer distance of the group's first are one place, in the order
    /// of `stations`.
    nonisolated static func places(_ stations: [RealRailways.Station], railways: RealRailways) -> [[RealRailways.Station]] {
        let reach = railways.transfers?.maximumDistanceMetres ?? 450
        var groups: [(key: String, stations: [RealRailways.Station])] = []
        for station in stations {
            let key = RealRailways.stationKey(station.chinese)
            if let index = groups.firstIndex(where: {
                $0.key == key && $0.stations[0].coordinate.distance(to: station.coordinate) < reach
            }) {
                groups[index].stations.append(station)
            } else {
                groups.append((key, [station]))
            }
        }
        return groups.map(\.stations)
    }

    private func suggestion(_ stations: [RealRailways.Station], frame: RealWorldFrame, distanceMetres: Double) -> RealStationSuggestion? {
        guard let first = stations.first else { return nil }
        let position = frame.worldPosition(latitude: first.coordinate.latitude, longitude: first.coordinate.longitude)
        return RealStationSuggestion(
            stations: stations,
            point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())),
            distanceMetres: distanceMetres
        )
    }
}
