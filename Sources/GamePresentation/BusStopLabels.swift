import Foundation
import GameCore

// Decision 424, C2: what the bus tool writes on the map beside a stop and
// along the line. A stop's number is the order the player tapped it in, 1
// the nearest the station; its name is a real bus stop's within 25 m, or
// else the name of the road it stands on, read from the base map's
// `transportation_name` layer (which has the names; the `transportation`
// layer the buses drive on has none). Names are worked out each time they
// are drawn and never saved. The line carries a round arrow every so often
// pointing at the station, and nearby real stops are drawn faint to snap
// to. Presentation only: GameCore keeps each stop as a cell and each leg as
// metres, as before.
//
// The references: geo-scene's `BusEngine.ts` lists a route's real stops by
// name and `snapToRoute`s a point onto a line (kept as C1's `nearest`); the
// owner's `MapBuilder` snapshot and the street scene have no road names or
// direction arrows on a drawn line (gap): the rest is the project's own.

/// A bus stop's number and name on the map.
public struct BusStopLabel: Hashable, Sendable {
    /// The stop's place in the route from the station out: 1 is the nearest.
    public let number: Int
    /// The real stop's name, or the road's; `nil` when neither is near.
    public let name: String?

    /// The numbers of `count` stops: 1 to `count` as the player tapped them
    /// (nearest the station first), or from `count` down to 1 as GameCore
    /// lists a saved route's stops (`farthestFirst`).
    static func numbers(count: Int, farthestFirst: Bool) -> [Int] {
        (0..<max(count, 0)).map { farthestFirst ? count - $0 : $0 + 1 }
    }
}

// MARK: - Road names

/// A named road of the base map's `transportation_name` layer.
struct NamedRoad: Sendable {
    let name: String
    let english: String?
    let points: [BusRoadNetwork.Point]
    let minX: Double, minY: Double, maxX: Double, maxY: Double

    init(name: String, english: String?, points: [BusRoadNetwork.Point]) {
        self.name = name
        self.english = english
        self.points = points
        minX = points.map(\.x).min() ?? 0
        maxX = points.map(\.x).max() ?? 0
        minY = points.map(\.y).min() ?? 0
        maxY = points.map(\.y).max() ?? 0
    }

    /// The name in `language`: the English one when the road has it.
    func displayName(in language: DisplayLanguage) -> String {
        language.text(english ?? name, name)
    }

    /// How far `point` is from the road's nearest piece, in metres.
    func distance(to point: BusRoadNetwork.Point) -> Double {
        var least = Double.infinity
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, span = dx * dx + dy * dy
            let t = span > 0 ? min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / span, 0), 1) : 0
            least = min(least, hypot(point.x - (a.x + dx * t), point.y - (a.y + dy * t)))
        }
        return least
    }
}

enum BusRoadNames {
    /// How far from a stop a named road is looked for, in metres.
    static let reach = 30.0

    /// The named roads a bus takes in tile `column`, `row`'s
    /// `transportation_name` layer (the same classes as
    /// ``BusRoadNetwork/takes(_:)``, no tunnels), in the layer's order. A road
    /// with a number but no name is left out.
    static func roads(in layer: VectorTile.Layer, column: Int, row: Int, projection: RealRoadCells.Projection) -> [NamedRoad] {
        let (west, north, scale) = projection.place(column: column, row: row, extent: layer.extent)
        var roads: [NamedRoad] = []
        for feature in layer.features where feature.kind == .line {
            guard let kind = Map3DBaseMap.roadKind(feature.string("class")), BusRoadNetwork.takes(kind),
                  feature.string("brunnel") != "tunnel", let name = feature.string("name"), !name.isEmpty
            else { continue }
            let english = feature.string("name_en").flatMap { $0.isEmpty ? nil : $0 }
            for part in feature.parts where part.count >= 2 {
                roads.append(NamedRoad(
                    name: name, english: english,
                    points: part.map { BusRoadNetwork.Point(x: west + Double($0.x) * scale, y: north + Double($0.y) * scale) }
                ))
            }
        }
        return roads
    }

    /// The road of `roads` nearest `point`, within `reach` metres; of two as
    /// near, the one whose name sorts first, so the same roads always give
    /// the same name.
    static func nearest(to point: BusRoadNetwork.Point, in roads: [NamedRoad], within reach: Double = reach) -> NamedRoad? {
        var best: (road: NamedRoad, away: Double)?
        for road in roads where road.minX - reach <= point.x && point.x <= road.maxX + reach
            && road.minY - reach <= point.y && point.y <= road.maxY + reach {
            let away = road.distance(to: point)
            guard away <= reach else { continue }
            if best.map({ away < $0.away || away == $0.away && road.name < $0.road.name }) ?? true { best = (road, away) }
        }
        return best?.road
    }
}

extension BusRoads {
    /// The name of the bus road nearest `point` within ``BusRoadNames/reach``
    /// metres, from the base map's road names; `nil` where it has none (an
    /// alley often has none).
    func roadName(near point: PlanPoint, in language: DisplayLanguage) -> String? {
        let here = BusRoadNetwork.Point(point)
        let reach = BusRoadNames.reach
        var roads: [NamedRoad] = []
        for row in projection.row(here.y - reach)...projection.row(here.y + reach) {
            for column in projection.column(here.x - reach)...projection.column(here.x + reach) {
                roads += namedRoads(column: column, row: row)
            }
        }
        return BusRoadNames.nearest(to: here, in: roads)?.displayName(in: language)
    }
}

// MARK: - Real bus stops

/// The real bus stops round a station (`RealBuses`), the same name and
/// place merged into one: drawn faint while the bus tool is open, and a tap
/// near one puts the stop there. Read only and never saved.
public final class RealBusStops: Sendable, Hashable {
    public struct Stop: Hashable, Sendable {
        public let name: String
        public let point: PlanPoint

        public init(name: String, point: PlanPoint) {
            self.name = name
            self.point = point
        }
    }

    /// How far from a tap or a stop a real stop is taken for it, in metres.
    public static let snapReach = 25.0
    /// How near two stops of one name are the same stop, in metres.
    static let mergeMetres = 10.0

    /// The stops, from west to east.
    public let stops: [Stop]

    /// `stops` with those of one name within ``mergeMetres`` of each other
    /// merged (the first of them in west-to-east order kept).
    public init(stops all: [Stop]) {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        var kept: [Stop] = []
        var ofThisName: [Stop] = []
        for stop in all.sorted(by: { ($0.name, $0.point.x, $0.point.y) < ($1.name, $1.point.x, $1.point.y) }) {
            if ofThisName.first?.name != stop.name { ofThisName = [] }
            let same = ofThisName.contains { hypot(Double($0.point.x - stop.point.x), Double($0.point.y - stop.point.y)) / metre <= Self.mergeMetres }
            guard !same else { continue }
            ofThisName.append(stop)
            kept.append(stop)
        }
        self.stops = kept.sorted { ($0.point.x, $0.point.y, $0.name) < ($1.point.x, $1.point.y, $1.name) }
    }

    public static func == (a: RealBusStops, b: RealBusStops) -> Bool { a === b }

    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// The stop nearest `point` within `metres`; of two as near, the one
    /// whose name sorts first.
    public func nearest(to point: PlanPoint, within metres: Double = RealBusStops.snapReach) -> Stop? {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let reach = Int64((metres * metre).rounded(.up))
        var best: (stop: Stop, away: Double)?
        for index in firstIndex(withXAtLeast: point.x - reach)..<stops.count {
            let stop = stops[index]
            if stop.point.x > point.x + reach { break }
            guard abs(stop.point.y - point.y) <= reach else { continue }
            let away = hypot(Double(stop.point.x - point.x), Double(stop.point.y - point.y)) / metre
            guard away <= metres else { continue }
            if best.map({ away < $0.away || away == $0.away && stop.name < $0.stop.name }) ?? true { best = (stop, away) }
        }
        return best?.stop
    }

    /// The stops inside `region`, west to east.
    public func stops(in region: WorldRegion) -> [Stop] {
        guard region.minX <= region.maxX else { return [] }
        var inside: [Stop] = []
        for index in firstIndex(withXAtLeast: Int64(region.minX.rounded(.down)))..<stops.count {
            let stop = stops[index]
            if Double(stop.point.x) > region.maxX { break }
            if Double(stop.point.y) >= region.minY, Double(stop.point.y) <= region.maxY { inside.append(stop) }
        }
        return inside
    }

    private func firstIndex(withXAtLeast x: Int64) -> Int {
        var low = 0, high = stops.count
        while low < high {
            let middle = (low + high) / 2
            if stops[middle].point.x < x { low = middle + 1 } else { high = middle }
        }
        return low
    }
}

/// `RealBuses` and the way to read its files, for the stops round a place:
/// each city's file is read once, the first time a map reaches it.
public final class RealBusLibrary: @unchecked Sendable {
    private struct Entry {
        let name: String
        let coordinate: RealRailways.Coordinate
    }

    /// How far round a station the stops are taken, in metres.
    public static let reach = 6_000.0

    private let buses: RealBuses
    private let file: @Sendable (_ name: String, _ ext: String) throws -> Data
    private let lock = NSLock()
    private var read: [String: [Entry]] = [:]

    /// The library of the index `index`, whose files `file` reads (a name
    /// and extension to its contents). Throws what ``RealBuses`` throws for
    /// an index it cannot read.
    public init(index: Data, file: @escaping @Sendable (_ name: String, _ ext: String) throws -> Data) throws {
        buses = try RealBuses(index: index)
        self.file = file
    }

    /// The real stops within `metres` of `station`, on a map laid on the
    /// Earth by `frame`. A city's file that cannot be read has none.
    public func stops(around station: PlanPoint, frame: RealWorldFrame, within metres: Double = RealBusLibrary.reach) -> RealBusStops {
        let around = frame.coordinate(worldX: Double(station.x), worldY: Double(station.y))
        let middle = RealRailways.Coordinate(latitude: around.latitude, longitude: around.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let reach = Int64((metres * metre).rounded(.up))
        var stops: [RealBusStops.Stop] = []
        lock.lock()
        defer { lock.unlock() }
        for place in buses.places(near: middle, within: metres) {
            for entry in entries(of: place) {
                let position = frame.worldPosition(latitude: entry.coordinate.latitude, longitude: entry.coordinate.longitude)
                let point = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
                if abs(point.x - station.x) <= reach, abs(point.y - station.y) <= reach { stops.append(RealBusStops.Stop(name: entry.name, point: point)) }
            }
        }
        return RealBusStops(stops: stops)
    }

    /// Every stop of `place`'s routes (the lock is held).
    private func entries(of place: RealBuses.Place) -> [Entry] {
        if let known = read[place.city] { return known }
        var entries: [Entry] = []
        let split = place.file.lastIndex(of: ".")
        let name = split.map { String(place.file[..<$0]) } ?? place.file
        let ext = split.map { String(place.file[place.file.index(after: $0)...]) } ?? ""
        if let data = try? file(name, ext), let routes = try? buses.routes(of: place, data: data) {
            entries = routes.flatMap { $0.stops.map { Entry(name: $0.name, coordinate: $0.coordinate) } }
        }
        read[place.city] = entries
        return entries
    }
}

// MARK: - Direction arrows

/// A round arrow on a bus line: where it is, and the way it points as a
/// unit vector of the plan (x east, y south).
public struct BusArrow: Hashable, Sendable {
    public let point: PlanPoint
    public let dx: Double
    public let dy: Double
}

public enum BusArrows {
    /// The arrows are at least this far apart, in metres, and at least
    /// ``minimumPoints`` screen points apart: whichever is farther.
    public static let minimumMetres = 200.0
    public static let minimumPoints = 120.0
    /// A line shorter than this, in metres, has no arrow.
    public static let shortestLine = 40.0

    /// The metres between arrows when the map shows `pointsPerMetre` screen
    /// points to a metre.
    public static func spacing(pointsPerMetre: Double) -> Double {
        pointsPerMetre > 0 ? max(minimumMetres, minimumPoints / pointsPerMetre) : minimumMetres
    }

    /// The arrows along `points` (the way the bus runs: from the farthest
    /// stop to the station), as many as fit `spacing` metres apart and at
    /// least one, spread evenly, the first and last half a gap in. Each
    /// points along its piece of the line.
    public static func arrows(along points: [PlanPoint], every spacing: Double) -> [BusArrow] {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let lengths = zip(points, points.dropFirst()).map { hypot(Double($1.x - $0.x), Double($1.y - $0.y)) / metre }
        let total = lengths.reduce(0, +)
        guard total >= shortestLine, spacing > 0 else { return [] }
        let count = max(1, Int(total / spacing))
        var arrows: [BusArrow] = []
        var piece = 0, before = 0.0
        for number in 0..<count {
            let wanted = total * (Double(number) + 0.5) / Double(count)
            while piece < lengths.count - 1, before + lengths[piece] < wanted {
                before += lengths[piece]
                piece += 1
            }
            let length = lengths[piece]
            guard length > 0 else { continue }
            let a = points[piece], b = points[piece + 1]
            let t = min(max((wanted - before) / length, 0), 1)
            arrows.append(BusArrow(
                point: PlanPoint(x: a.x + Int64((Double(b.x - a.x) * t).rounded()), y: a.y + Int64((Double(b.y - a.y) * t).rounded())),
                dx: Double(b.x - a.x) / metre / length, dy: Double(b.y - a.y) / metre / length
            ))
        }
        return arrows
    }
}
