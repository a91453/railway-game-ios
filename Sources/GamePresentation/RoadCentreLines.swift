import Foundation
import GameCore

// Decision 476: the player's roads drawn as the base map's streets are, one
// line through the middles of their cells with its corners rounded, not a
// block a cell. The same lines draw the road being dragged (faint), the
// road laid, and the 3D map's road, so what the finger draws is what gets
// built.

/// The lines a set of road cells is drawn as (decision 476).
public enum RoadCentreLines {
    /// Each road through the middles of `cells`: two cells side by side are
    /// joined, and two corner to corner only when neither cell beside both
    /// is in `cells` (else the road turns through that cell, and a third
    /// side would make a triangle). With `touching`, only the joins with an
    /// end in it, and its cells joined to nothing as a single point. Each
    /// line runs from an end or a fork to the next; the corners rounded
    /// (``rounded(_:)``).
    public static func lines(of cells: Set<CellPosition>, touching: Set<CellPosition>? = nil) -> [[PlanPoint]] {
        let joined = joins(of: cells, touching: touching)
        struct Join: Hashable { let a: CellPosition, b: CellPosition }
        func join(_ a: CellPosition, _ b: CellPosition) -> Join { a < b ? Join(a: a, b: b) : Join(a: b, b: a) }
        var walked: Set<Join> = []
        var chains: [[CellPosition]] = []
        func walk(from start: CellPosition, to first: CellPosition) {
            guard walked.insert(join(start, first)).inserted else { return }
            var chain = [start, first], previous = start, at = first
            while let near = joined[at], near.count == 2 {
                let next = near[0] == previous ? near[1] : near[0]
                guard walked.insert(join(at, next)).inserted else { break }
                chain.append(next)
                previous = at
                at = next
            }
            chains.append(chain)
        }
        let ordered = joined.keys.sorted()
        // From the ends and forks first, then round the loops left.
        for cell in ordered where joined[cell]?.count != 2 {
            for near in joined[cell] ?? [] { walk(from: cell, to: near) }
        }
        for cell in ordered {
            for near in joined[cell] ?? [] { walk(from: cell, to: near) }
        }
        var lines = chains.map { rounded($0.map(\.middle)) }
        for cell in (touching ?? cells).sorted() where cells.contains(cell) && joined[cell] == nil {
            lines.append([cell.middle])
        }
        return lines
    }

    /// Each cell of `cells` and the cells it is joined to (``lines(of:touching:)``'s
    /// rule).
    static func joins(of cells: Set<CellPosition>, touching: Set<CellPosition>? = nil) -> [CellPosition: [CellPosition]] {
        var joined: [CellPosition: [CellPosition]] = [:]
        for cell in cells.sorted() {
            for (dr, dc) in [(0, 1), (1, -1), (1, 0), (1, 1)] {
                let near = CellPosition(row: cell.row + dr, column: cell.column + dc)
                guard cells.contains(near) else { continue }
                if dr != 0, dc != 0 {
                    guard !cells.contains(CellPosition(row: cell.row + dr, column: cell.column)),
                          !cells.contains(CellPosition(row: cell.row, column: cell.column + dc)) else { continue }
                }
                if let touching, !touching.contains(cell), !touching.contains(near) { continue }
                joined[cell, default: []].append(near)
                joined[near, default: []].append(cell)
            }
        }
        return joined
    }

    /// The middles of the cells of `cells` where a road ends: joined to one
    /// other cell or to none (476's sequel: where a player's road meets the
    /// city's).
    static func ends(of cells: Set<CellPosition>) -> [PlanPoint] {
        let joined = joins(of: cells)
        return cells.sorted().filter { (joined[$0]?.count ?? 0) <= 1 }.map(\.middle)
    }

    /// How far before a corner the road starts to turn: a quarter of a
    /// cell (16 m), as a street corner, not the whole block.
    static let cornerCut = Double(Land.cellLength) / 4

    /// `points` with each corner rounded: the line leaves the straight
    /// ``cornerCut`` (or half the shorter side) before the corner and
    /// curves round it, a quadratic curve with the corner as its control.
    static func rounded(_ points: [PlanPoint]) -> [PlanPoint] {
        guard points.count >= 3 else { return points }
        func point(_ p: PlanPoint) -> (x: Double, y: Double) { (Double(p.x), Double(p.y)) }
        func plan(_ x: Double, _ y: Double) -> PlanPoint { PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())) }
        var out = [points[0]]
        for index in 1..<(points.count - 1) {
            let a = point(points[index - 1]), b = point(points[index]), c = point(points[index + 1])
            let inX = b.x - a.x, inY = b.y - a.y, outX = c.x - b.x, outY = c.y - b.y
            let inLength = (inX * inX + inY * inY).squareRoot(), outLength = (outX * outX + outY * outY).squareRoot()
            // Straight on: no corner.
            guard inLength > 0, outLength > 0, abs(inX * outY - inY * outX) > 1e-9 * inLength * outLength else {
                out.append(points[index])
                continue
            }
            let cut = min(cornerCut, inLength / 2, outLength / 2)
            let start = (x: b.x - inX / inLength * cut, y: b.y - inY / inLength * cut)
            let end = (x: b.x + outX / outLength * cut, y: b.y + outY / outLength * cut)
            let steps = 4
            for step in 0...steps {
                let t = Double(step) / Double(steps), u = 1 - t
                out.append(plan(u * u * start.x + 2 * u * t * b.x + t * t * end.x, u * u * start.y + 2 * u * t * b.y + t * t * end.y))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    /// The base map's width of a lane (`minor`), in points, at map `zoom`
    /// (``BaseMapStyle``'s road widths), never under a point: the player's
    /// road is drawn as wide as the streets around it.
    public static func width(zoom: Double, casing: Bool = false) -> Double {
        let lane = BaseMapStyle.roadWidth(of: "minor", zoom: zoom)
        return max(1, lane) + (casing ? 1.5 : 0)
    }
}
