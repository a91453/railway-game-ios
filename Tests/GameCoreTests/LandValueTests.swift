import Foundation
@testable import GameCore
import XCTest

/// Land value (Phase 6c-3, ARCHITECTURE decision 76): what a cell is worth,
/// worked out when asked from its use, its building's density and the best
/// station's last measured service.
final class LandValueTests: XCTestCase {
    /// A small world: 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)

    private static func point(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * 4_096 + 2_048, y: Int64(row) * 4_096 + 2_048)
    }

    /// A managed world whose land sets ridership, with the city's buildings
    /// and town growth on, `cells` of land and stations at `points`, each
    /// measured at `service` and `reached`.
    private func world(_ cells: [LandCell], stations points: [PlanPoint], service: [Int64], reached: [Int64], bounds: WorldBounds = small) throws -> GameWorld {
        var world = GameWorld(bounds: bounds, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.setLand(cells)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        world.setCityBuildings(true)
        for (index, point) in points.enumerated() {
            try world.buildStation(named: "S\(index)", at: point)
        }
        world.growLand(reached: [:])
        // The measures a midnight would have left.
        for index in world.townGrowth!.places.indices {
            let station = world.townGrowth!.places[index].station.rawValue - 1
            world.townGrowth!.places[index].lastService = service[station]
            world.townGrowth!.places[index].lastReached = reached[station]
        }
        return world
    }

    // MARK: - An independent reading of the rules

    private static func reference(_ world: GameWorld, row: Int, column: Int) -> LandValue? {
        let rows = Int((world.bounds.height + 4_095) / 4_096), columns = Int((world.bounds.width + 4_095) / 4_096)
        guard row >= 0, column >= 0, row < rows, column < columns else { return nil }
        let uses: [LandUse: Int64] = [.residential: 2_000, .commercial: 3_000, .office: 3_500]
        let factors: [Int64] = [1_000, 1_250, 1_600, 2_000]
        var b: Int64 = 1_000, d: Int64 = 1_000
        if let building = world.buildings.all.first(where: { $0.cells.contains(CellPosition(row: row, column: column)) }) {
            b = uses[building.use]!
            d = factors[building.density.rawValue - 1]
        } else if let cell = world.land.cells.first(where: { $0.row == row && $0.column == column }) {
            b = uses[cell.use]!
        }
        let base = b * d / 1_000
        var s: Int64 = 0, a: Int64 = 0
        var station: StationID?
        if world.landDemand, world.accounts.mode == .management, let growth = world.townGrowth {
            for place in growth.places.sorted(by: { $0.station < $1.station }) where place.lastService > 0 {
                let location = world.stations.first { $0.id == place.station }!.location
                let dx = Int64(column) * 4_096 + 2_048 - location.x, dy = Int64(row) * 4_096 + 2_048 - location.y
                let d2 = dx * dx + dy * dy, r2: Int64 = 51_200 * 51_200
                guard d2 < r2 else { continue }
                let score = (1_000 - d2 * 1_000 / r2) * place.lastService / 1_000
                if station == nil || score > s {
                    s = score
                    a = place.lastReached
                    station = place.station
                }
            }
        }
        let total = min(50_000, max(500, base + 15 * s + 1_000 * a))
        return LandValue(value: total, base: base, servicePremium: 15 * s, accessPremium: 1_000 * a, station: station)
    }

    // MARK: - The study's examples

    func testTheStudysExamples() throws {
        // D2 homes 400 m (25,600 units) from a station that served 800
        // thousandths and reached 3: w = 1000 − 250 = 750, S = 600,
        // base 2000 × 1250 / 1000 = 2500, 2500 + 9000 + 3000 = 14,500.
        let home = LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0)
        var station = Self.point(row: 5, column: 5)
        station = PlanPoint(x: station.x + 25_600, y: station.y)
        var world = try world([home], stations: [station], service: [800], reached: [3])
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d2)
        XCTAssertEqual(world.landValue(row: 5, column: 5), LandValue(value: 14_500, base: 2_500, servicePremium: 9_000, accessPremium: 3_000, station: StationID(rawValue: 1)))
        // No service: its base, 2,500.
        world = try self.world([home], stations: [station], service: [0], reached: [3])
        XCTAssertEqual(world.landValue(row: 5, column: 5), LandValue(value: 2_500, base: 2_500, servicePremium: 0, accessPremium: 0, station: nil))
        // D4 offices at a fully served station reaching 5: 7000 + 15000 + 5000.
        let office = LandCell(row: 5, column: 5, use: .office, residents: 0, jobs: 1_600)
        world = try self.world([office], stations: [Self.point(row: 5, column: 5)], service: [1_000], reached: [5])
        XCTAssertEqual(world.landValue(row: 5, column: 5), LandValue(value: 27_000, base: 7_000, servicePremium: 15_000, accessPremium: 5_000, station: StationID(rawValue: 1)))
    }

    func testTheCatchmentEdgeIsStrict() throws {
        // A station exactly 800 m east of a cell's middle (d² = R²) does
        // not reach it; one unit nearer it does, at weight 1.
        let middle = Self.point(row: 5, column: 5)
        // Homes at the station's own cell give it ridership to measure.
        let homes = [LandCell(row: 5, column: 18, use: .residential, residents: 100, jobs: 0)]
        var world = try world(homes, stations: [PlanPoint(x: middle.x + 51_200, y: middle.y)], service: [1_000], reached: [2])
        XCTAssertEqual(world.landValue(row: 5, column: 5), LandValue(value: 1_000, base: 1_000, servicePremium: 0, accessPremium: 0, station: nil))
        world = try self.world(homes, stations: [PlanPoint(x: middle.x + 51_199, y: middle.y)], service: [1_000], reached: [2])
        // w = 1000 − floor(51199² × 1000 / 51200²) = 1000 − 999 = 1: S = 1.
        XCTAssertEqual(world.landValue(row: 5, column: 5), LandValue(value: 3_015, base: 1_000, servicePremium: 15, accessPremium: 2_000, station: StationID(rawValue: 1)))
    }

    func testTheBestStationSetsItAndATieGoesToTheLower() throws {
        let middle = Self.point(row: 5, column: 5)
        let west = PlanPoint(x: middle.x - 10_000, y: middle.y), east = PlanPoint(x: middle.x + 10_000, y: middle.y)
        // Homes 320 m south that both stations share, for ridership.
        let homes = [LandCell(row: 10, column: 5, use: .residential, residents: 100, jobs: 0)]
        // The same distance and service: the lower station, its reach.
        var world = try world(homes, stations: [east, west], service: [900, 900], reached: [1, 4])
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.station, StationID(rawValue: 1))
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.accessPremium, 1_000)
        // The better served one wins, though it reaches less.
        world = try self.world(homes, stations: [east, west], service: [900, 950], reached: [4, 1])
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.station, StationID(rawValue: 2))
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.accessPremium, 1_000)
        XCTAssertEqual(world.landValue(row: 5, column: 5), Self.reference(world, row: 5, column: 5))
    }

    func testTheValueStaysWithinItsBounds() {
        XCTAssertEqual(LandValueRules.value(base: 0, service: 0, access: 0), 500)
        XCTAssertEqual(LandValueRules.value(base: 499, service: 0, access: 0), 500)
        XCTAssertEqual(LandValueRules.value(base: 7_000, service: 15_000, access: 5_000), 27_000)
        XCTAssertEqual(LandValueRules.value(base: 40_000, service: 15_000, access: 5_000), 50_000)
    }

    func testWithoutTheLandSettingRidershipOnlyTheBaseCounts() throws {
        let home = LandCell(row: 5, column: 5, use: .commercial, residents: 0, jobs: 100)
        var world = try world([home], stations: [Self.point(row: 5, column: 5)], service: [1_000], reached: [5])
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.value, 3_750 + 15_000 + 5_000)
        var free = world
        free.setEconomyMode(.free)
        XCTAssertEqual(free.landValue(row: 5, column: 5), LandValue(value: 3_750, base: 3_750, servicePremium: 0, accessPremium: 0, station: nil))
        var off = world
        off.setLandDemand(false)
        XCTAssertEqual(off.landValue(row: 5, column: 5)?.value, 3_750)
        world.setTownGrowth(false)
        XCTAssertEqual(world.landValue(row: 5, column: 5)?.value, 3_750)
    }

    func testUsesAndDensitiesSetTheBase() throws {
        var world = try world([
            LandCell(row: 1, column: 1, use: .residential, residents: 56, jobs: 0),
            LandCell(row: 1, column: 2, use: .residential, residents: 400, jobs: 0),
            LandCell(row: 1, column: 3, use: .commercial, residents: 0, jobs: 1_000),
            LandCell(row: 1, column: 4, use: .office, residents: 0, jobs: 5_000),
        ], stations: [], service: [], reached: [])
        // D1 homes 2000; D3 homes 3200; D4 shops 6000; existing stock
        // offices (D4) 7000; an empty cell 1000.
        XCTAssertEqual((1...5).map { world.landValue(row: 1, column: $0)?.base }, [2_000, 3_200, 6_000, 7_000, 1_000])
        // Without buildings, the land's use at D 1000.
        world.setCityBuildings(false)
        XCTAssertEqual((1...5).map { world.landValue(row: 1, column: $0)?.base }, [2_000, 2_000, 3_000, 3_500, 1_000])
        // Outside the world, none.
        for (row, column) in [(-1, 0), (0, -1), (24, 0), (0, 32)] {
            XCTAssertNil(world.landValue(row: row, column: column))
        }
        XCTAssertNotNil(world.landValue(row: 23, column: 31))
        // Ranges wholly outside the world give none, past either end.
        XCTAssertEqual(world.landValues(rows: 30...40, columns: 0...3), [])
        XCTAssertEqual(world.landValues(rows: 0...3, columns: 40...50), [])
        XCTAssertEqual(world.landValues(rows: -5...(-1), columns: -5...(-1)), [])
        XCTAssertEqual(world.landValues(rows: 20...40, columns: 30...40).count, 4 * 2)
    }

    // MARK: - Every cell, against the reference

    func testEveryCellOfATownFollowsTheReference() throws {
        var world = GameWorld(bounds: .maximum, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.foundTowns(seed: 5)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        world.setCityBuildings(true)
        for (index, dx) in [Int64(0), 30_000, -45_000, 20_000].enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 524_288 + dx, y: 524_288 + dx / 3))
        }
        world.growLand(reached: [:])
        for (index, place) in world.townGrowth!.places.enumerated() {
            world.townGrowth!.places[index].lastService = [1_000, 640, 0, 999][place.station.rawValue - 1]
            world.townGrowth!.places[index].lastReached = [2, 5, 3, 0][place.station.rawValue - 1]
        }
        let values = world.landValues()
        let columns = Land.columns(in: world.bounds)
        XCTAssertEqual(values.count, Land.rows(in: world.bounds) * columns)
        // Every cell near the stations, and a sample of the rest.
        for row in 116...140 {
            for column in 110...146 {
                XCTAssertEqual(values[row * columns + column], Self.reference(world, row: row, column: column), "\(row), \(column)")
                XCTAssertEqual(world.landValue(row: row, column: column), values[row * columns + column])
            }
        }
        for index in stride(from: 0, to: values.count, by: 997) {
            XCTAssertEqual(values[index], Self.reference(world, row: index / columns, column: index % columns))
        }
        XCTAssertTrue(values.contains { $0.station == StationID(rawValue: 4) }, "the nearly fully served station sets some")
        XCTAssertFalse(values.contains { $0.station == StationID(rawValue: 3) }, "the unserved one sets none")
    }

    // MARK: - A query, not state

    func testAskingChangesNothingAndASaveGivesTheSameValues() throws {
        let home = LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0)
        let world = try world([home], stations: [Self.point(row: 5, column: 6)], service: [870], reached: [2])
        let asked = world
        _ = asked.landValue(row: 5, column: 5)
        _ = asked.landValues()
        XCTAssertEqual(asked, world)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(asked), try encoder.encode(world), "nothing is saved for it")
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world))
        XCTAssertEqual(loaded.landValues(), world.landValues())
        XCTAssertGreaterThan(loaded.landValue(row: 5, column: 5)?.servicePremium ?? 0, 0)
    }
}
