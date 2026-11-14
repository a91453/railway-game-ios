import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 737: the 3D map's levelled ground on a real-world map.
final class Map3DLevelledGroundTests: XCTestCase {
    private typealias Levelled = Map3DLevelledGround
    private typealias Key = Map3DScene.ChunkKey

    /// A levelled ground over a 40 × 40 world of corners whose heights are
    /// `height`, read over rows and columns `rows`, with `held` cells and
    /// `wet` corners.
    private func levelled(_ height: @escaping (Int, Int) -> Float, rows: ClosedRange<Int> = 10...30, held: Set<Key> = [],
                          wet: @escaping (Int, Int) -> Bool = { _, _ in false }) -> Levelled {
        Levelled(held: held, rows: rows, columns: rows, lastRow: 40, lastColumn: 40, raw: height, water: wet)
    }

    /// A hillside keeps its slope: the mean of a plane is the plane.
    func testAPlaneStaysAsItIs() {
        let plane: (Int, Int) -> Float = { row, column in 3 * Float(row) - 1.5 * Float(column) + 40 }
        let ground = levelled(plane)
        for row in 12...28 {
            for column in 12...28 {
                XCTAssertEqual(ground.corner(row: row, column: column, own: plane(row, column)), plane(row, column), accuracy: 1e-3)
            }
        }
    }

    /// The surface model's bumps (here a metre up and down from one corner
    /// to the next, as buildings and whole-metre rounding leave them) are
    /// smoothed nearly away.
    func testBumpsAreSmoothed() {
        let bumps: (Int, Int) -> Float = { row, column in (row + column) % 2 == 0 ? 11 : 9 }
        let ground = levelled(bumps)
        for row in 12...28 {
            for column in 12...28 {
                XCTAssertEqual(ground.corner(row: row, column: column, own: bumps(row, column)), 10, accuracy: 0.1)
            }
        }
    }

    /// A ridge moves at most ``Map3DLevelledGround/reach``.
    func testACornerMovesAtMostItsReach() {
        let peak: (Int, Int) -> Float = { row, column in row == 20 && column == 20 ? 60 : 0 }
        let ground = levelled(peak)
        XCTAssertEqual(ground.corner(row: 20, column: 20, own: 60), 60 - Levelled.reach)
        let beside = ground.corner(row: 20, column: 21, own: 0)
        XCTAssertGreaterThan(beside, 0)
        XCTAssertLessThanOrEqual(beside, Levelled.reach)
    }

    /// The corners of the player's track's cells, of water and near the
    /// world's edge stay the world's.
    func testHeldCornersStayTheWorlds() {
        let bumps: (Int, Int) -> Float = { row, column in (row + column) % 2 == 0 ? 11 : 9 }
        let ground = levelled(bumps, held: [Key(column: 20, row: 20)], wet: { row, column in row == 15 && column == 15 })
        // The held cell's four corners.
        for (row, column) in [(20, 20), (20, 21), (21, 20), (21, 21)] {
            XCTAssertEqual(ground.corner(row: row, column: column, own: bumps(row, column)), bumps(row, column))
        }
        XCTAssertNotEqual(ground.corner(row: 22, column: 22, own: bumps(22, 22)), bumps(22, 22))
        XCTAssertEqual(ground.corner(row: 15, column: 15, own: 11), 11)
        // Within the reach of the edge.
        XCTAssertEqual(ground.corner(row: 2, column: 20, own: 11), 11)
        XCTAssertEqual(ground.corner(row: 20, column: 38, own: 11), 11)
    }

    /// Water is left out of the land's mean, so a bank keeps its height.
    func testWaterIsLeftOutOfTheMean() {
        let bank: (Int, Int) -> Float = { _, column in column < 20 ? 0 : 8 }
        let ground = levelled(bank, wet: { _, column in column < 20 })
        XCTAssertEqual(ground.corner(row: 20, column: 21, own: 8), 8, accuracy: 1e-4)
    }

    /// Regions built apart (their kept corners elsewhere) level a corner
    /// alike, so their ground meets with no seam.
    func testRegionsBuiltApartAgree() {
        let rough: (Int, Int) -> Float = { row, column in Float((row * 7919 + column * 104_729) % 13) * 0.5 }
        let one = levelled(rough, rows: 8...20), other = levelled(rough, rows: 18...32)
        for row in 16...22 {
            for column in 16...22 {
                XCTAssertEqual(one.corner(row: row, column: column, own: rough(row, column)),
                               other.corner(row: row, column: column, own: rough(row, column)))
            }
        }
    }

    // MARK: On the map

    private static let heights: Result<HeightGrid, Error> = Result { try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat")) }

    /// Central Taipei (Zhongxiao East Road by the Sun Yat-sen Memorial
    /// Hall, flat ground): the drawn ground is at least twice as smooth as
    /// the world's, and no corner moves more than its reach.
    func testCentralTaipeiIsLevelled() throws {
        var world = GameWorld.newGame(anchor: try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.0415, longitudeDegrees: 121.5560)))
        try world.mapGround()
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let at = frame.worldPosition(latitude: 25.0415, longitude: 121.5560)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 1_000.0
        let region = WorldRegion(minX: at.x - half * metre, minY: at.y - half * metre, maxX: at.x + half * metre, maxY: at.y + half * metre)
        var raw = Map3DScene.Builder(originX: at.x, originY: at.y, region: region, world: world, heights: try Self.heights.get())
        var drawn = raw
        drawn.levelGround(under: world.railwaySnapshot())
        XCTAssertNotNil(drawn.levelling)
        let cell = Double(Land.cellLength)
        let rows = Int((region.minY / cell).rounded(.up))...Int((region.maxY / cell).rounded(.down))
        let columns = Int((region.minX / cell).rounded(.up))...Int((region.maxX / cell).rounded(.down))
        func roughness(_ builder: inout Map3DScene.Builder) -> Float {
            var sum: Float = 0, count: Float = 0
            for row in rows.dropFirst().dropLast() {
                for column in columns.dropFirst().dropLast() {
                    let around = builder.groundCorner(row: row - 1, column: column) + builder.groundCorner(row: row + 1, column: column)
                        + builder.groundCorner(row: row, column: column - 1) + builder.groundCorner(row: row, column: column + 1)
                    sum += abs(builder.groundCorner(row: row, column: column) - around / 4)
                    count += 1
                }
            }
            return sum / count
        }
        let before = roughness(&raw), after = roughness(&drawn)
        print("ROAD-FLATTEN central Taipei roughness", before, "→", after)
        XCTAssertGreaterThan(before, 0.2)
        XCTAssertLessThan(after, before / 2)
        for row in rows {
            for column in columns {
                XCTAssertLessThanOrEqual(abs(drawn.groundCorner(row: row, column: column) - raw.groundCorner(row: row, column: column)),
                                         Levelled.reach + 1e-4)
            }
        }
    }
}
