import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 876 (later, PERF-3D-BLOCK-FIXED): what a 3D block looks up
/// millions of times, kept so it is found faster, and found the same: the
/// cells' keys hashed by their own finalizer, the ground's corners in an
/// array, the heights file's rows and the base map's directories
/// unpacked once. Each answers what it answered before.
final class Map3DBlockMemoTests: XCTestCase {
    private typealias Key = Map3DScene.ChunkKey

    /// Keys equal in their column and row hash alike under every seed, and
    /// a set and a dictionary of them hold each once, near zero, far off
    /// and below it (a scene's cells lie either side of its origin).
    func testACellsKeyHashesAsItEquals() {
        var keys: [Key] = []
        for row in -40...40 {
            for column in -40...40 { keys.append(Key(column: column, row: row)) }
        }
        keys += [Key(column: Int.max, row: Int.min), Key(column: Int.min, row: Int.max), Key(column: 1 << 40, row: 3),
                 Key(column: 0, row: 1 << 40), Key(column: -(1 << 33), row: -(1 << 33))]
        XCTAssertEqual(Set(keys).count, keys.count)
        var numbered: [Key: Int] = [:]
        for (number, key) in keys.enumerated() { numbered[key] = number }
        for (number, key) in keys.enumerated() {
            let again = Key(column: key.column, row: key.row)
            XCTAssertEqual(numbered[again], number)
            XCTAssertEqual(again.hashValue, key.hashValue)
            for seed in [0, 1, -1, 0x5EED, Int.max] { XCTAssertEqual(again._rawHashValue(seed: seed), key._rawHashValue(seed: seed)) }
        }
        // Spread: a block's 6,561 cells in 4,096 buckets fill as many as
        // a random hash would (4,096 × (1 − e^(−6,561 / 4,096)), some 3,270).
        let buckets = Set(keys.prefix(81 * 81).map { $0._rawHashValue(seed: 12_345) & 4_095 })
        XCTAssertGreaterThan(buckets.count, 3_150)
    }

    /// The corners round the region are kept in an array, the rest by
    /// key: every corner keeps what it was given, and one never given is
    /// not there.
    func testTheGroundsCornersKeepWhatTheyAreGiven() {
        let cell = Double(Land.cellLength)
        let region = WorldRegion(minX: 100 * cell, minY: -20 * cell, maxX: 116 * cell, maxY: -4 * cell)
        var corners = Map3DScene.Builder.CornerHeights(region: region)
        var given: [Key: Float] = [:]
        for (row, column) in [(-20, 100), (-4, 116), (-20 - 48, 100 - 48), (-4 + 48, 116 + 48), (-69, 100), (0, 0), (-12, 108), (500, -500)] {
            let height = Float(row * 1_000 + column) / 7
            corners[row, column] = height
            given[Key(column: column, row: row)] = height
        }
        for (key, height) in given {
            XCTAssertEqual(corners[key.row, key.column], height, "\(key)")
            XCTAssertEqual(corners[key], height, "\(key)")
        }
        XCTAssertNil(corners[-19, 100])
        XCTAssertNil(corners[-69, 101])
        XCTAssertEqual(Set(corners.keys), Set(given.keys))
        corners[-12, 108] = nil
        XCTAssertNil(corners[-12, 108])
        // With no region, every corner by key.
        var plain = Map3DScene.Builder.CornerHeights()
        plain[3, 4] = 2.5
        XCTAssertEqual(plain[3, 4], 2.5)
        XCTAssertEqual(plain.keys, [Key(column: 4, row: 3)])
    }

    /// The heights file read through its rows' memo gives every height as
    /// the row unpacked on its own does, before and after the memo starts
    /// again.
    func testTheHeightsFilesRowsReadTheSameFromTheMemo() throws {
        let grid = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
        let rows = Array(stride(from: 3_000, to: grid.rows, by: 7).prefix(HeightGrid.RowMemo.limit + 40))
        for pass in 0..<2 {
            var reader = HeightGrid.Reader(grid)
            for row in rows {
                let own = try XCTUnwrap(grid.row(row))
                for column in stride(from: 0, to: grid.columns, by: 997) {
                    XCTAssertEqual(reader.height(row: row, column: column), Double(own[column]), "pass \(pass), row \(row), column \(column)")
                }
            }
        }
    }

    /// The base map's tiles read through its directories' memo are the
    /// tiles a new archive reads, the second time as the first, and a
    /// place with no tile has none either way.
    func testTheBaseMapsTilesReadTheSameFromTheMemo() throws {
        let file = Map3DRealTrainsTests.resources.appendingPathComponent("BaseMap/taiwan.pmtiles")
        let data = try Data(contentsOf: file, options: .alwaysMapped)
        let kept = try PMTilesArchive(data: data)
        let zoom = BaseMapTiles.zoom
        func tile(latitude: Double, longitude: Double) -> (x: Int, y: Int) {
            let n = Double(1 << zoom), radians = latitude * .pi / 180
            return (Int((longitude + 180) / 360 * n), Int((1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2 * n))
        }
        var places = [tile(latitude: 25.0478, longitude: 121.5170), tile(latitude: 22.6394, longitude: 120.3024),
                      tile(latitude: 24.1372, longitude: 120.6869), tile(latitude: 35, longitude: 139)]
        let taipei = places[0]
        for dx in -2...2 { places.append((taipei.x + dx, taipei.y + 3)) }
        var found = 0
        for pass in 0..<2 {
            for place in places {
                let fresh = try PMTilesArchive(data: data).tile(zoom: zoom, x: place.x, y: place.y)
                XCTAssertEqual(try kept.tile(zoom: zoom, x: place.x, y: place.y), fresh, "pass \(pass), \(place)")
                if fresh != nil { found += 1 }
            }
        }
        XCTAssertGreaterThan(found, 10, "Taiwan's tiles are there")
        XCTAssertNil(try kept.tile(zoom: zoom, x: places[3].x, y: places[3].y), "Tokyo is not on Taiwan's base map")
    }
}
