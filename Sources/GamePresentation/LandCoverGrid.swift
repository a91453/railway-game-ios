import Foundation
import GameCore

// What covers Taiwan's ground outside its towns (ARCHITECTURE decision
// 811): ESA WorldCover 10 m 2021 v200 (© ESA WorldCover project 2021,
// Copernicus Sentinel data processed by the ESA WorldCover consortium,
// CC BY 4.0) on the water file's grid (1.875″, some 58 × 53 m): each cell
// the class most of its samples are, folded into the game's eight, then
// the most common of the 3 × 3 cells round it. Bundled as `Resources/RealWorld/taiwan_landcover.dat`
// by `tools/worldcover/build_landcover_grid.py`, in the heights file's form
// (``HeightGrid``) under the magic `TWLC`.
//
// Only the presentation reads it, for the look of the 3D map's ground
// outside OpenStreetMap's land cover and the trees in its forests
// (``Map3DScene/Builder/landCover``); nothing of the game's rules or saves
// depends on it.

/// What covers each cell of a grid of Taiwan (decision 811).
public struct LandCoverGrid: Sendable {
    /// The game's eight covers, folded from WorldCover's eleven classes
    /// (the tool's docstring).
    public enum Cover: Int, CaseIterable, Sendable {
        case unknown = 0
        case forest, shrubland, grassland, cropland, builtUp, bare, water, wetland
    }

    let grid: HeightGrid

    /// Reads the app's land cover file. Throws for a file out of shape, as
    /// ``HeightGrid/init(data:)`` does.
    public init(data: Data) throws {
        grid = try HeightGrid(data: data, magic: "TWLC")
    }

    /// Reads rows as asked, each once.
    struct Reader {
        let grid: LandCoverGrid
        private var rows: [Int: [Int16]] = [:]

        init(_ grid: LandCoverGrid) {
            self.grid = grid
        }

        /// The cover at (`latitude`, `longitude`); `nil` outside the grid,
        /// where nothing is known (water, or no WorldCover tile) or in a
        /// row that does not decode.
        mutating func cover(latitude: Double, longitude: Double) -> Cover? {
            let heights = grid.grid
            let row = Int(((heights.north - latitude) / heights.cellDegrees).rounded(.down))
            let column = Int(((longitude - heights.west) / heights.cellDegrees).rounded(.down))
            guard (0..<heights.rows).contains(row), (0..<heights.columns).contains(column) else { return nil }
            if rows[row] == nil {
                rows[row] = heights.row(row) ?? []
            }
            guard let values = rows[row], !values.isEmpty, let cover = Cover(rawValue: Int(values[column])), cover != .unknown else { return nil }
            return cover
        }
    }

    /// The cover at (`latitude`, `longitude`), as ``Reader`` reads it.
    public func cover(latitude: Double, longitude: Double) -> Cover? {
        var reader = Reader(self)
        return reader.cover(latitude: latitude, longitude: longitude)
    }
}
