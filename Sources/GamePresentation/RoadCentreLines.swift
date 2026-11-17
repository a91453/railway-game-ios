import Foundation
import GameCore

// Decision 476: the player's roads drawn as the base map's streets are, one
// line through the middles of their cells with its corners rounded, not a
// block a cell. The same lines draw the road being dragged (faint), the
// road laid, and the 3D map's road, so what the finger draws is what gets
// built. Decision 821: each line is the straightest one inside its cells
// (RoadSmoothing.swift), not a zigzag through their middles.

/// The lines a set of road cells is drawn as (decision 476).
public enum RoadCentreLines {
    /// Each road through `cells`: two cells side by side are joined, and
    /// two corner to corner only when neither cell beside both is in
    /// `cells` (else the road turns through that cell, and a third side
    /// would make a triangle). Each line runs from an end or a fork to the
    /// next, from the one cell's middle to the other's, and is drawn as the
    /// straightest line inside its own cells with its bends rounded
    /// (decision 821, ``smoothed(_:)``). With `touching`, only the lines
    /// through a cell of it, whole (so the road being drawn is drawn as it
    /// will be laid), and its cells joined to nothing as a single point.
    public static func lines(of cells: Set<CellPosition>, touching: Set<CellPosition>? = nil) -> [[PlanPoint]] {
        var known: [CellPosition: [CellPosition]] = [:]
        func near(_ cell: CellPosition) -> [CellPosition] {
            if let found = known[cell] { return found }
            let found = neighbours(of: cell, in: cells)
            known[cell] = found
            return found
        }
        struct Join: Hashable { let a: CellPosition, b: CellPosition }
        func join(_ a: CellPosition, _ b: CellPosition) -> Join { a < b ? Join(a: a, b: b) : Join(a: b, b: a) }
        var walked: Set<Join> = []
        // The cells from `start` on through `first` to the next end or fork
        // (or round to `start` again).
        func walk(from start: CellPosition, to first: CellPosition) -> [CellPosition] {
            var chain = [start, first], previous = start, at = first
            walked.insert(join(start, first))
            while at != start {
                let next = near(at)
                guard next.count == 2 else { break }
                let on = next[0] == previous ? next[1] : next[0]
                guard walked.insert(join(at, on)).inserted else { break }
                chain.append(on)
                previous = at
                at = on
            }
            return chain
        }
        var chains: [[CellPosition]] = []
        if let touching {
            for cell in touching.sorted() where cells.contains(cell) {
                for first in near(cell) where !walked.contains(join(cell, first)) {
                    // Back along the other way to where the line begins.
                    var chain = walk(from: cell, to: first)
                    if chain.last != cell, near(cell).count == 2, let other = near(cell).first(where: { $0 != first }),
                       !walked.contains(join(cell, other)) {
                        chain = walk(from: cell, to: other).reversed() + chain.dropFirst()
                    }
                    chains.append(chain)
                }
            }
        } else {
            let ordered = cells.sorted()
            // From the ends and forks first, then round the loops left.
            for cell in ordered where near(cell).count != 2 {
                for first in near(cell) where !walked.contains(join(cell, first)) { chains.append(walk(from: cell, to: first)) }
            }
            for cell in ordered {
                for first in near(cell) where !walked.contains(join(cell, first)) { chains.append(walk(from: cell, to: first)) }
            }
        }
        // The same cells draw the same line whichever end they are walked
        // from: the lower end first, and a ring with no fork from its
        // lowest cell.
        func canonical(_ chain: [CellPosition]) -> [CellPosition] {
            guard chain.first == chain.last, chain.count > 2 else { return chain.last! < chain.first! ? chain.reversed() : chain }
            var ring = Array(chain.dropLast())
            if near(ring[0]).count == 2, let lowest = ring.indices.min(by: { ring[$0] < ring[$1] }) {
                ring = Array(ring[lowest...] + ring[..<lowest])
            }
            if ring.count > 2, ring[ring.count - 1] < ring[1] { ring = [ring[0]] + ring.dropFirst().reversed() }
            return ring + [ring[0]]
        }
        var lines = chains.map { smoothed(canonical($0)) }
        for cell in (touching ?? cells).sorted() where cells.contains(cell) && near(cell).isEmpty {
            lines.append([cell.middle])
        }
        return lines
    }

    /// The cells of `cells` that `cell` is joined to (``lines(of:touching:)``'s
    /// rule), lowest first.
    static func neighbours(of cell: CellPosition, in cells: Set<CellPosition>) -> [CellPosition] {
        var found: [CellPosition] = []
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let near = CellPosition(row: cell.row + dr, column: cell.column + dc)
                guard cells.contains(near) else { continue }
                if dr != 0, dc != 0 {
                    guard !cells.contains(CellPosition(row: cell.row + dr, column: cell.column)),
                          !cells.contains(CellPosition(row: cell.row, column: cell.column + dc)) else { continue }
                }
                found.append(near)
            }
        }
        return found
    }

    /// Each cell of `cells` and the cells it is joined to (``lines(of:touching:)``'s
    /// rule).
    static func joins(of cells: Set<CellPosition>) -> [CellPosition: [CellPosition]] {
        var joined: [CellPosition: [CellPosition]] = [:]
        for cell in cells {
            let near = neighbours(of: cell, in: cells)
            if !near.isEmpty { joined[cell] = near }
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

    /// How far before a sharp corner the road starts to turn: a quarter of
    /// a cell (16 m), as a street corner, not the whole block (slighter
    /// bends turn wider, ``rounded(_:in:)``).
    static let cornerCut = Double(Land.cellLength) / 4

    /// The base map's width of a lane (`minor`), in points, at map `zoom`
    /// (``BaseMapStyle``'s road widths), never under a point: the player's
    /// road is drawn as wide as the streets around it.
    public static func width(zoom: Double, casing: Bool = false) -> Double {
        let lane = BaseMapStyle.roadWidth(of: "minor", zoom: zoom)
        return max(1, lane) + (casing ? 1.5 : 0)
    }
}
