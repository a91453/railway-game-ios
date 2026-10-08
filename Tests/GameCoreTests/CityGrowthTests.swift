import Foundation
@testable import GameCore
import XCTest

/// The city grows into its buildings (Phase 6c-2, ARCHITECTURE decision
/// 75): with the city's buildings on, land grows to each cell's building
/// capacity, and well-served stations raise full buildings a density a
/// night; each station's last service and stations reached are kept.
final class CityGrowthTests: XCTestCase {
    private static let middle: Int64 = 524_288
    private static let reach: Int64 = 51_200 * 51_200

    // MARK: - An independent reading of the rules

    /// What a building holds, from the table as decision 74 writes it.
    private static func capacity(_ use: LandUse, _ kind: BuildingKind, _ density: Int, residents: Int64, jobs: Int64) -> (residents: Int64, jobs: Int64) {
        let table: [LandUse: [(Int64, Int64)]] = [
            .residential: [(56, 12), (168, 36), (504, 108), (1_120, 240)],
            .commercial: [(16, 72), (48, 216), (144, 648), (320, 1_440)],
            .office: [(8, 84), (24, 252), (72, 756), (160, 1_680)],
            // Decision 91's.
            .industrial: [(0, 96), (0, 288), (0, 864), (0, 1_920)],
            .civic: [(8, 84), (24, 252), (72, 756), (160, 1_680)],
            .leisure: [(8, 84), (24, 252), (72, 756), (160, 1_680)],
            .agricultural: [(16, 72), (48, 216), (144, 648), (320, 1_440)],
            .park: [(0, 0), (0, 0), (0, 0), (0, 0)],
        ]
        let (r, j) = table[use]![density - 1]
        if kind == .existingStock { return (max(r, residents), max(j, jobs)) }
        return use == .residential ? (r, max(j, jobs)) : (max(r, residents), j)
    }

    private static func largestRemainder(_ total: Int64, _ weights: [Int64]) -> [Int64] {
        let sum = weights.reduce(0, +)
        guard sum > 0 else { return weights.map { _ in 0 } }
        var shares = weights.map { total * $0 / sum }
        let order = weights.indices.sorted { a, b in
            let ra = total * weights[a] % sum, rb = total * weights[b] % sum
            return ra != rb ? ra > rb : a < b
        }
        for index in order.prefix(Int(total - shares.reduce(0, +))) {
            shares[index] += 1
        }
        return shares
    }

    private static func squaredDistance(row: Int, column: Int, _ point: PlanPoint) -> Int64 {
        let dx = Int64(column) * 4_096 + 2_048 - point.x, dy = Int64(row) * 4_096 + 2_048 - point.y
        return dx * dx + dy * dy
    }

    /// A cell and its building, written again.
    private struct Plot: Equatable {
        var use: LandUse
        var residents: Int64
        var jobs: Int64
        var id: Int
        var kind: BuildingKind
        var density: Int
    }

    /// A night of growth (by ascending station, each with its rate and
    /// whether it raises buildings), written again cell by cell: the shares
    /// of the land as it was, the buildings full as the night began; then
    /// each growing station raises up to two of those in its catchment by
    /// row and column that no station raised tonight, grows its share into
    /// the cells of its catchment by their counts up to their capacity, and
    /// builds the empty cell beside people nearest it with D1 homes.
    private static func referenceNight(
        _ plots: [CellPosition: Plot], _ stations: [Station], rates: [StationID: Int64], raises: Set<StationID>, in bounds: WorldBounds
    ) -> [CellPosition: Plot] {
        var land = plots
        let columns = Int((bounds.width + 4_095) / 4_096), rows = Int((bounds.height + 4_095) / 4_096)
        // Shares, as in LandDemandTests.
        var shares: [StationID: (residents: Int64, jobs: Int64)] = [:]
        for key in land.keys.sorted() {
            let plot = land[key]!
            let near = stations.compactMap { station -> (Station, Int64)? in
                let d2 = squaredDistance(row: key.row, column: key.column, station.location)
                return d2 < reach ? (station, 1_000 - d2 * 1_000 / reach) : nil
            }
            let residents = largestRemainder(plot.residents, near.map(\.1)), jobs = largestRemainder(plot.jobs, near.map(\.1))
            for (index, (station, _)) in near.enumerated() {
                var share = shares[station.id] ?? (0, 0)
                share.residents += residents[index]
                share.jobs += jobs[index]
                shares[station.id] = share
            }
        }
        let full = Set(land.keys.filter { key in
            let plot = land[key]!
            // A park holds no one, so is never full (decision 91).
            guard plot.kind == .city, plot.density < 4, plot.use != .park else { return false }
            // Full by the main count only (decision 77): the table's
            // residents of homes, jobs of shops and offices.
            let table = capacity(plot.use, plot.kind, plot.density, residents: 0, jobs: 0)
            return plot.use == .residential ? plot.residents >= table.residents : plot.jobs >= table.jobs
        })
        var raised: Set<CellPosition> = []
        for station in stations.sorted(by: { $0.id < $1.id }) {
            guard let rate = rates[station.id], rate > 0 else { continue }
            let inReach = land.keys.sorted().filter { squaredDistance(row: $0.row, column: $0.column, station.location) < reach }
            if raises.contains(station.id) {
                for key in inReach.filter({ full.contains($0) && !raised.contains($0) }).prefix(2) {
                    land[key]!.density += 1
                    raised.insert(key)
                }
            }
            func grown(_ amount: Int64) -> Int64 { amount > 0 ? max(1, (amount * rate + 500) / 1_000) : 0 }
            let share = shares[station.id] ?? (0, 0)
            let addedResidents = largestRemainder(grown(share.residents), inReach.map { land[$0]!.residents })
            let addedJobs = largestRemainder(grown(share.jobs), inReach.map { land[$0]!.jobs })
            for (offset, key) in inReach.enumerated() {
                let plot = land[key]!
                let cap = capacity(plot.use, plot.kind, plot.density, residents: plot.residents, jobs: plot.jobs)
                if plot.residents < cap.residents { land[key]!.residents = min(cap.residents, plot.residents + addedResidents[offset]) }
                if plot.jobs < cap.jobs { land[key]!.jobs = min(cap.jobs, plot.jobs + addedJobs[offset]) }
            }
            var best: (Int64, Int, Int)?
            for row in 0..<rows {
                for column in 0..<columns where land[CellPosition(row: row, column: column)] == nil {
                    let d2 = squaredDistance(row: row, column: column, station.location)
                    guard d2 < reach else { continue }
                    let beside = [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)].contains { r, c in
                        land[CellPosition(row: r, column: c)].map { $0.residents + $0.jobs > 0 } ?? false
                    }
                    guard beside, best.map({ (d2, row, column) < $0 }) ?? true else { continue }
                    best = (d2, row, column)
                }
            }
            if let (_, row, column) = best {
                let id = (land.values.map(\.id).max() ?? 0) + 1
                land[CellPosition(row: row, column: column)] = Plot(use: .residential, residents: 4, jobs: 0, id: id, kind: .city, density: 1)
            }
        }
        return land
    }

    private static func plots(of world: GameWorld) -> [CellPosition: Plot] {
        var plots: [CellPosition: Plot] = [:]
        for cell in world.land.cells {
            let building = world.buildings.building(row: cell.row, column: cell.column)!
            plots[cell.position] = Plot(
                use: cell.use, residents: cell.residents, jobs: cell.jobs,
                id: building.id.rawValue, kind: building.kind, density: building.density.rawValue
            )
        }
        return plots
    }

    // MARK: - Worlds

    private func world(cells: [LandCell]? = nil, seed: UInt32 = 1, bounds: WorldBounds = .standard, buildings: Bool = true) throws -> GameWorld {
        var world = GameWorld(bounds: bounds, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        if let cells {
            try world.setLand(cells)
        } else {
            world.foundTowns(seed: seed)
        }
        world.setEconomyMode(.management)
        world.setLandDemand(true)
        world.setTownGrowth(true)
        world.setCityBuildings(buildings)
        return world
    }

    /// A small world: 32 × 24 cells.
    private static let small = try! WorldBounds(width: 131_072, height: 98_304)

    /// The middle of the cell at `row`, `column`.
    private static func point(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * 4_096 + 2_048, y: Int64(row) * 4_096 + 2_048)
    }

    /// Lets each station's passengers have had `served` of its trips (in
    /// thousandths, rounded up, so the share measured is `served` for a
    /// station of 1,000 trips or more) arrive since the last midnight.
    private func serve(_ world: inout GameWorld, _ served: [StationID: Int64]) throws {
        for (id, thousandths) in served {
            let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == id })
            let place = try XCTUnwrap(world.townGrowth?.places.first { $0.station == id })
            let arrived = place.counted + (world.passengers[index].demand!.dailyTrips * thousandths + 999) / 1_000
            // Released as well, so the ledger still adds up in a save.
            world.passengers[index].released += max(0, arrived - world.passengers[index].arrived)
            world.passengers[index].arrived = arrived
        }
    }

    // MARK: - Nights against the reference

    func testNightsFollowTheReferenceCellByCell() throws {
        for seed: UInt32 in [1, 5] {
            var world = try world(seed: seed)
            let points = [(Self.middle, Self.middle), (Self.middle + 30_000, Self.middle + 10_000), (Self.middle - 35_000, Self.middle)]
            for (index, point) in points.enumerated() {
                try world.buildStation(named: "S\(index)", at: PlanPoint(x: point.0, y: point.1))
            }
            world.growLand(reached: [:])
            let ids = world.stations.map(\.id)
            // Fully served; 800 thousandths; 799 (rounded up, so the
            // measured share is that or a little over: the reference reads
            // the arrivals); reached 2, 1 and 3.
            let served: [StationID: Int64] = [ids[0]: 1_000, ids[1]: 800, ids[2]: 799]
            let reached: [StationID: Int] = [ids[0]: 2, ids[1]: 1, ids[2]: 3]
            var raisedTotal = 0, capped = false
            for night in 0..<40 {
                try serve(&world, served)
                var rates: [StationID: Int64] = [:]
                var raises: Set<StationID> = []
                var shares: [StationID: Int64] = [:]
                for id in ids {
                    let record = world.passengers.first { $0.station == id }!
                    let place = world.townGrowth!.places.first { $0.station == id }!
                    let trips = record.demand!.dailyTrips, done = record.arrived - place.counted
                    let share: Int64 = done <= 0 ? 0 : done >= trips ? 1_000 : done * 1_000 / trips
                    rates[id] = done > 0 ? share * 10 / 1_000 + Int64(min(reached[id]!, 5)) : -2
                    shares[id] = share
                    if share >= 800, reached[id]! >= 1 { raises.insert(id) }
                }
                let before = Self.plots(of: world)
                let expected = Self.referenceNight(before, world.stations, rates: rates, raises: raises, in: world.bounds)
                world.growLand(reached: reached)
                let after = Self.plots(of: world)
                XCTAssertEqual(after, expected, "seed \(seed), night \(night)")
                XCTAssertNil(world.buildingProblem())
                for id in ids {
                    let place = world.townGrowth!.places.first { $0.station == id }!
                    XCTAssertEqual(place.lastService, shares[id], "seed \(seed), night \(night)")
                    XCTAssertEqual(place.lastReached, Int64(reached[id]!))
                }
                raisedTotal += after.filter { before[$0.key].map { $0.density } != nil && before[$0.key]!.density < $0.value.density }.count
                capped = capped || after.contains { key, plot in
                    let cap = Self.capacity(plot.use, plot.kind, plot.density, residents: 0, jobs: 0)
                    return plot.kind == .city && (plot.residents == cap.residents || plot.jobs == cap.jobs) && before[key] != nil
                }
            }
            XCTAssertGreaterThan(raisedTotal, 0, "seed \(seed): buildings were raised")
            XCTAssertTrue(capped, "seed \(seed): some cell grew to its capacity")
        }
    }

    // MARK: - Capacity

    /// One night of a single station at the middle of row 5, column 5, all
    /// its trips served, reaching `reached` stations.
    private func night(_ cells: [LandCell], reached: Int = 0, buildings: Bool = true) throws -> GameWorld {
        var world = try world(cells: cells, bounds: Self.small, buildings: buildings)
        let id = try world.buildStation(named: "S", at: Self.point(row: 5, column: 5)).id
        world.growLand(reached: [:])
        try serve(&world, [id: 1_000])
        world.growLand(reached: [id: reached])
        return world
    }

    func testHomesStopAtTheirBuildingsCapacity() throws {
        // D2 homes of 167 at 10 thousandths: (167 × 10 + 500) / 1000 = 2,
        // 169, held at 168.
        var world = try night([LandCell(row: 5, column: 5, use: .residential, residents: 167, jobs: 0)])
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 168)
        // D3 homes of 500: 5 more, 505, held at 504.
        world = try night([LandCell(row: 5, column: 5, use: .residential, residents: 500, jobs: 0)])
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 504)
        // Without the city's buildings, 400 still: 169 and 505 (above 400
        // already: kept, not grown).
        world = try night([LandCell(row: 5, column: 5, use: .residential, residents: 167, jobs: 0)], buildings: false)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 169)
        world = try night([LandCell(row: 5, column: 5, use: .residential, residents: 500, jobs: 0)], buildings: false)
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 500)
        // Offices' jobs: D2's 252 hold 250 + 3 at 252; their residents are
        // held at the table's 24 or what is there.
        world = try night([LandCell(row: 5, column: 5, use: .office, residents: 30, jobs: 250)])
        XCTAssertEqual(world.land.cell(row: 5, column: 5), LandCell(row: 5, column: 5, use: .office, residents: 30, jobs: 252))
    }

    func testWhatDoesNotFitIsDroppedNotGivenToAnotherCell() throws {
        // 167 + 300 residents grow by (467 × 10 + 500) / 1000 = 5, by the
        // largest remainder 2 and 3: the D2 homes have room for 1 and keep
        // 168; the other 1 is not added to the D3 homes beside them (303).
        let world = try night([
            LandCell(row: 5, column: 5, use: .residential, residents: 167, jobs: 0),
            LandCell(row: 5, column: 6, use: .residential, residents: 300, jobs: 0),
        ])
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 168)
        XCTAssertEqual(world.land.cell(row: 5, column: 6)?.residents, 303)
        // The station's new cell: (4, 5), with its D1 homes.
        XCTAssertEqual(world.land.cell(row: 4, column: 5)?.residents, 4)
        XCTAssertEqual(world.buildings.building(row: 4, column: 5)?.density, .d1)
        XCTAssertEqual(world.land.totals.residents, 168 + 303 + 4)
    }

    func testCellsAboveTheirCapacityKeepWhatTheyHave() throws {
        // A building that 6c-1's growth (to 400) or a save left above its
        // capacity: D1 homes of 60 (56) keep 60, and stay D1 without
        // service enough to raise them.
        var world = try world(cells: [LandCell(row: 5, column: 5, use: .residential, residents: 50, jobs: 0)], bounds: Self.small)
        world.land.cells[0] = LandCell(row: 5, column: 5, use: .residential, residents: 60, jobs: 0)
        let id = try world.buildStation(named: "S", at: Self.point(row: 5, column: 5)).id
        world.growLand(reached: [:])
        try serve(&world, [id: 1_000])
        world.growLand(reached: [id: 0])
        XCTAssertEqual(world.land.cell(row: 5, column: 5)?.residents, 60)
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d1)
    }

    // MARK: - Measures

    func testServiceAndStationsReachedAreKept() throws {
        var world = try world(cells: [LandCell(row: 5, column: 5, use: .residential, residents: 2_500, jobs: 0)], bounds: Self.small)
        let id = try world.buildStation(named: "S", at: Self.point(row: 5, column: 5)).id
        XCTAssertEqual(world.stationDemand(of: id)?.dailyTrips, 1_000)
        world.growLand(reached: [id: 3])
        var place = try XCTUnwrap(world.townGrowth(of: id))
        XCTAssertEqual(place.lastService, 0, "first seen: measured from the next midnight")
        XCTAssertEqual(place.lastReached, 0)
        for (served, reached, service, count) in [(Int64(799), 0, Int64(799), Int64(0)), (0, 9, 0, 5), (1_000, 2, 1_000, 2), (500, 1, 500, 1)] {
            try serve(&world, [id: served])
            world.growLand(reached: [id: reached])
            place = try XCTUnwrap(world.townGrowth(of: id))
            XCTAssertEqual(place.lastService, service)
            XCTAssertEqual(place.lastReached, count)
        }
        // More arrivals than trips (a day's carried over) count as 1000.
        let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == id })
        world.passengers[index].arrived = place.counted + 5_000
        world.growLand(reached: [:])
        XCTAssertEqual(world.townGrowth(of: id)?.lastService, 1_000)
        XCTAssertEqual(world.townGrowth(of: id)?.lastReached, 0)
        XCTAssertEqual(TownGrowth.serviceShare(served: -3, trips: 10), 0)
        XCTAssertEqual(TownGrowth.serviceShare(served: 7, trips: 9), 777)
    }

    func testMeasuresSaveOnlyOnceTakenAndOldSavesReadThemAsZero() throws {
        var world = try night([LandCell(row: 5, column: 5, use: .residential, residents: 100, jobs: 0)], reached: 2)
        let data = try JSONEncoder().encode(world)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let places = try XCTUnwrap((object["townGrowth"] as? [String: Any])?["places"] as? [[String: Any]])
        XCTAssertEqual(places[0]["lastService"] as? Int, 1_000)
        XCTAssertEqual(places[0]["lastReached"] as? Int, 2)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        // Without them (before 6c-2, or not yet measured): 0, and saved
        // without the keys.
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: #","lastService":1000"#, with: "").replacingOccurrences(of: #","lastReached":2"#, with: "")
        text = text.replacingOccurrences(of: #""lastService":1000,"#, with: "").replacingOccurrences(of: #""lastReached":2,"#, with: "")
        XCTAssertFalse(text.contains("lastService"))
        world = try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8))
        XCTAssertEqual(world.townGrowth?.places[0].lastService, 0)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("lastReached"))
        // Out of range is refused.
        let good = String(decoding: data, as: UTF8.self)
        for (key, bad) in [
            (#""lastService":1000"#, #""lastService":1001"#), (#""lastService":1000"#, #""lastService":-1"#),
            (#""lastReached":2"#, #""lastReached":6"#), (#""lastService":1000"#, #""lastService":null"#),
        ] {
            let broken = good.replacingOccurrences(of: key, with: bad)
            XCTAssertNotEqual(broken, good)
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(broken.utf8)), bad)
        }
    }

    // MARK: - Raising buildings

    /// Two stations sharing row 5 (each cell's middle well within 800 m of
    /// both), the cells' buildings as the night begins:
    ///
    /// - column 2: D1 homes of 56, full;
    /// - column 3: D1 shops of 72 jobs, full;
    /// - column 4: D4 homes of 1,120, full (no higher density);
    /// - column 5: existing stock of 2,000 residents (never raised);
    /// - column 6: D1 offices of 84 jobs, full;
    /// - column 7: D3 homes of 503, one short;
    /// - column 8: D2 homes of 168, full;
    /// - column 10: D1 homes of 56, full.
    private static let rowFive = [
        LandCell(row: 5, column: 2, use: .residential, residents: 56, jobs: 0),
        LandCell(row: 5, column: 3, use: .commercial, residents: 0, jobs: 72),
        LandCell(row: 5, column: 4, use: .residential, residents: 1_120, jobs: 0),
        LandCell(row: 5, column: 5, use: .residential, residents: 2_000, jobs: 0),
        LandCell(row: 5, column: 6, use: .office, residents: 0, jobs: 84),
        LandCell(row: 5, column: 7, use: .residential, residents: 503, jobs: 0),
        LandCell(row: 5, column: 8, use: .residential, residents: 168, jobs: 0),
        LandCell(row: 5, column: 10, use: .residential, residents: 56, jobs: 0),
    ]

    private func rowFiveWorld() throws -> (GameWorld, [StationID]) {
        var world = try world(cells: Self.rowFive, bounds: Self.small)
        let a = try world.buildStation(named: "A", at: Self.point(row: 5, column: 5)).id
        let b = try world.buildStation(named: "B", at: Self.point(row: 5, column: 9)).id
        world.growLand(reached: [:])
        return (world, [a, b])
    }

    private func density(_ world: GameWorld, _ column: Int) -> BuildingDensity? {
        world.buildings.building(row: 5, column: column)?.density
    }

    func testEachStationRaisesTwoFullBuildingsByRowAndColumnOncePerNight() throws {
        var (world, ids) = try rowFiveWorld()
        try serve(&world, [ids[0]: 1_000, ids[1]: 1_000])
        let before = Self.plots(of: world)
        world.growLand(reached: [ids[0]: 1, ids[1]: 1])
        // A raises columns 2 and 3 (its first two full ones), not its third
        // (6); B passes over 2 and 3, which A raised tonight, and raises 6
        // and 8, not 10. D4 (4), existing stock (5) and the homes one short
        // as the night began (7) are not raised.
        XCTAssertEqual(density(world, 2), .d2, "raised once, not again by B")
        XCTAssertEqual(density(world, 3), .d2)
        XCTAssertEqual(density(world, 4), .d4)
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.kind, .existingStock)
        XCTAssertEqual(density(world, 6), .d2)
        XCTAssertEqual(density(world, 7), .d3)
        XCTAssertEqual(density(world, 8), .d3)
        XCTAssertEqual(density(world, 10), .d1, "B's third")
        XCTAssertEqual(world.land.cell(row: 5, column: 7)?.residents, 504, "full tonight, raised no sooner than tomorrow")
        // Raising changes the density only: the same building, use and
        // people (the cells raised then grow into their new room).
        for column in [2, 3, 6, 8] {
            let old = before[CellPosition(row: 5, column: column)]!, new = world.buildings.building(row: 5, column: column)!
            XCTAssertEqual(new.id.rawValue, old.id)
            XCTAssertEqual(new.use, old.use)
            XCTAssertEqual(new.kind, .city)
        }
        XCTAssertEqual(Self.plots(of: world), Self.referenceNight(
            before, world.stations, rates: [ids[0]: 11, ids[1]: 11], raises: Set(ids), in: world.bounds
        ))

        // The next night only the homes that filled (7) and B's third (10,
        // full and not grown) are full, and A raises both: the raised
        // cells grew into their new room and are not full.
        try serve(&world, [ids[0]: 1_000, ids[1]: 1_000])
        world.growLand(reached: [ids[0]: 1, ids[1]: 1])
        XCTAssertEqual(density(world, 7), .d4)
        XCTAssertEqual(density(world, 10), .d2)
        XCTAssertEqual(density(world, 2), .d2)
    }

    /// Decision 77: only the main count fills a building. D2 homes of 100
    /// with 500 jobs (their jobs' capacity is the 500 they hold) and D2
    /// offices of 100 jobs with 60 residents (likewise 60) are not full and
    /// stay; the D1 homes of 56 beside them are, and rise.
    func testOnlyTheMainCountFillsABuilding() throws {
        var world = try world(cells: [
            LandCell(row: 5, column: 4, use: .residential, residents: 100, jobs: 500),
            LandCell(row: 5, column: 5, use: .office, residents: 60, jobs: 100),
            LandCell(row: 5, column: 6, use: .residential, residents: 56, jobs: 0),
        ], bounds: Self.small)
        let id = try world.buildStation(named: "S", at: Self.point(row: 5, column: 5)).id
        world.growLand(reached: [:])
        try serve(&world, [id: 1_000])
        let before = Self.plots(of: world)
        world.growLand(reached: [id: 2])
        XCTAssertEqual(world.buildings.building(row: 5, column: 4)?.density, .d2, "jobs at their capacity do not fill homes")
        XCTAssertEqual(world.buildings.building(row: 5, column: 5)?.density, .d2, "residents at theirs do not fill offices")
        XCTAssertEqual(world.buildings.building(row: 5, column: 6)?.density, .d2, "full homes rise")
        XCTAssertEqual(Self.plots(of: world), Self.referenceNight(before, world.stations, rates: [id: 12], raises: [id], in: world.bounds))
    }

    func testRaisingNeedsEightyPercentServedAndAStationReached() throws {
        // A station of 1,000 trips a day (2,500 residents: 56 in full D1
        // homes and 2,444 in existing stock beside them).
        let cells = [
            LandCell(row: 5, column: 5, use: .residential, residents: 56, jobs: 0),
            LandCell(row: 5, column: 6, use: .residential, residents: 2_444, jobs: 0),
        ]
        for (served, reached, raised) in [(Int64(799), 1, false), (800, 1, true), (1_000, 0, false), (1_000, 1, true)] {
            var world = try world(cells: cells, bounds: Self.small)
            let id = try world.buildStation(named: "S", at: Self.point(row: 5, column: 5)).id
            XCTAssertEqual(world.stationDemand(of: id)?.dailyTrips, 1_000)
            world.growLand(reached: [:])
            try serve(&world, [id: served])
            world.growLand(reached: [id: reached])
            XCTAssertEqual(world.townGrowth(of: id)?.lastService, served)
            XCTAssertEqual(density(world, 5), raised ? .d2 : .d1, "served \(served), reached \(reached)")
            // Either way the station grew (its rate was positive).
            XCTAssertGreaterThan(world.land.cells.count, 2)
        }
    }

    func testNothingIsRaisedWithoutGrowthOrWithBuildingsOff() throws {
        // Nothing served: the rate is negative, nothing grows or rises.
        var (world, ids) = try rowFiveWorld()
        try serve(&world, [ids[0]: 0, ids[1]: 0])
        let land = world.land, buildings = world.buildings
        world.growLand(reached: [ids[0]: 5, ids[1]: 5])
        XCTAssertEqual(world.land, land)
        XCTAssertEqual(world.buildings, buildings)
        // Buildings off: the land grows to 400 and 1,200, as before 6c.
        var off = try self.world(cells: Self.rowFive, bounds: Self.small, buildings: false)
        let a = try off.buildStation(named: "A", at: Self.point(row: 5, column: 5)).id
        off.growLand(reached: [:])
        try serve(&off, [a: 1_000])
        off.growLand(reached: [a: 1])
        XCTAssertTrue(off.buildings.isEmpty)
        XCTAssertGreaterThan(off.land.cell(row: 5, column: 2)!.residents, 56, "no building holds it back")
    }

    // MARK: - However the days are advanced

    /// A served line through the first town, running 06:00 to 22:00 so the
    /// trains stand idle over each midnight: the city grows and rises the
    /// same advanced a day at a time, minute by minute, in uneven slices,
    /// saved and loaded just before and just after a midnight, or idling
    /// over it in one step.
    func testTheCityGrowsTheSameHoweverTheDaysAreAdvanced() throws {
        var start = try world()
        let a = try start.buildTrackNode(at: WorldCoordinate(x: Self.middle - 40_960, y: Self.middle))
        let b = try start.buildTrackNode(at: WorldCoordinate(x: Self.middle + 40_960, y: Self.middle))
        let edge = try start.buildTrackEdge(from: a, to: b)
        let west = try start.buildStation(named: "West", at: PlanPoint(x: Self.middle - 30_720, y: Self.middle)).id
        let east = try start.buildStation(named: "East", at: PlanPoint(x: Self.middle + 30_720, y: Self.middle)).id
        try start.addTrackPlatform(west, on: edge, from: 8_192, to: 12_288)
        try start.addTrackPlatform(east, on: edge, from: 69_632, to: 73_728)
        let line = try start.createLine(named: "L", stops: [west, east]).id
        try start.setLineServiceWindow(line, to: .hours(open: 360, close: 1_320))
        try start.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        for (name, direction) in [("T1", TrackEdgeDirection.forward), ("T2", .backward)] {
            let train = try start.purchaseTrain(named: name).id
            try start.setTrainCars(train, to: 4)
            try start.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: direction), offset: 12_288))
            try start.setTrainContinuation(train, along: [], stoppingAt: 12_288)
            try start.setTrainMovementRate(train, to: 512)
            try start.assignTrain(train, to: line)
        }
        let days = 6, total = days * 1_440
        var daily = start
        for _ in 0..<days { try daily.advance(ticks: 1_440) }
        var minutes = start
        for _ in 0..<total { try minutes.advance(ticks: 1) }
        var sliced = start
        var done = 0, step = 1
        while done < total {
            let ticks = min(step, total - done)
            try sliced.advance(ticks: ticks)
            done += ticks
            step = step * 7 % 997 + 1
        }
        var saved = start
        for ticks in [1_439, 1, 1, 1_438, 1_441 * 2 - 2, total - 1_439 - 1 - 1 - 1_438 - (1_441 * 2 - 2)] {
            try saved.advance(ticks: ticks)
            saved = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(saved))
        }
        var idle = start
        try idle.advance(ticks: total)
        XCTAssertEqual(minutes, daily)
        XCTAssertEqual(sliced, daily)
        XCTAssertEqual(saved, daily)
        XCTAssertEqual(idle, daily)
        XCTAssertNil(daily.buildingProblem())
        let raised = zip(start.buildings.all, daily.buildings.all).filter { $0.density < $1.density }.count
        XCTAssertGreaterThan(raised, 0, "buildings rose")
        XCTAssertGreaterThan(daily.townGrowth(of: west)?.lastService ?? 0, 0)
    }
}
