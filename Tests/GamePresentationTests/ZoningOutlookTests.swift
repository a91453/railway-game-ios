@testable import GameCore
import GamePresentation
import XCTest

/// Decision 514: the zoning layer tells each empty zoned cell's outlook
/// apart (will be built, waiting for its station, too far, not needed now),
/// as the city's growth rules decide it (decisions 98 and 139).
final class ZoningOutlookTests: XCTestCase {
    private let cell = Land.cellLength

    /// A new game with one station at the middle of a cell, in a corner of
    /// the map no town has reached, and the cell's row and column.
    private func world() throws -> (world: GameWorld, station: StationID, row: Int, column: Int) {
        var world = GameWorld.newGame()
        let row = 6, column = 6
        for r in 0...30 {
            for c in 0...30 { XCTAssertNil(world.land.cell(row: r, column: c), "the corner is empty") }
        }
        let station = try world.buildStation(named: "Corner", at: PlanPoint(x: Int64(column) * cell + cell / 2, y: Int64(row) * cell + cell / 2)).id
        return (world, station, row, column)
    }

    /// Station `id`'s town grew last night, `service` thousandths served.
    private func grow(_ id: StationID, in world: inout GameWorld, service: Int64 = 500) {
        var place = TownGrowth.Place(station: id, base: 100, counted: 0)
        place.lastService = service
        place.lastReached = 1
        var growth = world.townGrowth ?? TownGrowth()
        growth.places = [place]
        world.townGrowth = growth
    }

    func testEachOutlookFromTheStationTheTrainsAndTheDemand() throws {
        var (world, station, row, column) = try world()
        // Two cells east: in the 800 m catchment; 14 cells (896 m): out.
        try world.setZone(.residential, rows: row...row, columns: (column + 2)...(column + 2))
        try world.setZone(.residential, rows: row...row, columns: (column + 14)...(column + 14))
        var outlook = ZoningOutlook(world: world)
        XCTAssertEqual(outlook.outlook(row: row, column: column + 2, zone: .residential, in: world), .waitsForStation, "no one has ridden yet")
        XCTAssertEqual(outlook.outlook(row: row, column: column + 14, zone: .residential, in: world), .tooFar)

        grow(station, in: &world)
        outlook = ZoningOutlook(world: world)
        XCTAssertEqual(outlook.outlook(row: row, column: column + 2, zone: .residential, in: world), .builds)
        XCTAssertEqual(outlook.outlook(row: row, column: column + 14, zone: .residential, in: world), .tooFar, "growing does not reach further")
        XCTAssertEqual(outlook.counts(in: world), [.builds: 1, .tooFar: 1])

        // No service share served yesterday: it waits again.
        grow(station, in: &world, service: 0)
        XCTAssertEqual(ZoningOutlook(world: world).outlook(row: row, column: column + 2, zone: .residential, in: world), .waitsForStation)

        // A city that kept no shops: it has more than it wants.
        grow(station, in: &world)
        world.cityDemand = CityDemand(baseline: CityMix(shopJobs: 0, workJobs: 0))
        XCTAssertLessThan(world.cityDemandLevels.shops, 0)
        outlook = ZoningOutlook(world: world)
        XCTAssertEqual(outlook.outlook(row: row, column: column + 2, zone: .commercial, in: world), .notWanted)
        // Schools and sights are left alone by the valves.
        XCTAssertEqual(outlook.outlook(row: row, column: column + 2, zone: .civic, in: world), .builds)
        // Too far comes first: a station is what is missing.
        XCTAssertEqual(outlook.outlook(row: row, column: column + 14, zone: .commercial, in: world), .tooFar)
    }

    func testAClosedStationReachesNothingAndTheTownOffGrowsNothing() throws {
        var (world, station, row, column) = try world()
        grow(station, in: &world)
        world.townGrowth = nil
        XCTAssertEqual(ZoningOutlook(world: world).outlook(row: row, column: column + 2, zone: .residential, in: world), .waitsForStation)
        grow(station, in: &world)
        try world.setStationOperationMode(station, to: .closed)
        XCTAssertEqual(ZoningOutlook(world: world).outlook(row: row, column: column + 2, zone: .residential, in: world), .tooFar)
    }

    func testBuiltLandAndZonesThatKeepTheCityOffHaveNoOutlook() throws {
        var (world, station, row, column) = try world()
        grow(station, in: &world)
        let outlook = ZoningOutlook(world: world)
        XCTAssertNil(outlook.outlook(row: row, column: column + 2, zone: .noDevelopment, in: world))
        XCTAssertNil(outlook.outlook(row: row, column: column + 2, zone: .reserved, in: world))
        world.addLand(LandCell(row: row, column: column + 2, use: .residential, residents: 4, jobs: 0))
        XCTAssertNil(ZoningOutlook(world: world).outlook(row: row, column: column + 2, zone: .residential, in: world), "built on")
    }

    func testTheLayerMarksTheZonesAndATappedCellSaysWhy() throws {
        var (world, station, row, column) = try world()
        try world.setZone(.residential, rows: row...(row + 1), columns: (column + 1)...(column + 2))
        try world.setZone(.residential, rows: row...row, columns: (column + 14)...(column + 15))
        grow(station, in: &world)
        let map = CityMap(world: world)
        let all = WorldRegion(minX: 0, minY: 0, maxX: Double(world.bounds.width), maxY: Double(world.bounds.height))
        let marks = map.zoningMarks(in: all)
        XCTAssertEqual(marks.count, 6)
        XCTAssertEqual(marks.filter { $0.outlook == .builds }.count, 4)
        XCTAssertEqual(marks.filter { $0.outlook == .tooFar }.count, 2)
        let first = try XCTUnwrap(marks.first)
        XCTAssertEqual([first.minX, first.minY, first.maxX, first.maxY], [
            Double(Int64(column + 1) * cell), Double(Int64(row) * cell), Double(Int64(column + 2) * cell), Double(Int64(row + 1) * cell),
        ])
        XCTAssertEqual(first.outlook, .builds)
        // Zoomed out, 16 cells a block: the four that build share a block,
        // the two too far another.
        let blocks = map.zoningMarks(in: all, blockSize: 16)
        XCTAssertEqual(blocks.map(\.outlook), [.builds, .tooFar])
        // Nothing marked out of the region.
        XCTAssertTrue(map.zoningMarks(in: WorldRegion(minX: 0, minY: 0, maxX: 1_000, maxY: 1_000)).isEmpty)

        let x = Double(Int64(column + 14) * cell + cell / 2), y = Double(Int64(row) * cell + cell / 2)
        let info = try XCTUnwrap(world.cityCellInfo(atX: x, y: y))
        XCTAssertEqual(info.outlook, .tooFar)
        XCTAssertTrue(info.lines(in: .traditionalChinese).contains("離車站太遠：800 公尺內沒有車站：在附近蓋車站，或劃在車站旁邊。"))
        XCTAssertTrue(info.lines(in: .english).contains("Too far from a station: No station within 800 m: build one nearby, or zone closer to a station."))
    }

    @MainActor
    func testZoningSaysWhatWillNotBeBuilt() throws {
        var (world, station, row, column) = try world()
        grow(station, in: &world)
        let session = GameSession(world: world, language: .traditionalChinese)
        // Row 6, columns 3 to 21: 16 within 800 m of the station, 3 not.
        XCTAssertTrue(session.zone(CellRectangle(rows: row...row, columns: (column - 3)...(column + 15))))
        XCTAssertEqual(session.message?.text, "劃設住宅區 19 格。其中 3 格離車站太遠，不會蓋。")
        XCTAssertTrue(session.zone(CellRectangle(rows: row...row, columns: (column + 20)...(column + 21))))
        XCTAssertEqual(session.message?.text, "劃設住宅區 2 格。這裡離車站太遠，城市不會來蓋。")
        // All within reach and the town grows: nothing more to say.
        XCTAssertTrue(session.zone(CellRectangle(rows: (row + 1)...(row + 1), columns: column...(column + 3))))
        XCTAssertEqual(session.message?.text, "劃設住宅區 4 格。")
    }
}
