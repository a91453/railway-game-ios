import Foundation
import GameCore

// How dear Taiwan's land is, place by place (decision 1025): each 7.5″
// cell's land price (some 230 m) over the country's median of the same
// zone, from the real-price registry's sales of 110 to 115 (實價登錄),
// in thousandths. Bundled as `Resources/RealWorld/taiwan_land_price.dat`
// by `tools/real-land-price/build_land_price_grid.py`, in the heights
// file's form (``HeightGrid``) under the magic `TWLP`; -1 where nothing
// is known (the sea, outside every township).
//
// Only the presentation reads it, with the coverage file it is loaded
// beside (``CoverageGrid/landPrice``): each 256 m square of land read in
// takes the factor of the grid cell its middle lies in
// (``GameWorld/setLandLocations(_:)``), and the world saves it with the
// land, so a save does not depend on the file.

/// How dear the land of each cell of a grid of Taiwan is against the
/// country (decision 1025).
public struct LandPriceGrid: Sendable {
    let grid: HeightGrid

    /// Reads the app's land price file. Throws for a file out of shape, as
    /// ``HeightGrid/init(data:)`` does.
    public init(data: Data) throws {
        grid = try HeightGrid(data: data, magic: "TWLP")
    }

    /// The factors of the squares (``LandLocations/squareCells`` cells a
    /// side) of `blocks` of a world of `bounds` laid over the Earth by
    /// `frame`, each the factor of the grid cell its middle lies in; none
    /// for a square outside the world or the grid, where nothing is known
    /// or in a row that does not decode. By row and then column.
    public func locations(in blocks: some Sequence<LandBlock>, frame: RealWorldFrame, bounds: WorldBounds) -> [LandLocation] {
        let per = Land.blockCells / LandLocations.squareCells
        var squares: [CellPosition] = []
        for block in blocks {
            for r in 0..<per {
                for c in 0..<per {
                    squares.append(CellPosition(row: block.row * per + r, column: block.column * per + c))
                }
            }
        }
        return locations(of: squares, frame: frame, bounds: bounds)
    }

    /// The factors of every square of a world of `bounds` laid over the
    /// Earth by `frame` (a map whose land came all at once).
    public func locations(frame: RealWorldFrame, bounds: WorldBounds) -> [LandLocation] {
        var squares: [CellPosition] = []
        for row in 0..<LandLocations.squareRows(in: bounds) {
            for column in 0..<LandLocations.squareColumns(in: bounds) {
                squares.append(CellPosition(row: row, column: column))
            }
        }
        return locations(of: squares, frame: frame, bounds: bounds)
    }

    private func locations(of squares: [CellPosition], frame: RealWorldFrame, bounds: WorldBounds) -> [LandLocation] {
        let rows = LandLocations.squareRows(in: bounds), columns = LandLocations.squareColumns(in: bounds)
        let side = Land.cellLength * Int64(LandLocations.squareCells)
        var decoded: [Int: [Int16]] = [:]
        var found: [LandLocation] = []
        for square in Set(squares).sorted() {
            guard (0..<rows).contains(square.row), (0..<columns).contains(square.column) else { continue }
            let x = Double(Int64(square.column) * side + side / 2), y = Double(Int64(square.row) * side + side / 2)
            let place = frame.coordinate(worldX: x, worldY: y)
            let row = Int(((grid.north - place.latitude) / grid.cellDegrees).rounded(.down))
            let column = Int(((place.longitude - grid.west) / grid.cellDegrees).rounded(.down))
            guard (0..<grid.rows).contains(row), (0..<grid.columns).contains(column) else { continue }
            if decoded[row] == nil {
                decoded[row] = grid.row(row) ?? []
            }
            guard let values = decoded[row], !values.isEmpty else { continue }
            let factor = Int64(values[column])
            guard (LandLocations.lowest...LandLocations.highest).contains(factor) else { continue }
            found.append(LandLocation(row: square.row, column: square.column, factor: factor))
        }
        return found
    }
}
