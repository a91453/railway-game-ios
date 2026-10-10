import Foundation
import GameCore

// How much of the ground real buildings cover on a real-world map
// (ARCHITECTURE decision 147): Overture Maps' footprints on the water
// file's grid (1.875″, some 58 × 53 m), in whole percent, -1 where they are
// not known (Kinmen and Matsu, where Overture misses most of the towns).
// Bundled as `Resources/RealWorld/taiwan_coverage.dat` by
// `tools/real-world-population/build_coverage_grid.py`, in the heights
// file's form (``HeightGrid``) under the magic `TWCV`.
//
// Only the presentation reads it: each cell of land read from the
// real-world grids takes the coverage of the grid cell its middle lies in
// (``LandCell/coverage``), and the world saves it with the land, so a save
// does not depend on the file. GameCore buys out a city building by it.

/// How much of each cell of a grid of Taiwan real buildings cover
/// (decision 147).
public struct CoverageGrid: Sendable {
    let grid: HeightGrid

    /// Reads the app's coverage file. Throws for a file out of shape, as
    /// ``HeightGrid/init(data:)`` does.
    public init(data: Data) throws {
        grid = try HeightGrid(data: data, magic: "TWCV")
    }

    /// `cells` of a world laid over the Earth by `frame`, each with the
    /// coverage of the grid cell its middle lies in: 0 to 100, or `nil`
    /// outside the grid, where it is not known or in a row that does not
    /// decode. Their order is kept.
    public func covering(_ cells: [LandCell], frame: RealWorldFrame) -> [LandCell] {
        var rows: [Int: [Int16]] = [:]
        return cells.map { cell in
            let middle = cell.middle
            let place = frame.coordinate(worldX: Double(middle.x), worldY: Double(middle.y))
            let row = Int(((grid.north - place.latitude) / grid.cellDegrees).rounded(.down))
            let column = Int(((place.longitude - grid.west) / grid.cellDegrees).rounded(.down))
            guard (0..<grid.rows).contains(row), (0..<grid.columns).contains(column) else { return cell }
            if rows[row] == nil {
                rows[row] = grid.row(row) ?? []
            }
            guard let values = rows[row], !values.isEmpty, (0...100).contains(values[column]) else { return cell }
            return LandCell(row: cell.row, column: cell.column, use: cell.use, residents: cell.residents, jobs: cell.jobs,
                            coverage: Int64(values[column]))
        }
    }
}
