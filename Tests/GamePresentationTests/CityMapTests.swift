import Foundation
import GameCore
import GamePresentation
import XCTest

/// The city's map layers (Phase 6d, ARCHITECTURE decision 76): land use,
/// land value and catchment coverage drawn from the world, the tapped
/// cell's tooltip and the station panel's average land value.
final class CityMapTests: XCTestCase {
    /// A world 32 × 24 cells: homes, shops, offices and existing stock in
    /// row 5, a home far off at row 20, column 30, and a station at the
    /// middle of row 5, column 5.
    private func world() throws -> GameWorld {
        var world = GameWorld(bounds: try WorldBounds(width: 131_072, height: 98_304), economy: GameEconomy(balance: 1_000_000_000, costs: ConstructionCosts(track: 1, station: 1, train: 1)))
        try world.setLand([
            LandCell(row: 5, column: 4, use: .residential, residents: 56, jobs: 0),
            LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0),
            LandCell(row: 5, column: 6, use: .commercial, residents: 0, jobs: 1_000),
            LandCell(row: 5, column: 7, use: .office, residents: 0, jobs: 5_000),
            LandCell(row: 20, column: 30, use: .residential, residents: 9, jobs: 0),
        ])
        world.setCityBuildings(true)
        try world.buildStation(named: "Alpha", at: PlanPoint(x: 5 * 4_096 + 2_048, y: 5 * 4_096 + 2_048))
        return world
    }

    private static let everywhere = WorldRegion(minX: 0, minY: 0, maxX: 131_072, maxY: 98_304)

    func testTheCityLayersAreOnePopTravelLayerAtATime() {
        var layers = MapLayerPreferences()
        layers.setShows(.landValue, true)
        XCTAssertTrue(layers.shows(.landValue))
        layers.setShows(.population, true)
        XCTAssertFalse(layers.shows(.landValue), "one at a time")
        XCTAssertTrue(PopTravelMode.landUse.isCityLayer)
        XCTAssertFalse(PopTravelMode.landValue.usesHour)
        XCTAssertFalse(PopTravelMode.coverage.usesHour)
        XCTAssertTrue(PopTravelMode.travel.usesHour)
        XCTAssertEqual(PopTravel.baseOpacity(for: .coverage, compactWidth: true), 0.8)
        XCTAssertEqual(PopTravelMode.landUse.title(in: .traditionalChinese), "土地用途")
        XCTAssertEqual(PopTravelMode.landValue.title(in: .english), "Land value")
        XCTAssertEqual(PopTravelMode.coverage.title(in: .traditionalChinese), "腹地涵蓋")
        XCTAssertTrue(TravelDemandMap(trips: [:]).tiles(for: .landValue, at: 8).isEmpty)
    }

    func testLandUseColoursEachCellByItsUseAndDensity() throws {
        let map = CityMap(world: try world())
        let tiles = map.tiles(for: .landUse, in: Self.everywhere)
        XCTAssertEqual(tiles.count, 5)
        // D1 homes, D2 homes, D4 shops, existing stock offices (as D4), D1 homes.
        XCTAssertEqual(tiles.map(\.color), [
            CityMap.useColor(use: 1, density: 1), CityMap.useColor(use: 1, density: 2), CityMap.useColor(use: 2, density: 4),
            CityMap.useColor(use: 3, density: 4), CityMap.useColor(use: 1, density: 1),
        ])
        XCTAssertEqual(tiles[0].minX, 4 * 4_096)
        XCTAssertEqual(tiles[0].minY, 5 * 4_096)
        XCTAssertEqual(tiles[0].maxX, 5 * 4_096)
        // Only what is in view.
        XCTAssertEqual(map.tiles(for: .landUse, in: WorldRegion(minX: 0, minY: 0, maxX: 20_000, maxY: 30_000)).count, 1)
        // Merged into blocks of 8: the four of row 5 make one block, homes
        // being most (2 of 4), of their average density (1 + 2 + 4 + 4) / 4.
        let blocks = map.tiles(for: .landUse, in: Self.everywhere, blockSize: 8)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].color, CityMap.useColor(use: 1, density: 3))
        XCTAssertEqual(blocks[0].maxX - blocks[0].minX, 8 * 4_096)
        XCTAssertEqual(CityMap.blockSize(pointsPerUnit: 1), 1)
        XCTAssertEqual(CityMap.blockSize(pointsPerUnit: 6.0 / 4_096 / 3), 4)
    }

    func testLandValueAndCoverageLayers() throws {
        let world = try world()
        let map = CityMap(world: world)
        // The land's cells only (no service is measured yet, so no empty
        // cell is worth more than 1,000).
        let values = map.tiles(for: .landValue, in: Self.everywhere)
        XCTAssertEqual(values.map(\.value), [2_000, 2_500, 6_000, 7_000, 2_000])
        XCTAssertEqual(values.map(\.color), [2_000, 2_500, 6_000, 7_000, 2_000].map { CityMap.valueColor(cents: $0) })
        XCTAssertEqual(CityMap.valueStep(cents: 1_999), 0)
        XCTAssertEqual(CityMap.valueStep(cents: 2_000), 1)
        XCTAssertEqual(CityMap.valueStep(cents: 27_000), 8)
        // Coverage: Alpha's 800 m reaches row 5's cells; the home at row
        // 20, column 30 is reached by none.
        let coverage = map.tiles(for: .coverage, in: Self.everywhere)
        XCTAssertEqual(coverage.filter { $0.color == CityMap.uncoveredColor }.map { $0.minX / 4_096 }, [30])
        XCTAssertEqual(coverage.filter { $0.color == CityMap.coveredColor }.count, 4)
        XCTAssertGreaterThan(coverage.filter { $0.color == CityMap.coveredEmptyColor }.count, 100)
        // Blocks with an unreached home are unreached.
        let blocks = map.tiles(for: .coverage, in: Self.everywhere, blockSize: 32)
        XCTAssertEqual(blocks.map(\.color), [CityMap.uncoveredColor])
        XCTAssertTrue(map.tiles(for: .population, in: Self.everywhere).isEmpty)
        // A closed station reaches no one (decision 77): every peopled cell
        // is unreached.
        var closed = world
        try closed.setStationOperationMode(StationID(rawValue: 1), to: .closed)
        let unreached = CityMap(world: closed).tiles(for: .coverage, in: Self.everywhere)
        XCTAssertEqual(unreached.map(\.color), Array(repeating: CityMap.uncoveredColor, count: 5))
    }

    func testTheTappedCellsTooltip() throws {
        var world = try world()
        let info = try XCTUnwrap(world.cityCellInfo(atX: 5 * 4_096 + 10, y: 5 * 4_096 + 10))
        XCTAssertEqual(info.lines(in: .english), [
            "Homes · D2 (6 storeys)", "Residents 100 · Jobs 0", "Land value $ 25.00 a m²",
            "Base $ 25.00 · Service + $ 0.00 · Access + $ 0.00", "No station adds to it",
        ])
        XCTAssertEqual(info.lines(in: .traditionalChinese), [
            "住宅 · D2（6 層）", "居民 100 人 · 就業 0 個", "地價 每平方公尺 $ 25.00",
            "基準 $ 25.00 · 服務 + $ 0.00 · 可達 + $ 0.00", "沒有車站影響地價",
        ])
        XCTAssertEqual(world.cityCellInfo(atX: 7 * 4_096, y: 5 * 4_096)?.lines(in: .traditionalChinese).first, "辦公 · 既有存量")
        XCTAssertEqual(world.cityCellInfo(atX: 0, y: 0)?.lines(in: .english).first, "Empty land")
        XCTAssertEqual(world.cityCellInfo(atX: 0, y: 0)?.lines(in: .traditionalChinese).first, "空地")
        XCTAssertNil(world.cityCellInfo(atX: -1, y: 0))
        XCTAssertNil(world.cityCellInfo(atX: 131_072, y: 0))
        world.setCityBuildings(false)
        XCTAssertEqual(world.cityCellInfo(atX: 5 * 4_096, y: 5 * 4_096)?.lines(in: .english).first, "Homes")
    }

    /// A served station sets its catchment's premiums: the tooltip names
    /// it, and the panel's average follows.
    func testAServedStationsCatchment() throws {
        var world = GameWorld.newGame()
        let station = try world.buildStation(named: "Middle", at: PlanPoint(x: 524_288, y: 524_288)).id
        let before = try XCTUnwrap(world.catchmentLandValue(of: station))
        XCTAssertEqual(world.catchmentLandValueText(of: station, in: .english), "Average land value within 800 m: \(Money(before).centsText) a m²")
        XCTAssertEqual(world.catchmentLandValueText(of: station, in: .traditionalChinese), "腹地平均地價：每平方公尺 \(Money(before).centsText)")
        XCTAssertNil(world.catchmentLandValueText(of: StationID(rawValue: 99), in: .english))
        // The average is of every cell within 800 m, worked out again.
        var total: Int64 = 0, count: Int64 = 0
        for row in 0..<256 {
            for column in 0..<256 {
                let dx = Int64(column) * 4_096 + 2_048 - 524_288, dy = Int64(row) * 4_096 + 2_048 - 524_288
                guard dx * dx + dy * dy < 51_200 * 51_200 else { continue }
                total += world.landValue(row: row, column: column)!.value
                count += 1
            }
        }
        XCTAssertEqual(before, total / count)
        try world.setLand([])
        XCTAssertNil(world.catchmentLandValueText(of: station, in: .english), "no land, no line")
    }

    /// How long a whole map's land value takes for Taipei's new game
    /// (anchor 25.047882, 121.517219), for the record: printed, not
    /// asserted (a debug build on whatever machine runs it).
    func testTaipeisWholeMapIsWorkedOutOnce() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        let places = try PlaceGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json")))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.047882, longitudeDegrees: 121.517219))
        let cells = try XCTUnwrap(LandImport.cells(
            population: population, places: places, frame: RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds), bounds: GameWorld.newGameBounds
        ))
        var world = GameWorld.newGame(anchor: anchor, land: cells)
        for (index, dx) in [Int64(-30_000), 0, 30_000].enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 524_288 + dx, y: 524_288))
        }
        let start = ContinuousClock.now
        let map = CityMap(world: world)
        let elapsed = ContinuousClock.now - start
        print("CityMap for Taipei: \(map.rows * map.columns) cells in \(elapsed)")
        XCTAssertEqual(map.rows * map.columns, 65_536)
        XCTAssertFalse(map.tiles(for: .landValue, in: WorldRegion(minX: 500_000, minY: 500_000, maxX: 550_000, maxY: 550_000)).isEmpty)
    }
}
