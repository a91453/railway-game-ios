import Foundation
@testable import GameCore
import XCTest

/// City buildings (Phase 6c-1, ARCHITECTURE decision 74): the table of
/// what each use and density holds, the building each cell gets, and the
/// buildings kept with the land as it is set, founded, grown and saved.
final class BuildingTests: XCTestCase {
    private static let middle: Int64 = 524_288

    private func world(bounds: WorldBounds = .maximum) -> GameWorld {
        GameWorld(bounds: bounds, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
    }

    // MARK: - An independent reading of the rules

    /// The study's table (§5.2) as written there: use, density, residents,
    /// jobs, floors.
    private static let table: [(LandUse, BuildingDensity, Int64, Int64, Int64)] = [
        (.residential, .d1, 56, 12, 2), (.residential, .d2, 168, 36, 6), (.residential, .d3, 504, 108, 18), (.residential, .d4, 1_120, 240, 40),
        (.commercial, .d1, 16, 72, 2), (.commercial, .d2, 48, 216, 6), (.commercial, .d3, 144, 648, 18), (.commercial, .d4, 320, 1_440, 40),
        (.office, .d1, 8, 84, 2), (.office, .d2, 24, 252, 6), (.office, .d3, 72, 756, 18), (.office, .d4, 160, 1_680, 40),
    ]

    private static func row(_ use: LandUse, _ density: BuildingDensity) -> (residents: Int64, jobs: Int64) {
        let row = table.first { $0.0 == use && $0.1 == density }!
        return (row.2, row.3)
    }

    /// The building a cell gets, from the table above: the first density
    /// whose main count (residents of homes, jobs of the rest) is enough,
    /// and the capacity it gives the cell.
    private static func reference(_ cell: LandCell) -> (kind: BuildingKind, density: BuildingDensity, capacity: BuildingCapacity) {
        let homes = cell.use == .residential
        for density in [BuildingDensity.d1, .d2, .d3, .d4] {
            let (residents, jobs) = row(cell.use, density)
            if homes ? residents >= cell.residents : jobs >= cell.jobs {
                let capacity = homes
                    ? BuildingCapacity(residents: residents, jobs: max(jobs, cell.jobs))
                    : BuildingCapacity(residents: max(residents, cell.residents), jobs: jobs)
                return (.city, density, capacity)
            }
        }
        let (residents, jobs) = row(cell.use, .d4)
        return (.existingStock, .d4, BuildingCapacity(residents: max(residents, cell.residents), jobs: max(jobs, cell.jobs)))
    }

    /// Checks every cell of `world`'s land has its building: numbered and
    /// fitted as the reference says, holding all who live and work there.
    private func assertBuildingsFit(_ world: GameWorld, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(world.cityBuildings, file: file, line: line)
        XCTAssertNil(world.buildingProblem(), file: file, line: line)
        XCTAssertEqual(world.buildings.all.count, world.land.cells.count, file: file, line: line)
        for cell in world.land.cells {
            guard let building = world.buildings.building(row: cell.row, column: cell.column),
                  let capacity = world.buildingCapacity(row: cell.row, column: cell.column)
            else { return XCTFail("no building at \(cell.row), \(cell.column)", file: file, line: line) }
            let expected = Self.reference(cell)
            XCTAssertEqual(building.use, cell.use, file: file, line: line)
            XCTAssertEqual(building.cells, [cell.position], file: file, line: line)
            XCTAssertEqual(building.kind, expected.kind, file: file, line: line)
            XCTAssertEqual(building.density, expected.density, file: file, line: line)
            XCTAssertEqual(capacity, expected.capacity, file: file, line: line)
            XCTAssertGreaterThanOrEqual(capacity.residents, cell.residents, file: file, line: line)
            XCTAssertGreaterThanOrEqual(capacity.jobs, cell.jobs, file: file, line: line)
        }
    }

    // MARK: - The table

    func testTheTableIsTheStudysRowByRow() {
        for (use, density, residents, jobs, floors) in Self.table {
            XCTAssertEqual(density.floors, floors)
            XCTAssertEqual(Building.tableCapacity(of: use, density), BuildingCapacity(residents: residents, jobs: jobs), "\(use) \(density)")
            // Worked out again: 1,536 m² a storey, 7, 2 or 1 eighths homes
            // at 48 m² a resident, the rest jobs at 32 m², with nothing
            // left over.
            let floor = 1_536 * floors
            let homes: Int64 = use == .residential ? 7 : use == .commercial ? 2 : 1
            XCTAssertEqual(floor * homes % (8 * 48), 0)
            XCTAssertEqual(floor * (8 - homes) % (8 * 32), 0)
            XCTAssertEqual(floor * homes / 8 / 48, residents)
            XCTAssertEqual(floor * (8 - homes) / 8 / 32, jobs)
        }
        XCTAssertEqual(Self.table.count, LandUse.allCases.count * BuildingDensity.allCases.count)
    }

    func testACellGetsTheLowestDensityHoldingItsMainCount() {
        // use, residents, jobs → kind, density, capacity
        let cases: [(LandUse, Int64, Int64, BuildingKind, BuildingDensity, Int64, Int64)] = [
            (.residential, 56, 12, .city, .d1, 56, 12),
            (.residential, 57, 0, .city, .d2, 168, 36),
            (.residential, 168, 36, .city, .d2, 168, 36),
            (.residential, 169, 0, .city, .d3, 504, 108),
            (.residential, 230, 30, .city, .d3, 504, 108), // the first town's fullest homes
            (.residential, 505, 0, .city, .d4, 1_120, 240),
            (.residential, 1_120, 0, .city, .d4, 1_120, 240),
            (.residential, 0, 5, .city, .d1, 56, 12), // jobs only: the main count is 0
            // A few jobs do not raise homes: their capacity is what is there.
            (.residential, 100, 500, .city, .d2, 168, 500),
            (.residential, 1_121, 300, .existingStock, .d4, 1_121, 300),
            (.residential, 2_000, 5, .existingStock, .d4, 2_000, 240),
            (.commercial, 16, 72, .city, .d1, 16, 72),
            (.commercial, 0, 73, .city, .d2, 48, 216),
            (.commercial, 65, 780, .city, .d4, 320, 1_440), // a town's core: 260 / 4 and 3 × 260
            (.commercial, 400, 100, .city, .d2, 400, 216),
            (.commercial, 10, 1_441, .existingStock, .d4, 320, 1_441),
            (.office, 160, 84, .city, .d1, 160, 84),
            (.office, 78, 285, .city, .d3, 78, 756), // Taipei's fullest office cell
            (.office, 65, 780, .city, .d4, 160, 1_680),
            (.office, 0, 1_681, .existingStock, .d4, 160, 1_681),
            (.office, 100_000, 100_000, .existingStock, .d4, 100_000, 100_000),
        ]
        for (use, residents, jobs, kind, density, residentCapacity, jobCapacity) in cases {
            let cell = LandCell(row: 3, column: 4, use: use, residents: residents, jobs: jobs)
            let building = Building.fitting(cell, id: BuildingID(rawValue: 9))
            let label = "\(use) \(residents) / \(jobs)"
            XCTAssertEqual(building.id, BuildingID(rawValue: 9))
            XCTAssertEqual(building.use, use)
            XCTAssertEqual(building.cells, [CellPosition(row: 3, column: 4)])
            XCTAssertEqual(building.kind, kind, label)
            XCTAssertEqual(building.density, density, label)
            XCTAssertEqual(building.capacity(on: cell), BuildingCapacity(residents: residentCapacity, jobs: jobCapacity), label)
            let reference = Self.reference(cell)
            XCTAssertEqual(reference.kind, kind, label)
            XCTAssertEqual(reference.density, density, label)
            XCTAssertEqual(reference.capacity, building.capacity(on: cell), label)
        }
    }

    // MARK: - Putting them up

    func testTurningThemOnPutsOneUpOnEveryCellKeepingEveryone() throws {
        for seed: UInt32 in [1, 5, 77] {
            var world = world()
            world.foundTowns(seed: seed)
            let land = world.land
            XCTAssertTrue(world.buildings.isEmpty, "off in a new world")
            XCTAssertNil(world.buildingCapacity(row: land.cells[0].row, column: land.cells[0].column))
            world.setCityBuildings(true)
            XCTAssertEqual(world.land, land, "no one is turned out or added")
            assertBuildingsFit(world)
            XCTAssertEqual(world.buildings.all.map(\.id.rawValue), Array(1...land.cells.count), "numbered by row and column")
            XCTAssertEqual(world.buildings.all.map { $0.cells[0] }, land.cells.map(\.position))
        }
        // Seed 1 on a new game's map: its three towns' cells by density.
        var world = world()
        world.foundTowns(seed: 1)
        world.setCityBuildings(true)
        XCTAssertEqual(Self.densities(world), Self.expectedSeedOne)
    }

    /// Seed 1's three towns on the largest map (887 cells): how many cells
    /// get each density (homes, shops, offices) and existing stock.
    private static let expectedSeedOne = DensityCount(residential: [200, 416, 168, 0], commercial: [0, 0, 18, 33], office: [0, 0, 47, 5], existingStock: 0)

    struct DensityCount: Equatable {
        var residential: [Int]
        var commercial: [Int]
        var office: [Int]
        var existingStock: Int
    }

    private static func densities(_ world: GameWorld) -> DensityCount {
        var count = DensityCount(residential: [0, 0, 0, 0], commercial: [0, 0, 0, 0], office: [0, 0, 0, 0], existingStock: 0)
        for building in world.buildings.all {
            guard building.kind == .city else {
                count.existingStock += 1
                continue
            }
            let index = building.density.rawValue - 1
            switch building.use {
            case .residential: count.residential[index] += 1
            case .commercial: count.commercial[index] += 1
            case .office: count.office[index] += 1
            }
        }
        return count
    }

    func testTurningThemOffTakesThemDownAndOnPutsThemUpAgain() {
        var world = world()
        world.foundTowns(seed: 1)
        world.setCityBuildings(true)
        let on = world
        world.setCityBuildings(true)
        XCTAssertEqual(world, on, "already on: nothing changes")
        world.setCityBuildings(false)
        XCTAssertFalse(world.cityBuildings)
        XCTAssertTrue(world.buildings.isEmpty)
        XCTAssertNil(world.buildingCapacity(at: PlanPoint(x: Self.middle, y: Self.middle)))
        XCTAssertEqual(world.land, on.land)
        world.setCityBuildings(true)
        XCTAssertEqual(world, on, "the same buildings, numbered the same")
    }

    func testSetLandAndFoundTownsBringTheirBuildings() throws {
        var world = world(bounds: try WorldBounds(width: 40_000, height: 40_000))
        world.setCityBuildings(true)
        XCTAssertTrue(world.buildings.isEmpty, "no land, no buildings")
        let cells = [
            LandCell(row: 2, column: 0, use: .office, residents: 78, jobs: 285),
            LandCell(row: 0, column: 3, use: .residential, residents: 57, jobs: 0),
            LandCell(row: 0, column: 1, use: .commercial, residents: 10, jobs: 2_000),
        ]
        try world.setLand(cells)
        assertBuildingsFit(world)
        XCTAssertEqual(world.buildings.all.map { $0.cells[0] }, [CellPosition(row: 0, column: 1), CellPosition(row: 0, column: 3), CellPosition(row: 2, column: 0)])
        XCTAssertEqual(world.buildings.all.map(\.kind), [.existingStock, .city, .city])
        XCTAssertEqual(world.buildingCapacity(at: PlanPoint(x: 4_096 + 100, y: 4_000)), BuildingCapacity(residents: 320, jobs: 2_000))
        XCTAssertNil(world.buildingCapacity(row: 0, column: 0), "no one there, no building")
        XCTAssertNil(world.buildingCapacity(at: PlanPoint(x: -1, y: 0)))

        // Refused land changes neither the land nor the buildings.
        let before = world
        for bad in [
            [LandCell(row: 0, column: 0, use: .office, residents: 1, jobs: 1), LandCell(row: 0, column: 0, use: .office, residents: 1, jobs: 1)],
            [LandCell(row: 0, column: 10, use: .office, residents: 1, jobs: 1)],
            [LandCell(row: 0, column: 0, use: .office, residents: 0, jobs: 0)],
        ] {
            XCTAssertThrowsError(try world.setLand(bad)) { XCTAssertEqual($0 as? GameError, .invalidLand) }
            XCTAssertEqual(world, before)
        }

        // New land is numbered from 1 again; none takes them all down.
        try world.setLand([LandCell(row: 1, column: 1, use: .residential, residents: 4, jobs: 0)])
        XCTAssertEqual(world.buildings.all, [Building(id: BuildingID(rawValue: 1), kind: .city, use: .residential, density: .d1, cells: [CellPosition(row: 1, column: 1)])])
        try world.setLand([])
        XCTAssertTrue(world.buildings.isEmpty)
        XCTAssertTrue(world.cityBuildings)

        var towns = self.world()
        towns.setCityBuildings(true)
        towns.foundTowns(seed: 3)
        assertBuildingsFit(towns)
        towns.setCityBuildings(false)
        towns.foundTowns(seed: 4)
        XCTAssertTrue(towns.buildings.isEmpty, "off, towns come without buildings")
    }

    // MARK: - Growth

    /// A world whose land sets its stations' ridership and grows round
    /// them, with town growth having seen them once.
    private func growingWorld(buildings: Bool) throws -> GameWorld {
        var world = world()
        world.foundTowns(seed: 1)
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        world.setCityBuildings(buildings)
        for (index, x) in [Self.middle, Self.middle + 40_000].enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: x, y: Self.middle))
        }
        world.growLand(reached: [:])
        for index in world.passengers.indices {
            world.passengers[index].arrived += world.passengers[index].demand!.dailyTrips
        }
        return world
    }

    func testGrowthBuildsANewCellsHomesWithIt() throws {
        var world = try growingWorld(buildings: true)
        let before = world.land
        let reached: [StationID: Int] = [StationID(rawValue: 1): 1, StationID(rawValue: 2): 1]
        world.growLand(reached: reached)
        let added = world.land.cells.filter { before.cell(row: $0.row, column: $0.column) == nil }
        XCTAssertEqual(added.count, 2, "each growing station built a cell")
        for (offset, cell) in added.sorted(by: { world.buildings.building(row: $0.row, column: $0.column)!.id < world.buildings.building(row: $1.row, column: $1.column)!.id }).enumerated() {
            XCTAssertEqual(cell.use, .residential)
            XCTAssertEqual(cell.residents, LandDemand.newCellResidents)
            XCTAssertEqual(world.buildings.building(row: cell.row, column: cell.column),
                           Building(id: BuildingID(rawValue: before.cells.count + 1 + offset), kind: .city, use: .residential, density: .d1, cells: [cell.position]))
            XCTAssertEqual(world.buildingCapacity(row: cell.row, column: cell.column), BuildingCapacity(residents: 56, jobs: 12))
        }
        XCTAssertNil(world.buildingProblem(), "every cell with people has its building")
        XCTAssertEqual(world.buildings.all.map(\.id.rawValue), Array(1...world.land.cells.count))
    }

    func testGrowthBuildsNoCellWhenNoBuildingNumberIsLeft() throws {
        var world = try growingWorld(buildings: true)
        // Buildings that reached the last number (as a save may hold).
        var numbered = CityBuildings()
        for building in world.buildings.all {
            let id = building.id == world.buildings.all.last?.id ? BuildingID(rawValue: .max) : building.id
            numbered.append(Building(id: id, kind: building.kind, use: building.use, density: building.density, cells: building.cells))
        }
        world.buildings = numbered
        XCTAssertNil(world.buildingProblem())
        XCTAssertNil(world.buildings.nextID)
        let cells = world.land.cells.count
        world.growLand(reached: [StationID(rawValue: 1): 1, StationID(rawValue: 2): 1])
        XCTAssertEqual(world.land.cells.count, cells, "no cell without its building")
        XCTAssertNil(world.buildingProblem())
    }

    /// A served line through the first town, with the city's buildings on:
    /// the land and its buildings grow the same whether advanced a day at
    /// a time, minute by minute, or saved and loaded on the way
    /// (`CityGrowthTests` also slices the days and idles over midnight).
    func testTheCityGrowsTheSameHoweverTheDaysAreAdvanced() throws {
        func start(buildings: Bool) throws -> GameWorld {
            var start = world()
            start.foundTowns(seed: 1)
            start.setEconomyMode(.management)
            start.setLandDemand(true)
            start.setTownGrowth(true)
            start.setCityBuildings(buildings)
            let a = try start.buildTrackNode(at: WorldCoordinate(x: Self.middle - 40_960, y: Self.middle))
            let b = try start.buildTrackNode(at: WorldCoordinate(x: Self.middle + 40_960, y: Self.middle))
            let edge = try start.buildTrackEdge(from: a, to: b)
            let west = try start.buildStation(named: "West", at: PlanPoint(x: Self.middle - 30_720, y: Self.middle)).id
            let east = try start.buildStation(named: "East", at: PlanPoint(x: Self.middle + 30_720, y: Self.middle)).id
            try start.addTrackPlatform(west, on: edge, from: 8_192, to: 12_288)
            try start.addTrackPlatform(east, on: edge, from: 69_632, to: 73_728)
            let line = try start.createLine(named: "L", stops: [west, east]).id
            try start.setLineServiceWindow(line, to: .allDay)
            try start.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
            let train = try start.purchaseTrain(named: "T").id
            try start.setTrainCars(train, to: 4)
            try start.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: 12_288))
            try start.setTrainContinuation(train, along: [], stoppingAt: 12_288)
            try start.setTrainMovementRate(train, to: 512)
            try start.assignTrain(train, to: line)
            return start
        }
        let first = try start(buildings: true)
        let days: Int = 3
        var daily = first
        for _ in 0..<days { try daily.advance(ticks: 1_440) }
        var minutes = first
        for _ in 0..<(days * 1_440) { try minutes.advance(ticks: 1) }
        var saved = first
        try saved.advance(ticks: 1_000)
        saved = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(saved))
        try saved.advance(ticks: days * 1_440 - 1_000)
        XCTAssertEqual(minutes, daily)
        XCTAssertEqual(saved, daily)
        XCTAssertGreaterThan(daily.land.cells.count, first.land.cells.count, "a served town spreads")
        XCTAssertNil(daily.buildingProblem())
        XCTAssertEqual(daily.buildings.all.count, daily.land.cells.count)
    }

    // MARK: - Saving

    func testBuildingsSaveAsRunsAndReadBackTheSame() throws {
        var world = world(bounds: try WorldBounds(width: 40_000, height: 40_000))
        try world.setLand([
            LandCell(row: 0, column: 1, use: .residential, residents: 4, jobs: 0),
            LandCell(row: 0, column: 2, use: .residential, residents: 60, jobs: 0),
            LandCell(row: 0, column: 3, use: .residential, residents: 2_000, jobs: 0),
            LandCell(row: 0, column: 4, use: .residential, residents: 300, jobs: 0),
            LandCell(row: 0, column: 5, use: .office, residents: 2, jobs: 300),
            LandCell(row: 1, column: 0, use: .commercial, residents: 0, jobs: 6),
        ])
        world.setCityBuildings(true)
        let data = try JSONEncoder().encode(world.buildings)
        let runs = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(runs.count, 5)
        XCTAssertEqual(runs[0]["id"] as? Int, 1)
        XCTAssertEqual(runs[0]["density"] as? [Int], [1, 2])
        XCTAssertNil(runs[0]["kind"], "city buildings leave out their kind")
        XCTAssertEqual(runs[1]["kind"] as? String, "existingStock")
        XCTAssertEqual(runs[1]["column"] as? Int, 3)
        XCTAssertEqual(runs[2]["id"] as? Int, 4)
        XCTAssertEqual(runs[2]["density"] as? [Int], [3])
        XCTAssertEqual(runs[3]["use"] as? String, "office")
        XCTAssertEqual(runs[4]["row"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(CityBuildings.self, from: data), world.buildings)
        let saved = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(object["cityBuildings"] as? Bool, true)
        XCTAssertNotNil(object["buildings"])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: saved), world)

        // On with no land: the switch alone. Off: neither.
        try world.setLand([])
        let empty = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertEqual(empty["cityBuildings"] as? Bool, true)
        XCTAssertNil(empty["buildings"])
        world.setCityBuildings(false)
        let off = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(off["cityBuildings"])
        XCTAssertNil(off["buildings"])
    }

    func testBadSavedBuildingsAreRefused() throws {
        func decode(_ json: String) throws -> CityBuildings {
            try JSONDecoder().decode(CityBuildings.self, from: Data(json.utf8))
        }
        XCTAssertNoThrow(try decode(#"[{"id":1,"row":0,"column":0,"use":"office","density":[1,4]},{"id":5,"row":0,"column":2,"use":"office","density":[4],"kind":"existingStock"}]"#))
        let bad = [
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[]}]"#,
            #"[{"id":0,"row":0,"column":0,"use":"office","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[0]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[5]}]"#,
            #"[{"id":1,"row":-1,"column":0,"use":"office","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":-1,"use":"office","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"farm","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[1],"kind":"tower"}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[3],"kind":"existingStock"}]"#,
            #"[{"id":2,"row":0,"column":0,"use":"office","density":[1]},{"id":1,"row":0,"column":1,"use":"office","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"office","density":[1,1]},{"id":3,"row":0,"column":1,"use":"office","density":[1]}]"#,
            #"[{"id":\#(Int.max),"row":0,"column":0,"use":"office","density":[1,1]}]"#,
            #"null"#,
        ]
        for json in bad {
            XCTAssertThrowsError(try decode(json), json)
        }

        // The world refuses buildings that do not stand on its land, one
        // a cell and of its use, or that stand while they are off.
        var world = world(bounds: try WorldBounds(width: 40_000, height: 40_000))
        try world.setLand([
            LandCell(row: 0, column: 0, use: .residential, residents: 4, jobs: 0),
            LandCell(row: 0, column: 1, use: .office, residents: 0, jobs: 10),
        ])
        world.setCityBuildings(true)
        let saved = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        func decodeWorld(buildings json: String?, cityBuildings: Bool = true) throws -> GameWorld {
            var object = saved
            object["buildings"] = try json.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
            object["cityBuildings"] = cityBuildings ? true : nil
            return try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let good = #"[{"id":1,"row":0,"column":0,"use":"residential","density":[1]},{"id":2,"row":0,"column":1,"use":"office","density":[1]}]"#
        XCTAssertEqual(try decodeWorld(buildings: good), world)
        XCTAssertNoThrow(try decodeWorld(buildings: #"[{"id":3,"row":0,"column":0,"use":"residential","density":[4]},{"id":9,"row":0,"column":1,"use":"office","density":[4],"kind":"existingStock"}]"#),
                         "any numbers and densities, kept as saved")
        for json in [
            #"[{"id":1,"row":0,"column":0,"use":"residential","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"residential","density":[1]},{"id":2,"row":0,"column":1,"use":"office","density":[1,1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"residential","density":[1]},{"id":2,"row":0,"column":1,"use":"commercial","density":[1]}]"#,
            #"[{"id":1,"row":0,"column":0,"use":"residential","density":[1]},{"id":2,"row":1,"column":1,"use":"office","density":[1]}]"#,
            #"[]"#,
            nil,
        ] as [String?] {
            XCTAssertThrowsError(try decodeWorld(buildings: json), json ?? "none")
        }
        XCTAssertThrowsError(try decodeWorld(buildings: good, cityBuildings: false), "buildings while they are off")
        XCTAssertNoThrow(try decodeWorld(buildings: nil, cityBuildings: false), "off, none")
    }
}
