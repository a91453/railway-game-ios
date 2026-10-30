@testable import GameCore
@testable import GamePresentation
import XCTest

/// PERF_3D_COCKPIT (2026-10-30): the 3D map's scene key and its buses'
/// signature count the roads at every tick without making the union of
/// the city's and the player's cells (``RoadGrid/roadCellCount``).
final class RoadCellCountTests: XCTestCase {
    /// The count is ``RoadGrid/allCells``'s: the city's cells, and the
    /// player's that are not among them, once each.
    func testTheCountIsTheUnions() {
        let city = Set((0..<40).flatMap { row in (0..<40).map { CellPosition(row: row, column: $0) } })
        let built: Set<CellPosition> = [CellPosition(row: 3, column: 3), CellPosition(row: 50, column: 50), CellPosition(row: 51, column: 50)]
        for roads in [RoadGrid(), RoadGrid(cells: city), RoadGrid(built: built), RoadGrid(cells: city, built: built)] {
            XCTAssertEqual(roads.roadCellCount, roads.allCells.count)
        }
        XCTAssertEqual(RoadGrid(cells: city, built: built).roadCellCount, 1_602)
    }

    /// A road the player builds changes the buses' signature, as the
    /// union's count did; the city's cells alone keep it.
    func testABuiltRoadChangesTheBusesSignature() throws {
        let city = Set((0..<10).map { CellPosition(row: 0, column: $0) })
        var world = GameWorld(bounds: try WorldBounds(width: 65_536, height: 65_536), economy: GameEconomy(balance: Money(1_000_000)))
        world.roads = RoadGrid(cells: city)
        let before = Map3DBuses.Signature(world: world, palette: .standard)
        XCTAssertEqual(before.roads, 10)
        world.roads = RoadGrid(cells: city, built: [CellPosition(row: 1, column: 0)])
        XCTAssertNotEqual(Map3DBuses.Signature(world: world, palette: .standard), before)
        world.roads = RoadGrid(cells: city, built: [CellPosition(row: 0, column: 0)])
        XCTAssertEqual(Map3DBuses.Signature(world: world, palette: .standard), before)
    }
}
