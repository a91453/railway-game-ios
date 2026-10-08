import Foundation
import GameCore

/// How far a line reaches, by the spacing of its stations (decision 89):
/// MapBuilder's levels (`MapBuilder/reference_snapshot/_next/static/chunks/pages/_app-70b32b07723ca1d7.js`,
/// `W`), each shown on the map above its zoom. MapBuilder picks its map's
/// level by `getLevel({avgSpacing})`: the first whose spacing threshold the
/// average spacing is below; here every line has its own.
public enum MapLineLevel: Int, CaseIterable, Comparable, Sendable {
    /// Stations under 2 km apart on average: a metro or tram.
    case local
    /// Under 10 km: a commuter or regional railway.
    case regional
    /// Under 50 km: an intercity or high-speed line.
    case long
    /// Farther.
    case extraLong

    /// The average spacing a line's level is below, in kilometres
    /// (MapBuilder's `spacingThreshold`).
    public var spacingThreshold: Double {
        switch self {
        case .local: 2
        case .regional: 10
        case .long: 50
        case .extraLong: .infinity
        }
    }

    /// The map zoom above which the level's stations are named when the
    /// map is zoomed out (MapBuilder's `zoomThreshold`, in MapLibre's zoom:
    /// the Earth is 512 · 2^z points wide).
    public var zoomThreshold: Double {
        switch self {
        case .local: 9.5
        case .regional: 7
        case .long: 3.5
        case .extraLong: 1.1
        }
    }

    /// The level of a line whose stations are `kilometres` apart on
    /// average.
    public static func level(averageSpacing kilometres: Double) -> MapLineLevel {
        allCases.first { kilometres < $0.spacingThreshold } ?? .extraLong
    }

    public static func < (lhs: MapLineLevel, rhs: MapLineLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Which stations are named on a zoomed-out map, and which first
/// (decision 89): a station takes the highest level of the lines that stop
/// at it (``MapLineLevel``), local without one, and is named once the map
/// is zoomed in past its level's threshold; the higher levels, then the
/// stations more lines stop at, then the lower IDs come first, so a name
/// that would cover another gives way to it.
///
/// Derived from the lines and the stations only, so it is worked out again
/// only after an edit, with the lines' map.
public struct StationLabels: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let station: StationID
        public let level: MapLineLevel
        /// How many lines stop at it.
        public let lines: Int
    }

    /// Every station, first named first.
    public let ranked: [Entry]

    public init() {
        ranked = []
    }

    public init(world: GameWorld) {
        let points = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.id, $0.location) })
        var levels: [StationID: MapLineLevel] = [:]
        var counts: [StationID: Int] = [:]
        for line in world.lines {
            let level = Self.level(of: line, points: points)
            for station in Set(line.stops) {
                levels[station] = max(levels[station] ?? .local, level)
                counts[station, default: 0] += 1
            }
        }
        ranked = world.stations
            .map { Entry(station: $0.id, level: levels[$0.id] ?? .local, lines: counts[$0.id] ?? 0) }
            .sorted { ($1.level, $1.lines, $0.station) < ($0.level, $0.lines, $1.station) }
    }

    /// The level of `line`: the average straight-line distance between
    /// its stops one after another (a ring's last back to its first), in
    /// world kilometres.
    static func level(of line: ServiceLine, points: [StationID: PlanPoint]) -> MapLineLevel {
        let stops = line.isRing ? line.stops + line.stops.prefix(1) : line.stops
        var total = 0.0, gaps = 0
        for (a, b) in zip(stops, stops.dropFirst()) {
            guard let p = points[a], let q = points[b] else { continue }
            let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
            total += (dx * dx + dy * dy).squareRoot()
            gaps += 1
        }
        guard gaps > 0 else { return .local }
        return MapLineLevel.level(averageSpacing: total / Double(gaps) / Double(WorldCoordinate.unitsPerMetre) / 1_000)
    }

    /// The stations named at map zoom `zoom`, first named first: those
    /// whose level's threshold the zoom is above.
    public func named(atZoom zoom: Double) -> [Entry] {
        ranked.filter { zoom > $0.level.zoomThreshold }
    }

    /// The map zoom (MapLibre's: the Earth 512 · 2^z points wide) of a map
    /// drawn `pointsPerUnit` points a world unit, a world unit being 1/64 m
    /// at `latitude` (a real-world map's anchor; the equator for a blank
    /// map).
    public static func zoom(pointsPerUnit: Double, latitude: Double = 0) -> Double {
        let pointsPerMetre = pointsPerUnit * Double(WorldCoordinate.unitsPerMetre)
        let earth = 2 * Double.pi * RealWorldFrame.earthRadius * cos(latitude * .pi / 180)
        return log2(pointsPerMetre * earth / 512)
    }
}
