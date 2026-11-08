import Foundation

// Decision 631 (author's screenshot review, 2026-11-07): the tracks'
// numbers ("#14") covered the switches and the stations' names beside
// them. Each number now picks a place along its track where its plate
// covers neither a switch, a name nor a number already placed; when the
// middle will not do it tries other places along the track, then a
// smaller plate, and when none is free it is left out.
//
// Decision 642 (the author's Mac screenshots of #1941, 2026-11-08): the
// names were kept clear but "#1" still sat on a station's badge and its
// waiting count, and "#11" on the point where two tracks cross. A number
// now keeps clear of the stations' badges (and the crowded ring round
// them), the waiting count's pill above each, and the points where two
// tracks cross on the screen, each with room round it.

/// Where the tracks' numbers stand on the map, in screen points. Pure
/// geometry, so the placement is tested on Linux; the map measures the
/// plates and draws them.
public enum TrackNumberPlacement {
    /// A box on the screen.
    public struct Box: Equatable, Sendable {
        public var minX: Double
        public var minY: Double
        public var maxX: Double
        public var maxY: Double

        public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
            self.minX = minX
            self.minY = minY
            self.maxX = maxX
            self.maxY = maxY
        }

        public init(center: ScreenPoint, width: Double, height: Double) {
            self.init(minX: center.x - width / 2, minY: center.y - height / 2,
                      maxX: center.x + width / 2, maxY: center.y + height / 2)
        }

        /// Whether the two share any area (boxes that only touch do not).
        public func intersects(_ other: Box) -> Bool {
            minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
        }
    }

    /// A number to place.
    public struct Candidate: Equatable, Sendable {
        public let id: Int
        /// The places it may stand, the best first.
        public let positions: [ScreenPoint]
        /// The plate's size at full scale.
        public let width: Double
        public let height: Double

        public init(id: Int, positions: [ScreenPoint], width: Double, height: Double) {
            self.id = id
            self.positions = positions
            self.width = width
            self.height = height
        }
    }

    public struct Placed: Equatable, Sendable {
        public let id: Int
        public let center: ScreenPoint
        /// 1 for the full plate, less for a smaller one.
        public let scale: Double
        public let box: Box
    }

    /// The sizes a plate may take, the largest first. Under the least a
    /// number would not be readable, so it is left out.
    public static let scales: [Double] = [1, 0.8, 0.65]

    /// Where along a track of `points` a number may stand, as fractions of
    /// its length: the middle, then either side of it.
    public static let fractions: [Double] = [0.5, 0.35, 0.65, 0.22, 0.78]

    /// The places along `points`, `beside` points to the left of the track
    /// (the middle first), for a number; none for a track of no length.
    public static func positions(along points: [ScreenPoint], beside: Double) -> [ScreenPoint] {
        let length = PolylineMarks.length(of: points)
        guard length > 0 else { return [] }
        return fractions.compactMap { fraction in
            PolylineMarks.mark(along: points, at: length * fraction).map {
                PolylineMarks.shifted($0, by: beside).point
            }
        }
    }

    /// What a switch keeps clear: a square `radius` points round the
    /// node.
    public static func switchBox(at point: ScreenPoint, radius: Double) -> Box {
        Box(center: point, width: radius * 2, height: radius * 2)
    }

    /// How far a number keeps from a switch or a crossing, in points: the
    /// half side of the square kept clear round it (decision 642; 12 in
    /// decision 631 let a plate's edge touch the crossing tracks).
    public static let junctionClearance: Double = 16

    /// What a station's badge keeps clear: a square round the widest ring
    /// drawn round it (the crowded ring and its halo,
    /// ``MapProblems/ringRadius(stationRadius:)``), so a number never sits
    /// on the badge whether the station is crowded or not.
    public static func stationBox(at station: ScreenPoint, stationRadius: Double) -> Box {
        let reach = MapProblems.ringRadius(stationRadius: stationRadius) + MapProblems.ringHaloReach
        return Box(center: station, width: reach * 2, height: reach * 2)
    }

    /// What a station's waiting count keeps clear: the pill above the
    /// badge where ``MapProblems`` draws it, as wide as a count of
    /// `characters` characters ("1,234" is five) in a bold face of
    /// `fontSize`, set where it stands over a crowded ring (the higher of
    /// its two places), down to the badge. The map's canvas of numbers is
    /// not redrawn as people come and go, so every station keeps this
    /// room, whether a pill is drawn there now or not.
    public static func waitingBox(
        at station: ScreenPoint, stationRadius: Double, fontSize: Double, characters: Int = 5
    ) -> Box {
        let icon = fontSize + 1
        let height = max(fontSize * 1.2 + 3, icon + 4)
        let width = 3 + icon + 1.5 + Double(characters) * fontSize * 0.62 + 4
        let top = MapProblems.ringRadius(stationRadius: stationRadius) + 1.5
        let centerY = station.y - top - height / 2 - 3
        return Box(minX: station.x - width / 2, minY: centerY - height / 2,
                   maxX: station.x + width / 2, maxY: station.y)
    }

    /// The points where two of `tracks` (each a polyline on the screen)
    /// cross inside `view`, where neither ends: the tracks that meet at a
    /// node are not crossings (the switches are kept clear by
    /// ``switchBox(at:radius:)``). Segments are binned in a grid of
    /// `cell` points so only near ones are compared.
    public static func crossings(of tracks: [[ScreenPoint]], in view: Box, cell: Double = 48) -> [ScreenPoint] {
        struct Segment { let track: Int; let a: ScreenPoint; let b: ScreenPoint }
        var segments: [Segment] = []
        var cells: [Int64: [Int]] = [:]
        func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) &* 1_000_003 &+ Int64(y) }
        for (track, points) in tracks.enumerated() where points.count >= 2 {
            for index in 1..<points.count {
                let a = points[index - 1], b = points[index]
                let box = Box(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y))
                guard box.maxX >= view.minX, box.minX <= view.maxX, box.maxY >= view.minY, box.minY <= view.maxY else { continue }
                let id = segments.count
                segments.append(Segment(track: track, a: a, b: b))
                let x0 = Int((max(box.minX, view.minX) / cell).rounded(.down))
                let x1 = Int((min(box.maxX, view.maxX) / cell).rounded(.down))
                let y0 = Int((max(box.minY, view.minY) / cell).rounded(.down))
                let y1 = Int((min(box.maxY, view.maxY) / cell).rounded(.down))
                for x in x0...x1 { for y in y0...y1 { cells[key(x, y), default: []].append(id) } }
            }
        }
        var seen = Set<Int64>()
        var found: [ScreenPoint] = []
        for ids in cells.values where ids.count >= 2 {
            for i in 0..<(ids.count - 1) {
                for j in (i + 1)..<ids.count {
                    let s = segments[ids[i]], t = segments[ids[j]]
                    guard s.track != t.track else { continue }
                    let pair = Int64(min(ids[i], ids[j])) &* 4_294_967_296 &+ Int64(max(ids[i], ids[j]))
                    guard seen.insert(pair).inserted,
                          let point = crossing(s.a, s.b, t.a, t.b),
                          point.x >= view.minX, point.x <= view.maxX, point.y >= view.minY, point.y <= view.maxY
                    else { continue }
                    found.append(point)
                }
            }
        }
        return found.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    /// Where segment `a`–`b` crosses `c`–`d` strictly inside both (not at
    /// an end, where two tracks meet at a node); none for parallel ones.
    static func crossing(_ a: ScreenPoint, _ b: ScreenPoint, _ c: ScreenPoint, _ d: ScreenPoint) -> ScreenPoint? {
        let rx = b.x - a.x, ry = b.y - a.y, sx = d.x - c.x, sy = d.y - c.y
        let denominator = rx * sy - ry * sx
        guard abs(denominator) > 1e-9 else { return nil }
        let qx = c.x - a.x, qy = c.y - a.y
        let t = (qx * sy - qy * sx) / denominator
        let u = (qx * ry - qy * rx) / denominator
        let end = 1e-6
        guard t > end, t < 1 - end, u > end, u < 1 - end else { return nil }
        return ScreenPoint(x: a.x + t * rx, y: a.y + t * ry)
    }

    /// What a station keeps clear: its name's plate, `nameTop` points
    /// below the station, `nameWidth` wide and `height` tall (the badges
    /// of its lines and the shops' squares included).
    public static func nameBox(station: ScreenPoint, nameTop: Double, nameWidth: Double, height: Double) -> Box {
        Box(minX: station.x - nameWidth / 2, minY: station.y + nameTop,
            maxX: station.x + nameWidth / 2, maxY: station.y + nameTop + height)
    }

    /// Places `candidates` in order (the ones that matter most first),
    /// each at the first of its positions, at the largest scale, where its
    /// plate (with `margin` round it) lies in `view` and covers none of
    /// `obstacles` and none placed before, `taken` included. At most
    /// `limit` in all.
    public static func place(
        _ candidates: [Candidate], obstacles: [Box], taken: [Box] = [], view: Box, limit: Int, margin: Double = 2
    ) -> [Placed] {
        var blocked = obstacles + taken
        var placed: [Placed] = []
        for candidate in candidates {
            guard placed.count < limit else { break }
            if let found = fit(candidate, blocked: blocked, view: view, margin: margin) {
                blocked.append(found.box)
                placed.append(found)
            }
        }
        return placed
    }

    static func fit(_ candidate: Candidate, blocked: [Box], view: Box, margin: Double) -> Placed? {
        for scale in scales {
            for position in candidate.positions {
                let box = Box(center: position, width: candidate.width * scale + 2 * margin,
                              height: candidate.height * scale + 2 * margin)
                guard box.intersects(view), !blocked.contains(where: { $0.intersects(box) }) else { continue }
                return Placed(id: candidate.id, center: position, scale: scale, box: box)
            }
        }
        return nil
    }
}
