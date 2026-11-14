import Foundation
import GameCore

// Decision 737 (ROAD-FLATTEN; the owner, 2026-11-14: 「道路凹凸不平 可以跟
// 收購路線那種邏輯 差不多盡量鋪平嗎」): on a real-world map the 3D map's
// ground is levelled before anything is laid on it. The world's ground is
// the Copernicus surface model on 64 m corners in whole metres (decision
// 124), which counts the city's buildings and trees as ground: through flat
// central Taipei a main road rose and fell five times a kilometre at up to
// 5% (`docs/decisions/737.md`), and as the roads, their paint, the street
// furniture and the buildings all stand on the drawn ground, all of them
// rose and fell with it.
//
// As a bought line's track is laid (``TrackRise``, decision 132: the
// ground's mean over 160 m either way), each drawn corner is the Gaussian
// mean of the corners within ``Map3DLevelledGround/radius`` cells (some
// 130 m each way), moved at most ``Map3DLevelledGround/reach`` from the
// world's: a plane is left as it is, so a hillside keeps its slope, and a
// ridge or a valley floor moves at most that far. The corners the world's
// own ground must stay under are not moved: those of a cell the player's
// track runs through (its heights are the world's, decision 124), of a
// water cell (its surface is level, decision 132), and those near the
// world's edge, where the mean would lean.
//
// Presentation only: GameCore's ground, the saves and the golden scenarios
// are untouched. The references have no such filter (the owner's
// `Simulator/` smooths a track's grade, not the ground; OpenTTD and
// Simutrans keep their own tile heights, ideas only): the filter is this
// project's own.

/// The 3D map's levelled ground on a real-world map (decision 737): each
/// 64 m corner worked out from the world's corners round it.
struct Map3DLevelledGround {
    /// How many cells either way a corner's mean reaches.
    static let radius = 3
    /// The Gaussian's spread, in cells (128 m).
    static let spread = 2.0
    /// The most a corner moves from the world's, in metres.
    static let reach: Float = 3
    /// The weight of the corner `offset` cells away along one axis; a
    /// corner's is the product of its two axes'.
    static let weights: [Double] = (-radius...radius).map { offset in
        let d = Double(offset)
        return exp(-d * d / (2 * spread * spread))
    }

    /// The cells (64 m, as ``Map3DScene/ChunkKey``) whose corners stay the
    /// world's: the player's track's, whole network.
    let held: Set<Map3DScene.ChunkKey>
    /// The world's corners in rows `firstRow...`, columns `firstColumn...`,
    /// read once for the scene's region and round it; past them ``raw``.
    let firstRow: Int, firstColumn: Int, rows: Int, columns: Int
    let heights: [Float]
    let wet: [Bool]
    /// The world's corners, in cells: those within ``radius`` of them are
    /// not moved.
    let lastRow: Int, lastColumn: Int
    /// The world's corner (`row`, `column`) and whether a cell round it is
    /// water, past the kept ones.
    let raw: (Int, Int) -> Float
    let water: (Int, Int) -> Bool
    /// The corners worked out, shared by the scene's copies of this
    /// ground: ``Map3DScene/Builder/ground(x:y:)`` reads them far past the
    /// kept ones (a real line's whole window).
    let memo = Memo()

    final class Memo: @unchecked Sendable {
        private let lock = NSLock()
        private var corners: [Map3DScene.ChunkKey: Float] = [:]
        private var raws: [Map3DScene.ChunkKey: Float] = [:]

        func raw(_ key: Map3DScene.ChunkKey, read: () -> Float) -> Float {
            if let known = lock.withLock({ raws[key] }) { return known }
            let found = read()
            lock.withLock { raws[key] = found }
            return found
        }

        func corner(_ key: Map3DScene.ChunkKey, workOut: () -> Float) -> Float {
            if let known = lock.withLock({ corners[key] }) { return known }
            let found = workOut()
            lock.withLock { corners[key] = found }
            return found
        }
    }

    /// Reads the world's corners over rows `rowRange` and columns
    /// `columnRange` and ``radius`` round them.
    init(held: Set<Map3DScene.ChunkKey>, rows rowRange: ClosedRange<Int>, columns columnRange: ClosedRange<Int>, lastRow: Int, lastColumn: Int,
         raw: @escaping (Int, Int) -> Float, water: @escaping (Int, Int) -> Bool) {
        self.held = held
        self.raw = raw
        self.water = water
        self.lastRow = lastRow
        self.lastColumn = lastColumn
        let r = Self.radius
        firstRow = rowRange.lowerBound - r
        firstColumn = columnRange.lowerBound - r
        rows = rowRange.count + 2 * r
        columns = columnRange.count + 2 * r
        var heights: [Float] = [], wet: [Bool] = []
        heights.reserveCapacity(rows * columns)
        wet.reserveCapacity(rows * columns)
        for row in firstRow..<(firstRow + rows) {
            for column in firstColumn..<(firstColumn + columns) {
                heights.append(raw(row, column))
                wet.append(water(row, column))
            }
        }
        self.heights = heights
        self.wet = wet
    }

    func rawCorner(_ row: Int, _ column: Int) -> Float {
        let r = row - firstRow, c = column - firstColumn
        guard r >= 0, c >= 0, r < rows, c < columns else {
            return memo.raw(Map3DScene.ChunkKey(column: column, row: row)) { raw(row, column) }
        }
        return heights[r * columns + c]
    }

    func isWet(_ row: Int, _ column: Int) -> Bool {
        let r = row - firstRow, c = column - firstColumn
        guard r >= 0, c >= 0, r < rows, c < columns else { return water(row, column) }
        return wet[r * columns + c]
    }

    /// Whether corner (`row`, `column`) stays the world's: a cell round it
    /// is held track, it is water, or it is near the world's edge.
    func holds(row: Int, column: Int) -> Bool {
        let r = Self.radius
        guard row >= r, column >= r, row <= lastRow - r, column <= lastColumn - r else { return true }
        for (dr, dc) in [(-1, -1), (-1, 0), (0, -1), (0, 0)] where held.contains(Map3DScene.ChunkKey(column: column + dc, row: row + dr)) {
            return true
        }
        return isWet(row, column)
    }

    /// The drawn height of corner (`row`, `column`): `own` (the world's
    /// there, as the caller reads it) where it is held, else the mean of
    /// the dry corners round it, at most ``reach`` from the world's.
    func corner(row: Int, column: Int, own: Float) -> Float {
        guard !holds(row: row, column: column) else { return own }
        // Of the world's corner as every region reads it (decision 406),
        // so the value kept is the same whoever asks first.
        return memo.corner(Map3DScene.ChunkKey(column: column, row: row)) { levelled(row: row, column: column) }
    }

    func levelled(row: Int, column: Int) -> Float {
        let own = rawCorner(row, column)
        let r = Self.radius
        var sum = 0.0, weight = 0.0
        for dr in -r...r {
            let across = Self.weights[dr + r]
            for dc in -r...r where !isWet(row + dr, column + dc) {
                let w = across * Self.weights[dc + r]
                sum += w * Double(rawCorner(row + dr, column + dc))
                weight += w
            }
        }
        guard weight > 0 else { return own }
        let moved = Float(sum / weight) - own
        return own + min(max(moved, -Self.reach), Self.reach)
    }
}
