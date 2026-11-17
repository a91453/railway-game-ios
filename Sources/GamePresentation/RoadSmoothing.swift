import Foundation
import GameCore

// Decision 821 (ROAD-SMOOTH): the player's roads are still kept as 64 m
// cells (decision 487), but a road dragged at a slant is a staircase of
// cells, and joining their middles drew it zigzagging. Each run of cells
// from an end or a fork to the next is drawn instead as the tightest line
// that stays inside its own cells (the shortest path through the cells,
// worked out as a navigation mesh's "funnel" does: Lee and Preparata's
// algorithm, in the simple form Mikko Mononen described for Recast), and
// then its bends are rounded. Ends and forks stay at their cells' middles,
// so roads, joins and bus routes still meet there.

extension RoadCentreLines {
    /// How close to its cells' edges the road's middle goes, and how far
    /// past a corner it may cut where the road goes corner to corner: 4 m,
    /// about half the road's width (the 3D map's lane is 5 m). The road
    /// drawn corner to corner already crossed that corner as wide.
    static let edge = 4 * Double(WorldCoordinate.unitsPerMetre)

    /// How near a corner the finger's line passes for the road drawn to go
    /// corner to corner there (``RoadDraft/extend(from:to:)``): 3.5 m, a
    /// little inside ``edge``, so that a straight drag is drawn dead
    /// straight.
    static let cornerReach = 3.5 * Double(WorldCoordinate.unitsPerMetre)

    /// How close to the end of the side two cells share the road's middle
    /// may cross it: 2 m, so it does not graze the corner of a cell beside.
    /// A straight drag crosses farther from it (it goes corner to corner
    /// within ``cornerReach``), but at under 6° where two corners are both
    /// that near.
    static let sideRoom = 2 * Double(WorldCoordinate.unitsPerMetre)

    /// How many cells in a line each side of a turn keep it a street
    /// corner, at the cell's middle (rounded a quarter cell), and not a
    /// cut across: three, 192 m. A slanting road's staircase has a single
    /// step one way between longer runs, so it is never cut there.
    static let cornerRun = 3

    /// The line that `chain` (cells each beside the last) is drawn as: from
    /// the first cell's middle to the last's, staying in its own cells.
    static func smoothed(_ chain: [CellPosition]) -> [PlanPoint] {
        guard chain.count >= 2 else { return chain.map(\.middle) }
        let room = Corridor(chain)
        // A turn between two long straight runs stays a corner at the middle.
        var steps: [(Int, Int)] = []
        for (a, b) in zip(chain, chain.dropFirst()) { steps.append((b.row - a.row, b.column - a.column)) }
        var pieces: [[CellPosition]] = []
        var start = 0
        var index = 1
        while index < chain.count - 1 {
            if steps[index - 1] != steps[index] {
                var before = 0, after = 0
                while index - 1 - before >= 0, steps[index - 1 - before] == steps[index - 1] { before += 1 }
                while index + after < steps.count, steps[index + after] == steps[index] { after += 1 }
                if before >= cornerRun, after >= cornerRun {
                    pieces.append(Array(chain[start...index]))
                    start = index
                }
            }
            index += 1
        }
        pieces.append(Array(chain[start...]))
        var points: [Point] = []
        for piece in pieces {
            let path = funnel(piece)
            points += points.isEmpty ? path : Array(path.dropFirst())
        }
        return finished(rounded(points, in: room))
    }

    /// A plan point in floating point.
    struct Point: Equatable {
        var x: Double
        var y: Double

        init(_ x: Double, _ y: Double) {
            self.x = x
            self.y = y
        }

        init(_ point: PlanPoint) {
            self.init(Double(point.x), Double(point.y))
        }

        static func + (a: Point, b: Point) -> Point { Point(a.x + b.x, a.y + b.y) }
        static func - (a: Point, b: Point) -> Point { Point(a.x - b.x, a.y - b.y) }
        static func * (a: Point, k: Double) -> Point { Point(a.x * k, a.y * k) }
        var length: Double { (x * x + y * y).squareRoot() }
        func cross(_ b: Point) -> Double { x * b.y - y * b.x }
        func dot(_ b: Point) -> Double { x * b.x + y * b.y }
    }

    /// The cells a road runs through, and the corners where it goes corner
    /// to corner, for asking whether a point of its line is in them.
    struct Corridor {
        let cells: Set<CellPosition>
        /// The corners between two cells joined corner to corner.
        let pinches: [Point]
        /// The cells beside those two, not in the road, whose corner the
        /// road may cut.
        let beside: Set<CellPosition>

        init(_ chain: [CellPosition]) {
            cells = Set(chain)
            var pinches: [Point] = [], beside = Set<CellPosition>()
            let side = Double(Land.cellLength)
            for (a, b) in zip(chain, chain.dropFirst()) where a.row != b.row && a.column != b.column {
                pinches.append(Point(Double(max(a.column, b.column)) * side, Double(max(a.row, b.row)) * side))
                beside.insert(CellPosition(row: a.row, column: b.column))
                beside.insert(CellPosition(row: b.row, column: a.column))
            }
            self.pinches = pinches
            self.beside = beside.subtracting(cells)
        }

        /// How far `point` is outside the cells (0 inside), looking at the
        /// cells round it.
        func outside(_ point: Point) -> Double {
            let cell = Corridor.cell(of: point)
            if cells.contains(cell) { return 0 }
            var nearest = Double.infinity
            for dr in -1...1 {
                for dc in -1...1 where cells.contains(CellPosition(row: cell.row + dr, column: cell.column + dc)) {
                    nearest = min(nearest, Corridor.distance(from: point, to: CellPosition(row: cell.row + dr, column: cell.column + dc)))
                }
            }
            return nearest
        }

        /// How far `point`, in the cells, is from the cells round it that
        /// are not.
        func clearance(_ point: Point) -> Double {
            let cell = Corridor.cell(of: point)
            var nearest = Double.infinity
            for dr in -1...1 {
                for dc in -1...1 {
                    let near = CellPosition(row: cell.row + dr, column: cell.column + dc)
                    if !cells.contains(near) { nearest = min(nearest, Corridor.distance(from: point, to: near)) }
                }
            }
            return nearest
        }

        /// Whether a rounded corner's `point` may be drawn: in the cells and
        /// clear of their edges, or near a corner the road goes corner to
        /// corner through, at most ``RoadCentreLines/edge`` past it.
        func admits(_ point: Point) -> Bool {
            let out = outside(point)
            if out > 0 { return out <= RoadCentreLines.edge && beside.contains(Corridor.cell(of: point)) }
            return clearance(point) >= RoadCentreLines.edge / 2 || pinches.contains { ($0 - point).length <= 3 * RoadCentreLines.edge }
        }

        static func cell(of point: Point) -> CellPosition {
            let side = Double(Land.cellLength)
            return CellPosition(row: Int((point.y / side).rounded(.down)), column: Int((point.x / side).rounded(.down)))
        }

        static func distance(from point: Point, to cell: CellPosition) -> Double {
            let side = Double(Land.cellLength)
            let left = Double(cell.column) * side, top = Double(cell.row) * side
            let dx = max(left - point.x, 0, point.x - (left + side)), dy = max(top - point.y, 0, point.y - (top + side))
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// The shortest line through `chain`'s cells from the first's middle to
    /// the last's. Each step from a cell to the next passes a portal: the
    /// side they share, ``sideRoom`` short of each end, or, corner to
    /// corner, across their corner, as far as ``edge`` into the cells
    /// beside. Where the line has to bend round the end
    /// of a side, it bends
    /// ``bendRoom`` from it, leaving room to round the bend; where it has to
    /// bend at a corner it goes corner to corner through, at the corner
    /// itself, so it does not run on along the outside of the cells. A
    /// straight line bends at neither, and stays as it is.
    static func funnel(_ chain: [CellPosition]) -> [Point] {
        var pulled: Set<Int> = []
        var (path, bends) = funnel(chain, pulled: pulled)
        for _ in 0..<(2 * chain.count) {
            let more = pulled.union(bends)
            guard more != pulled else { break }
            pulled = more
            (path, bends) = funnel(chain, pulled: pulled)
        }
        return path
    }

    /// How far from the end of a side the line bends round it: 12 m.
    static let bendRoom = 12 * Double(WorldCoordinate.unitsPerMetre)

    /// ``funnel(_:)`` with the portal ends in `pulled` (step × 2, and 1
    /// for the right) drawn in: a side's to ``bendRoom``, a corner's to the
    /// corner. Gives the line, and the portal ends it bends at.
    static func funnel(_ chain: [CellPosition], pulled: Set<Int>) -> (path: [Point], bends: Set<Int>) {
        let start = Point(chain[0].middle), end = Point(chain[chain.count - 1].middle)
        let side = Double(Land.cellLength)
        // Each portal, left and right of the way on (where the cross
        // product is positive), with the end each is (step × 2 + side).
        var portals: [(left: Point, right: Point, leftEnd: Int?, rightEnd: Int?)] = [(start, start, nil, nil)]
        for (step, (a, b)) in zip(chain, chain.dropFirst()).enumerated() {
            let from = Point(a.middle), to = Point(b.middle), way = to - from
            let leftEnd = 2 * step, rightEnd = 2 * step + 1
            let leftHand = Point(-way.y, way.x) * (1 / way.length)
            var left: Point, right: Point
            if a.row != b.row, a.column != b.column {
                let corner = Point(Double(max(a.column, b.column)) * side, Double(max(a.row, b.row)) * side)
                // Every line within `edge` of the corner crosses it, and is
                // at most `edge` into the cell beside.
                let reach = edge * 2.squareRoot()
                left = corner + leftHand * (pulled.contains(leftEnd) ? 0 : reach)
                right = corner - leftHand * (pulled.contains(rightEnd) ? 0 : reach)
            } else {
                let middle = (from + to) * 0.5, half = side / 2
                left = middle + leftHand * (half - (pulled.contains(leftEnd) ? bendRoom : sideRoom))
                right = middle - leftHand * (half - (pulled.contains(rightEnd) ? bendRoom : sideRoom))
            }
            portals.append((left, right, leftEnd, rightEnd))
        }
        portals.append((end, end, nil, nil))

        var path = [start]
        var bendsAt: [(index: Int, end: Int)] = []
        var apex = start, left = start, right = start
        var apexIndex = 0, leftIndex = 0, rightIndex = 0
        var index = 1
        func bend(at point: Point, portal: Int, end: Int?) {
            if path.last != point { path.append(point) }
            if let end { bendsAt.append((path.count - 1, end)) }
            apex = point
            apexIndex = portal
            left = apex
            right = apex
            leftIndex = apexIndex
            rightIndex = apexIndex
            index = apexIndex + 1
        }
        while index < portals.count {
            let portal = portals[index]
            // Narrow the right side.
            if (right - apex).cross(portal.right - apex) >= 0 {
                if apex == right || (left - apex).cross(portal.right - apex) < 0 {
                    right = portal.right
                    rightIndex = index
                } else {
                    // Past the left side: the left becomes a bend.
                    bend(at: left, portal: leftIndex, end: portals[leftIndex].leftEnd)
                    continue
                }
            }
            // Narrow the left side.
            if (left - apex).cross(portal.left - apex) <= 0 {
                if apex == left || (right - apex).cross(portal.left - apex) > 0 {
                    left = portal.left
                    leftIndex = index
                } else {
                    bend(at: right, portal: rightIndex, end: portals[rightIndex].rightEnd)
                    continue
                }
            }
            index += 1
        }
        if path.last != end { path.append(end) }
        // Only where the line turns: one that grazes an end goes on straight.
        var bends: Set<Int> = []
        for (at, end) in bendsAt where at > 0 && at < path.count - 1 {
            let inWay = path[at] - path[at - 1], outWay = path[at + 1] - path[at]
            if abs(inWay.cross(outWay)) > 1e-4 * inWay.length * outWay.length { bends.insert(end) }
        }
        return (path, bends)
    }

    /// `points` with each bend rounded, a quadratic curve with the bend as
    /// its control: from ``cornerCut`` (16 m) before a sharp turn to up to
    /// a cell before a slight one, never past half of either side, and cut
    /// back while the curve would leave ``Corridor``.
    static func rounded(_ points: [Point], in room: Corridor) -> [Point] {
        guard points.count >= 3 else { return points }
        var out = [points[0]]
        for index in 1..<(points.count - 1) {
            let a = points[index - 1], b = points[index], c = points[index + 1]
            let inWay = b - a, outWay = c - b
            let inLength = inWay.length, outLength = outWay.length
            guard inLength > 0, outLength > 0 else { continue }
            let turn = abs(atan2(inWay.cross(outWay), inWay.dot(outWay)))
            guard turn > 1e-6 else {
                out.append(b)
                continue
            }
            let side = Double(Land.cellLength)
            let sharp = Double.pi / 3
            var cut = turn >= sharp ? cornerCut : cornerCut + (side - cornerCut) * (1 - turn / sharp)
            cut = min(cut, inLength / 2, outLength / 2)
            var curve: [Point] = [b]
            while cut >= Double(WorldCoordinate.unitsPerMetre) / 2 {
                let from = b - inWay * (cut / inLength), to = b + outWay * (cut / outLength)
                let steps = max(4, Int((turn / (Double.pi / 16)).rounded(.up)))
                let trial = (0...steps).map { step -> Point in
                    let t = Double(step) / Double(steps), u = 1 - t
                    return from * (u * u) + b * (2 * u * t) + to * (t * t)
                }
                // Along each piece drawn, not only at its ends.
                let drawn = zip(trial, trial.dropFirst()).allSatisfy { a, b in
                    (0...4).allSatisfy { room.admits(a + (b - a) * (Double($0) / 4)) }
                }
                if drawn {
                    curve = trial
                    break
                }
                cut /= 2
            }
            out += curve
        }
        out.append(points[points.count - 1])
        return out
    }

    /// `points` as plan points, each straight stretch longer than a cell
    /// split evenly, at most a cell apart (so the 3D map lays it over the
    /// ground's rises as before), and repeats left out.
    static func finished(_ points: [Point]) -> [PlanPoint] {
        func plan(_ p: Point) -> PlanPoint { PlanPoint(x: Int64(p.x.rounded()), y: Int64(p.y.rounded())) }
        guard let first = points.first else { return [] }
        var out = [plan(first)]
        let side = Double(Land.cellLength)
        for (a, b) in zip(points, points.dropFirst()) {
            let pieces = max(1, Int(((b - a).length / side - 1e-6).rounded(.up)))
            for piece in 1...pieces {
                let point = plan(a + (b - a) * (Double(piece) / Double(pieces)))
                if point != out[out.count - 1] { out.append(point) }
            }
        }
        return out
    }
}
