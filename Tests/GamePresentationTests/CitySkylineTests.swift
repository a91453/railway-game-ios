import GameCore
import GamePresentation
import XCTest

/// Decision 126: the city's buildings on the plain map, read from the land
/// and its buildings: one lot a building, by its use and density, parks
/// and farms as open ground, north to south; asked only for what is in
/// view.
final class CitySkylineTests: XCTestCase {
    func testEveryBuildingIsALotByItsUseAndDensityAndParksAndFarmsAreOpenGround() throws {
        let world = GameWorld.newGame()
        let skyline = CitySkyline(world: world)
        XCTAssertFalse(skyline.isEmpty, "a new game has towns")
        XCTAssertEqual(skyline.lots, skyline.lots.sorted { ($0.row, $0.column) < ($1.row, $1.column) }, "north to south")
        var buildings = 0
        for cell in world.land.cells {
            let lot = skyline.lots.first { $0.row == cell.row && $0.column == cell.column }
            let building = world.buildings.building(row: cell.row, column: cell.column)
            if CitySkyline.openGround.contains(building?.use ?? cell.use) {
                XCTAssertEqual(lot?.density, 0)
                XCTAssertEqual(lot?.isOpenGround, true)
            } else if let building {
                buildings += 1
                XCTAssertEqual(lot?.use, building.use)
                XCTAssertEqual(lot?.density, building.kind == .existingStock ? 4 : building.density.rawValue)
                XCTAssertEqual(lot?.isOpenGround, false)
            } else {
                XCTAssertNil(lot, "land without its building draws nothing")
            }
        }
        XCTAssertGreaterThan(buildings, 0)
        XCTAssertTrue(skyline.lots.contains(where: \.isOpenGround), "the towns have parks and farms")
    }

    func testAWorldWithoutLandHasNoSkyline() throws {
        XCTAssertTrue(CitySkyline(world: try makeWorld()).isEmpty)
        XCTAssertEqual(CitySkyline(world: try makeWorld()).lots(in: WorldRegion(minX: 0, minY: 0, maxX: 8_192, maxY: 6_144)), [])
    }

    /// Only the lots in view, and those a few rows south whose buildings
    /// rise into it, in drawing order.
    func testTheLotsInARegionAreThoseItReachesAndTheRowsBelowIt() throws {
        let skyline = CitySkyline(world: GameWorld.newGame())
        let length = Double(Land.cellLength)
        let middle = try XCTUnwrap(skyline.lots[skyline.lots.count / 2])
        let region = WorldRegion(
            minX: Double(middle.column - 3) * length + 1, minY: Double(middle.row - 2) * length + 1,
            maxX: Double(middle.column + 3) * length + 1, maxY: Double(middle.row + 2) * length + 1
        )
        let inView = skyline.lots(in: region)
        XCTAssertFalse(inView.isEmpty)
        XCTAssertEqual(inView, skyline.lots.filter {
            (middle.row - 2...middle.row + 2).contains($0.row) && (middle.column - 3...middle.column + 3).contains($0.column)
        })
        let withBelow = skyline.lots(in: region, rowsBelow: CitySkyline.rowsRisenOver)
        XCTAssertEqual(withBelow, skyline.lots.filter {
            (middle.row - 2...middle.row + 2 + CitySkyline.rowsRisenOver).contains($0.row)
                && (middle.column - 3...middle.column + 3).contains($0.column)
        })
        XCTAssertEqual(skyline.lots(in: WorldRegion(minX: -.infinity, minY: 0, maxX: 0, maxY: 0)), [])
    }

    /// Taller with density, and a D4 tower stays within the rows the map
    /// looks below the view for.
    func testHeightsGrowWithDensityWithinTheRowsLookedAt() {
        let shares = (0...4).map { CitySkyline.heightShare(density: $0) }
        XCTAssertEqual(shares[0], 0)
        XCTAssertEqual(shares, shares.sorted())
        XCTAssertEqual(Set(shares).count, shares.count)
        let tallest = shares[4] * Double(PlacedBuildingRules.cityBuildingSide)
        XCTAssertLessThanOrEqual(tallest, Double(CitySkyline.rowsRisenOver) * Double(Land.cellLength))
    }
}
