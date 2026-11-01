import Foundation
import GameCore

/// Decision 517 續 (BUILD3D-3, PR 3): the ground as a scene draws it, kept
/// for taps (``Map3DPick``): the heights at the 64 m grid's corners
/// (``Land/cellLength``) over the scene's region, each square split from
/// its north-west corner to its south-east one as the scene's ground quads
/// are. Until this the pick read only the world's ground
/// (``GameWorld/groundHeight(at:)``), and on a real-world map the blocks
/// the world has not read were sea level there while the scene drew the
/// heights file's hills.
///
/// Past the region (a chunk streamed in later), a corner is worked out by
/// the scene's own rule: the world's ground where it has read it, else the
/// heights file's, else 0 m; past the world's edge, the edge's.
public struct Map3DGroundGrid: Sendable {
    /// The corner of the first row and column kept.
    public let firstRow: Int
    public let firstColumn: Int
    /// How many corners each way.
    public let rows: Int
    public let columns: Int
    let heights: [Float]
    let originX: Double
    let originY: Double
    let file: Map3DScene.FileGround?

    init(originX: Double, originY: Double, firstRow: Int, firstColumn: Int, rows: Int, columns: Int, heights: [Float],
         file: Map3DScene.FileGround?) {
        precondition(heights.count == rows * columns)
        self.originX = originX
        self.originY = originY
        self.firstRow = firstRow
        self.firstColumn = firstColumn
        self.rows = rows
        self.columns = columns
        self.heights = heights
        self.file = file
    }

    /// The kept height at the 64 m grid's corner (`row`, `column`), in
    /// metres; `nil` outside what the scene drew.
    public func corner(row: Int, column: Int) -> Float? {
        guard (0..<rows).contains(row - firstRow), (0..<columns).contains(column - firstColumn) else { return nil }
        return heights[(row - firstRow) * columns + column - firstColumn]
    }

    /// The ground's height, in metres, at scene point (`x`, `z`) as the
    /// scene draws it; outside the kept corners, by the scene's rule on
    /// `world`.
    public func height(x: Float, z: Float, world: GameWorld) -> Float {
        let cell = Double(Land.cellLength), metre = Double(WorldCoordinate.unitsPerMetre)
        let worldX = originX + Double(x) * metre, worldY = originY + Double(z) * metre
        let column = Int((worldX / cell).rounded(.down)), row = Int((worldY / cell).rounded(.down))
        let fx = Float(worldX / cell - Double(column)), fy = Float(worldY / cell - Double(row))
        func at(_ row: Int, _ column: Int) -> Float {
            if let kept = corner(row: row, column: column) { return kept }
            let bounds = world.bounds
            let plan = PlanPoint(x: min(max(Int64((Double(column) * cell).rounded()), 0), bounds.width - 1),
                                 y: min(max(Int64((Double(row) * cell).rounded()), 0), bounds.height - 1))
            if let height = world.groundHeight(at: plan) { return Float(Double(height) / metre) }
            return file?.corner(row: Int((Double(plan.y) / cell).rounded(.down)), column: Int((Double(plan.x) / cell).rounded(.down))) ?? 0
        }
        let a = at(row, column), b = at(row + 1, column), c = at(row + 1, column + 1), d = at(row, column + 1)
        // a (0, 0), b (0, 1), c (1, 1), d (1, 0) in (fx, fy): the
        // triangles a b c and a c d, as the scene's quads.
        return fy >= fx ? a + fx * (c - b) + fy * (b - a) : a + fx * (d - a) + fy * (c - d)
    }
}
