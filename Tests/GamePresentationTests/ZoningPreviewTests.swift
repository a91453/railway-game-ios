@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 522: a zoning drag greys the cells no station reaches before
/// the finger lifts, and the zoning mode opens on the use the city wants
/// most until the player picks one.
@MainActor
final class ZoningPreviewTests: XCTestCase {
    private let cell = Land.cellLength

    /// A new game with one station at the middle of row 6, column 6, in a
    /// corner no town has reached.
    private func world() throws -> (world: GameWorld, station: StationID) {
        var world = GameWorld.newGame()
        let station = try world.buildStation(named: "Corner", at: PlanPoint(x: 6 * cell + cell / 2, y: 6 * cell + cell / 2)).id
        return (world, station)
    }

    /// Every cell the runs cover, by row and then column.
    private func cells(_ runs: [CellRectangle]) -> [CellPosition] {
        runs.flatMap { run in run.rows.flatMap { row in run.columns.map { CellPosition(row: row, column: $0) } } }
    }

    func testTheGreyCellsAreTheOnesNoStationReaches() throws {
        var (world, _) = try world()
        // A second station 20 cells east, and one at a cell's corner, so
        // reaches overlap and cut rows at odd places.
        _ = try world.buildStation(named: "East", at: PlanPoint(x: 26 * cell + cell / 2, y: 7 * cell + 100))
        _ = try world.buildStation(named: "Corner2", at: PlanPoint(x: 15 * cell, y: 20 * cell))
        let rectangle = CellRectangle(rows: 0...30, columns: 0...40)
        try world.setZone(.residential, rows: rectangle.rows, columns: rectangle.columns)
        let session = GameSession(world: world, language: .english)
        let runs = session.cellsOutOfReach(in: rectangle)
        // Checked cell by cell against the zoning layer's own rule.
        let outlook = ZoningOutlook(world: session.world)
        var expected: [CellPosition] = []
        for row in rectangle.rows {
            for column in rectangle.columns {
                let middle = PlanPoint(x: Int64(column) * cell + cell / 2, y: Int64(row) * cell + cell / 2)
                let reached = session.world.stations.contains {
                    let dx = middle.x - $0.location.x, dy = middle.y - $0.location.y
                    return dx * dx + dy * dy < Land.catchmentRadius * Land.catchmentRadius
                }
                if !reached { expected.append(CellPosition(row: row, column: column)) }
                if let kind = outlook.outlook(row: row, column: column, zone: .residential, in: session.world) {
                    XCTAssertEqual(kind == .tooFar, !reached, "row \(row), column \(column)")
                }
            }
        }
        XCTAssertEqual(cells(runs), expected)
        XCTAssertFalse(expected.isEmpty)
        XCTAssertLessThan(expected.count, rectangle.count)
        // Runs, not cells: each row is cut into at most a few.
        XCTAssertLessThan(runs.count, 4 * rectangle.rows.count)
    }

    func testTheDragGreysOnlyWhenZoningForAUse() throws {
        let (world, _) = try world()
        let session = GameSession(world: world, language: .english)
        session.choose(.zoning)
        session.zoningZone = .commercial
        // Row 6 from column 6 (the station) to column 25. 800 m is 12.5
        // cells: column 18 is reached, columns 19 on are not.
        session.dragZone(from: PlanPoint(x: 6 * cell + 10, y: 6 * cell + 10), to: PlanPoint(x: 25 * cell + 10, y: 6 * cell + 10))
        XCTAssertEqual(session.buildingOverlay?.zoneDragOutOfReach, [CellRectangle(rows: 6...6, columns: 19...25).planRect])
        session.zoningZone = .noDevelopment
        XCTAssertEqual(session.buildingOverlay?.zoneDragOutOfReach, [], "keeping the city off: nothing to warn of")
        session.zoningZone = nil
        XCTAssertEqual(session.buildingOverlay?.zoneDragOutOfReach, [], "clearing")
        session.cancelZoneDrag()
        XCTAssertNil(session.buildingOverlay?.zoneDrag)
        XCTAssertEqual(session.buildingOverlay?.zoneDragOutOfReach, [])
    }

    func testAMapWithNoStationGreysTheWholeDrag() throws {
        let session = GameSession(world: GameWorld.newGame(), language: .english)
        let rectangle = CellRectangle(rows: 2...5, columns: 3...9)
        let runs = session.cellsOutOfReach(in: rectangle)
        XCTAssertEqual(runs.count, 4)
        XCTAssertEqual(cells(runs).count, rectangle.count)
    }

    /// The zone the rule picks from `levels`: the highest of homes, shops
    /// and work, in that order on a tie; public facilities when all are
    /// below zero.
    private func expectedZone(_ levels: CityDemand.Levels) -> Zone {
        let best = max(levels.homes, levels.shops, levels.work)
        if best < 0 { return .civic }
        return levels.homes == best ? .residential : levels.shops == best ? .commercial : .office
    }

    func testTheZoningModeOpensOnTheUseTheCityWantsMost() throws {
        var (world, _) = try world()
        XCTAssertNotNil(world.cityDemand)
        XCTAssertNotNil(world.townGrowth)
        // Land well past the corner, with residents and jobs, so the city
        // has a mix to compare with its baseline.
        world.addLand(LandCell(row: 40, column: 40, use: .residential, residents: 400, jobs: 0))
        world.addLand(LandCell(row: 40, column: 41, use: .commercial, residents: 0, jobs: 60))
        world.addLand(LandCell(row: 40, column: 42, use: .office, residents: 0, jobs: 300))
        var seen: Set<Zone> = []
        let mixes = [
            CityMix(shopJobs: 0, workJobs: 0),
            CityMix(shopJobs: 2 * CityDemand.perResidents, workJobs: 0),
            CityMix(shopJobs: 0, workJobs: 4 * CityDemand.perResidents),
            CityMix(shopJobs: CityDemand.perResidents / 10, workJobs: CityDemand.perResidents * 3 / 4),
        ]
        for mix in mixes {
            world.cityDemand = CityDemand(baseline: mix)
            let session = GameSession(world: world, language: .english)
            let levels = session.world.cityDemandLevels
            let zone = expectedZone(levels)
            seen.insert(zone)
            XCTAssertEqual(session.suggestedZoningZone, zone, "\(levels)")
            session.choose(.zoning)
            XCTAssertEqual(session.zoningZone, zone, "opens on it")
        }
        XCTAssertTrue(seen.contains { $0 != .residential }, "not always homes: \(seen)")
    }

    func testAZoneThePlayerPicksStays() throws {
        var (world, _) = try world()
        world.addLand(LandCell(row: 40, column: 40, use: .residential, residents: 400, jobs: 0))
        world.cityDemand = CityDemand(baseline: CityMix(shopJobs: 0, workJobs: 4 * CityDemand.perResidents))
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.suggestedZoningZone, .office, "\(session.world.cityDemandLevels)")
        session.choose(.zoning)
        XCTAssertEqual(session.zoningZone, .office)
        // Away and back without picking: suggested again.
        session.choose(.building)
        session.choose(.zoning)
        XCTAssertEqual(session.zoningZone, .office)
        // Picked: kept, even when the tool is left and opened again.
        session.zoningZone = .leisure
        session.choose(.building)
        session.choose(.zoning)
        XCTAssertEqual(session.zoningZone, .leisure)
    }

    func testWhereTheDemandSteersNothingItOpensOnHomes() throws {
        var (world, _) = try world()
        world.addLand(LandCell(row: 40, column: 40, use: .residential, residents: 400, jobs: 0))
        world.cityDemand = CityDemand(baseline: CityMix(shopJobs: 0, workJobs: 4 * CityDemand.perResidents))
        world.townGrowth = nil
        let session = GameSession(world: world, language: .english)
        XCTAssertEqual(session.suggestedZoningZone, .residential)
        session.choose(.zoning)
        XCTAssertEqual(session.zoningZone, .residential)
    }
}
