import Foundation
import GameCore

// Decision 468: the real lines drawn on a real-world map, and their trains
// (decision 304), are only a picture. Where the player has laid track along
// a real line, the picture makes way for the player's: the stretch of the
// real line the track covers is not drawn, a real line whose stations the
// player's stations have mostly taken (the same name within 450 m, as the
// station card finds them) runs no real trains, and on a line covered only
// in part the real trains are not drawn on the covered stretch. Taking the
// track away draws them again. Worked out once for each change of the
// player's track and stations, off the main actor.

/// What of the real railways makes way for the player's track and stations.
public struct RealRailwayYield: Sendable, Equatable {
    /// For each real line (``RealRailways/Line/id``) the player's track
    /// covers some of, the pieces of it still drawn; a line not here is
    /// drawn whole.
    public let pieces: [Int: [[RealRailways.Coordinate]]]
    /// The real operation lines (`system:line`, as ``RealTrainTraffic``
    /// keys a bought line) whose trains are not drawn at all.
    public let quietLines: Set<String>
    /// The covered places along the real lines, by cell, with the line's
    /// way there: a real train on one, running along it, is not drawn.
    let covered: [Cell: [Place]]

    struct Cell: Hashable, Sendable {
        let x: Int
        let y: Int
    }

    struct Place: Sendable {
        let x: Double, y: Double
        let dx: Double, dy: Double
    }

    /// Nothing makes way.
    public static let none = RealRailwayYield(pieces: [:], quietLines: [], covered: [:])

    init(pieces: [Int: [[RealRailways.Coordinate]]], quietLines: Set<String>, covered: [Cell: [Place]]) {
        self.pieces = pieces
        self.quietLines = quietLines
        self.covered = covered
    }

    public static func == (lhs: RealRailwayYield, rhs: RealRailwayYield) -> Bool {
        lhs.pieces == rhs.pieces && lhs.quietLines == rhs.quietLines
    }

    static let metre = Double(WorldCoordinate.unitsPerMetre)
    /// How near a real line the player's track runs to cover it: a traced
    /// edge keeps within 3 m of it, a double track's second 5 m beside.
    static let reach = 10 * metre
    /// How far apart the places along a line are that are looked at.
    static let step = 10 * metre
    /// The shortest covered stretch that is not drawn: shorter ones are
    /// where the player's track crosses the real line.
    static let shortest = 60 * metre
    /// How nearly the player's track runs the real line's way: within 30°.
    static let parallel = cos(30 * Double.pi / 180)
    /// The cells places are kept in, in world units.
    static let cell = 32 * metre
    /// The share of a real line's stations on the map, more than which,
    /// taken by the player's, quiets its trains: most of them.
    static let quietShare = 0.5

    /// The way `railways` and `operations` make way for `world`'s track
    /// and stations on a map at `frame`.
    public init(railways: RealRailways, operations: RealRailwayOperations?, world: GameWorld, frame: RealWorldFrame) {
        // The player's track, every ``step``, with its way, by cell.
        var track: [Cell: [Place]] = [:]
        for edge in world.network.edges {
            guard let points = world.trackGeometry(of: edge.id)?.points, points.count > 1 else { continue }
            for (a, b) in zip(points, points.dropFirst()) {
                let ax = Double(a.x), ay = Double(a.y), bx = Double(b.x), by = Double(b.y)
                let length = ((bx - ax) * (bx - ax) + (by - ay) * (by - ay)).squareRoot()
                guard length > 0 else { continue }
                let count = max(1, Int((length / Self.step).rounded(.up)))
                for index in 0...count {
                    let t = Double(index) / Double(count)
                    let place = Place(x: ax + (bx - ax) * t, y: ay + (by - ay) * t, dx: (bx - ax) / length, dy: (by - ay) / length)
                    track[Self.cell(of: place.x, place.y), default: []].append(place)
                }
            }
        }

        var pieces: [Int: [[RealRailways.Coordinate]]] = [:]
        var covered: [Cell: [Place]] = [:]
        if !track.isEmpty {
            let half = RealWorldFrame.halfExtent(of: world.bounds)
            let lines = railways.lines(near: frame.anchor, within: max(half.east, half.south) * 1.5 + 2_000)
            for line in lines where line.points.count > 1 {
                guard let cut = Self.cut(line, frame: frame, track: track, covered: &covered) else { continue }
                pieces[line.id] = cut
            }
        }
        self.pieces = pieces
        self.covered = covered
        quietLines = operations.map { Self.quietLines(of: $0, railways: railways, world: world, frame: frame) } ?? []
    }

    static func cell(of x: Double, _ y: Double) -> Cell {
        Cell(x: Int((x / cell).rounded(.down)), y: Int((y / cell).rounded(.down)))
    }

    /// Whether a place of the player's track lies within ``reach`` of
    /// (`x`, `y`) running along (`dx`, `dy`).
    private static func near(_ x: Double, _ y: Double, way dx: Double, _ dy: Double, in places: [Cell: [Place]], reach: Double) -> Bool {
        let centre = cell(of: x, y)
        let span = Int((reach / cell).rounded(.up))
        for cx in (centre.x - span)...(centre.x + span) {
            for cy in (centre.y - span)...(centre.y + span) {
                for place in places[Cell(x: cx, y: cy)] ?? [] {
                    let ex = place.x - x, ey = place.y - y
                    guard ex * ex + ey * ey <= reach * reach else { continue }
                    if abs(place.dx * dx + place.dy * dy) >= parallel { return true }
                }
            }
        }
        return false
    }

    /// `line` with the stretches `track` covers cut out, those stretches'
    /// places added to `covered`; `nil` where none is covered.
    private static func cut(_ line: RealRailways.Line, frame: RealWorldFrame, track: [Cell: [Place]], covered: inout [Cell: [Place]]) -> [[RealRailways.Coordinate]]? {
        let world = line.points.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
        var along: [Double] = [0]
        for (a, b) in zip(world, world.dropFirst()) {
            along.append(along[along.count - 1] + ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot())
        }
        guard let total = along.last, total > 0 else { return nil }

        // Each place along it, and whether it is covered.
        var places: [(at: Double, place: Place, covered: Bool)] = []
        for index in world.indices.dropLast() {
            let a = world[index], b = world[index + 1]
            let length = along[index + 1] - along[index]
            guard length > 0 else { continue }
            let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
            let count = max(1, Int((length / step).rounded(.up)))
            for step in 0..<count {
                let t = Double(step) / Double(count)
                let x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                places.append((along[index] + length * t, Place(x: x, y: y, dx: dx, dy: dy), near(x, y, way: dx, dy, in: track, reach: reach)))
            }
        }
        if let a = world.last, let b = world.dropLast().last {
            let length = total - along[along.count - 2]
            let dx = length > 0 ? (a.x - b.x) / length : 0, dy = length > 0 ? (a.y - b.y) / length : 0
            places.append((total, Place(x: a.x, y: a.y, dx: dx, dy: dy), near(a.x, a.y, way: dx, dy, in: track, reach: reach)))
        }

        // The covered stretches long enough not to be a crossing.
        var stretches: [ClosedRange<Double>] = []
        var index = 0
        while index < places.count {
            guard places[index].covered else {
                index += 1
                continue
            }
            var end = index
            while end + 1 < places.count, places[end + 1].covered { end += 1 }
            let range = places[index].at...places[end].at
            if range.upperBound - range.lowerBound >= shortest {
                stretches.append(range)
                for place in places[index...end] {
                    covered[cell(of: place.place.x, place.place.y), default: []].append(place.place)
                }
            }
            index = end + 1
        }
        guard !stretches.isEmpty else { return nil }

        // The line between them, cut where each begins and ends.
        func point(at distance: Double) -> RealRailways.Coordinate {
            let index = max(0, min(along.count - 2, (along.lastIndex { $0 <= distance } ?? 0)))
            let span = along[index + 1] - along[index]
            let t = span > 0 ? (distance - along[index]) / span : 0
            let a = line.points[index], b = line.points[index + 1]
            return RealRailways.Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
        }
        func piece(from start: Double, to end: Double) -> [RealRailways.Coordinate]? {
            guard end - start > 0 else { return nil }
            let inside = line.points.indices.filter { along[$0] > start && along[$0] < end }.map { line.points[$0] }
            return [point(at: start)] + inside + [point(at: end)]
        }
        var drawn: [[RealRailways.Coordinate]] = []
        var from = 0.0
        for stretch in stretches {
            if let piece = piece(from: from, to: stretch.lowerBound) { drawn.append(piece) }
            from = stretch.upperBound
        }
        if let piece = piece(from: from, to: total) { drawn.append(piece) }
        return drawn
    }

    /// The operation lines most of whose stations on the map are the
    /// player's: a station of the player's with the same name within the
    /// station card's reach (``RealRailways/stations(named:near:)``).
    private static func quietLines(of operations: RealRailwayOperations, railways: RealRailways, world: GameWorld, frame: RealWorldFrame) -> Set<String> {
        guard !world.stations.isEmpty else { return [] }
        let reach = railways.transfers?.maximumDistanceMetres ?? 450
        // The real stations the player's stations are.
        var taken: [(key: String, at: RealRailways.Coordinate)] = []
        for station in world.stations {
            let place = frame.coordinate(worldX: Double(station.location.x), worldY: Double(station.location.y))
            for real in railways.stations(named: station.name, near: RealRailways.Coordinate(latitude: place.latitude, longitude: place.longitude)) {
                taken.append((RealRailways.stationKey(real.chinese), real.coordinate))
            }
        }
        guard !taken.isEmpty else { return [] }
        let region = WorldRegion(bounds: world.bounds)
        var quiet: Set<String> = []
        for system in operations.orderedSystems {
            for line in system.lines {
                var onMap = 0, mine = 0
                for station in line.stations {
                    let point = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
                    guard point.x >= region.minX, point.x <= region.maxX, point.y >= region.minY, point.y <= region.maxY else { continue }
                    onMap += 1
                    let key = RealRailways.stationKey(station.name)
                    let at = RealRailways.Coordinate(latitude: station.latitude, longitude: station.longitude)
                    if taken.contains(where: { $0.key == key && RealStationTransfers.distanceMetres($0.at, at) < reach }) { mine += 1 }
                }
                if onMap >= 2, Double(mine) > Double(onMap) * quietShare { quiet.insert("\(system.id):\(line.id)") }
            }
        }
        return quiet
    }

    /// The pieces of `line` drawn: the whole of it, or what the player's
    /// track leaves.
    public func drawnPieces(of line: RealRailways.Line) -> [[RealRailways.Coordinate]] {
        pieces[line.id] ?? [line.points]
    }

    /// Whether a real train at (`x`, `y`) heading (`headingX`, `headingY`),
    /// in world units, is on a stretch the player's track covers.
    public func hidesTrain(_ dot: RealTrainDot) -> Bool {
        guard !covered.isEmpty else { return false }
        let length = (dot.headingX * dot.headingX + dot.headingY * dot.headingY).squareRoot()
        guard length > 0 else { return false }
        return Self.near(dot.x, dot.y, way: dot.headingX / length, dot.headingY / length, in: covered, reach: 2 * Self.reach)
    }
}
