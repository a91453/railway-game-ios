import Foundation
@testable import GameCore
import XCTest

/// Demand from land (Phase 6b, ARCHITECTURE decision 73): a managed
/// company's stations take their ridership from their share of the land,
/// and the land round well-served stations grows and spreads.
final class LandDemandTests: XCTestCase {
    private static let middle: Int64 = 524_288

    private func world(seed: UInt32 = 1, management: Bool = true) -> GameWorld {
        var world = GameWorld(bounds: .maximum, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.foundTowns(seed: seed)
        if management { world.setEconomyMode(.management) }
        world.setLandDemand(true)
        return world
    }

    // MARK: - An independent reading of the rules

    /// `total` by the largest remainder over `weights`, ties to the lower
    /// index, written again.
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

    private static let reach: Int64 = 51_200 * 51_200

    /// Every station's share, cell by cell over every station.
    private static func referenceShares(_ cells: [LandCell], _ stations: [Station]) -> [StationID: LandDemand.Share] {
        var shares: [StationID: LandDemand.Share] = [:]
        for cell in cells {
            let near = stations.compactMap { station -> (Station, Int64)? in
                let d2 = squaredDistance(row: cell.row, column: cell.column, station.location)
                return d2 < reach ? (station, 1_000 - d2 * 1_000 / reach) : nil
            }
            let residents = largestRemainder(cell.residents, near.map(\.1))
            let jobs = largestRemainder(cell.jobs, near.map(\.1))
            for (index, (station, _)) in near.enumerated() {
                var share = shares[station.id] ?? LandDemand.Share()
                share.residents += residents[index]
                if cell.use == .office { share.officeJobs += jobs[index] } else { share.shopJobs += jobs[index] }
                shares[station.id] = share
            }
        }
        return shares
    }

    /// A day's growth of `cells` at `rates` (by ascending station), written
    /// again: each growing station adds to its catchment's cells by their
    /// residents (jobs), filling each to 400 (1,200), then builds the empty
    /// cell beside people nearest it.
    private static func referenceGrowth(_ cells: [LandCell], _ stations: [Station], rates: [StationID: Int64], in bounds: WorldBounds) -> [LandCell] {
        let shares = referenceShares(cells, stations)
        var land: [Int: LandCell] = [:]
        let columns = Int((bounds.width + 4_095) / 4_096), rows = Int((bounds.height + 4_095) / 4_096)
        for cell in cells { land[cell.row * columns + cell.column] = cell }
        for station in stations {
            guard let rate = rates[station.id], rate > 0 else { continue }
            let share = shares[station.id] ?? LandDemand.Share()
            func grown(_ amount: Int64) -> Int64 { amount > 0 ? max(1, (amount * rate + 500) / 1_000) : 0 }
            let keys = land.keys.sorted().filter {
                squaredDistance(row: $0 / columns, column: $0 % columns, station.location) < reach
            }
            let addedResidents = largestRemainder(grown(share.residents), keys.map { land[$0]!.residents })
            let addedJobs = largestRemainder(grown(share.officeJobs + share.shopJobs), keys.map { land[$0]!.jobs })
            for (offset, key) in keys.enumerated() {
                let cell = land[key]!
                let residents = cell.residents >= 400 ? cell.residents : min(400, cell.residents + addedResidents[offset])
                let jobs = cell.jobs >= 1_200 ? cell.jobs : min(1_200, cell.jobs + addedJobs[offset])
                land[key] = LandCell(row: cell.row, column: cell.column, use: cell.use, residents: residents, jobs: jobs)
            }
            var best: (Int64, Int, Int)?
            for row in 0..<rows {
                for column in 0..<columns where land[row * columns + column] == nil {
                    let d2 = squaredDistance(row: row, column: column, station.location)
                    guard d2 < reach else { continue }
                    let beside = [(row - 1, column), (row + 1, column), (row, column - 1), (row, column + 1)].contains { r, c in
                        (0..<rows).contains(r) && (0..<columns).contains(c) && land[r * columns + c] != nil
                    }
                    guard beside, best.map({ (d2, row, column) < $0 }) ?? true else { continue }
                    best = (d2, row, column)
                }
            }
            if let (_, row, column) = best {
                land[row * columns + column] = LandCell(row: row, column: column, use: .residential, residents: 4, jobs: 0)
            }
        }
        return land.keys.sorted().map { land[$0]! }
    }

    // MARK: - Ridership

    func testAShareMakesFortyTripsForEveryHundredOfTheKindMostOfIt() {
        XCTAssertNil(LandDemand.Share().demand)
        XCTAssertNil(LandDemand.Share(residents: 1).demand, "0.4 trips round to 0")
        XCTAssertEqual(LandDemand.Share(residents: 2).demand, StationDemand(kind: .residential, dailyTrips: 1), "0.8 rounds to 1")
        XCTAssertEqual(LandDemand.Share(residents: 1_000, officeJobs: 500, shopJobs: 250).demand,
                       StationDemand(kind: .residential, dailyTrips: 700))
        XCTAssertEqual(LandDemand.Share(residents: 10, officeJobs: 10, shopJobs: 10).demand?.kind, .residential, "homes on a tie")
        XCTAssertEqual(LandDemand.Share(residents: 9, officeJobs: 10, shopJobs: 10).demand?.kind, .office, "then offices")
        XCTAssertEqual(LandDemand.Share(residents: 9, officeJobs: 9, shopJobs: 10).demand?.kind, .shopping)
        XCTAssertEqual(LandDemand.Share(residents: 10_000_000).demand?.dailyTrips, StationDemand.maximumDailyTrips)
    }

    func testSharesFollowTheRuleWorkedOutCellByCell() throws {
        var world = world(seed: 7)
        // Stations in and between the towns, some sharing cells, one far
        // from any town.
        let points = [
            (Self.middle, Self.middle), (Self.middle + 20_000, Self.middle), (Self.middle - 30_000, Self.middle + 40_000),
            (Self.middle + 51_200, Self.middle), (100_000, 100_000),
        ]
        for town in world.land.cells.filter({ $0.residents >= 100 }).prefix(3) {
            try world.buildStation(named: "T\(town.row)", at: town.middle)
        }
        for (index, point) in points.enumerated() {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: point.0, y: point.1))
        }
        let shares = LandDemand.shares(of: world.land, among: world.stations)
        XCTAssertEqual(shares, Self.referenceShares(world.land.cells, world.stations))
        // No one is counted twice: the shares add up to the land within
        // reach of any station.
        let reached = world.land.cells.filter { cell in world.stations.contains { Self.squaredDistance(row: cell.row, column: cell.column, $0.location) < Self.reach } }
        let total = shares.values.reduce(Int64(0)) { $0 + $1.residents + $1.officeJobs + $1.shopJobs }
        XCTAssertEqual(total, reached.reduce(Int64(0)) { $0 + $1.residents + $1.jobs })
        XCTAssertNil(shares[StationID(rawValue: 8)], "the station far from the towns has no land")
        // And each station's ridership is its share's.
        for station in world.stations {
            XCTAssertEqual(world.stationDemand(of: station.id), shares[station.id]?.demand, station.name)
        }
    }

    // MARK: - When the land sets ridership

    func testANewStationTakesItsShareFromItsNeighbours() throws {
        var world = world()
        let a = try world.buildStation(named: "A", at: PlanPoint(x: Self.middle, y: Self.middle)).id
        let whole = try XCTUnwrap(world.stationDemand(of: a))
        // The whole first town: (50,189 + 33,276) × 40 / 100.
        XCTAssertEqual(whole, StationDemand(kind: .residential, dailyTrips: 33_386))
        let b = try world.buildStation(named: "B", at: PlanPoint(x: Self.middle + 25_600, y: Self.middle)).id
        let after = try XCTUnwrap(world.stationDemand(of: a)).dailyTrips
        XCTAssertLessThan(after, whole.dailyTrips, "B takes part of A's town")
        let both = after + (world.stationDemand(of: b)?.dailyTrips ?? 0)
        XCTAssertEqual(Double(both), Double(whole.dailyTrips), accuracy: 2, "shared, not counted twice (each rounded)")
    }

    func testTheLandSetsOnlyAManagedCompanysRidership() throws {
        var free = world(management: false)
        let a = try free.buildStation(named: "A", at: PlanPoint(x: Self.middle, y: Self.middle)).id
        XCTAssertNil(free.stationDemand(of: a), "free play: the player sets ridership")
        try free.setStationDemand(a, to: StationDemand(kind: .scenic, dailyTrips: 300))
        free.foundTowns(seed: 2)
        XCTAssertEqual(free.stationDemand(of: a), StationDemand(kind: .scenic, dailyTrips: 300))
        free.setEconomyMode(.management)
        XCTAssertEqual(free.stationDemand(of: a)?.dailyTrips, 33_386, "managed, the land sets it")
        let before = free
        XCTAssertThrowsError(try free.setStationDemand(a, to: StationDemand(kind: .office, dailyTrips: 5))) {
            XCTAssertEqual($0 as? GameError, .stationDemandFromLand)
        }
        XCTAssertEqual(free, before)
        // Turned off, the stations keep what the land gave them, and the
        // player may set it.
        free.setLandDemand(false)
        XCTAssertEqual(free.stationDemand(of: a)?.dailyTrips, 33_386)
        try free.setStationDemand(a, to: StationDemand(kind: .office, dailyTrips: 5))
        free.setLandDemand(true)
        XCTAssertEqual(free.stationDemand(of: a)?.dailyTrips, 33_386)
        // Land changes ridership at once; none leaves no ridership.
        try free.setLand([])
        XCTAssertNil(free.stationDemand(of: a))
    }

    func testLandDemandIsSavedOnlyWhenOn() throws {
        var world = world()
        try world.buildStation(named: "A", at: PlanPoint(x: Self.middle, y: Self.middle))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertEqual(object["landDemand"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(world)), world)
        world.setLandDemand(false)
        let off = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(off["landDemand"])
    }

    /// Turned off, town growth starts again from the ridership each station
    /// keeps, as after ``GameWorld/setStationDemand(_:to:)``: the start the
    /// land set long before would pull a station back to it at the next
    /// midnight, and its growth, out of range, would leave a save that does
    /// not load.
    func testTurningLandDemandOffStartsTownGrowthAgain() throws {
        var world = world()
        world.setTownGrowth(true)
        let a = try world.buildStation(named: "A", at: PlanPoint(x: Self.middle, y: Self.middle)).id
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.townGrowth(of: a)?.base, 33_386, "growth has seen the whole town")
        try world.setLand([LandCell(row: 128, column: 128, use: .residential, residents: 100, jobs: 0)])
        let kept = try XCTUnwrap(world.stationDemand(of: a))
        XCTAssertEqual(kept.dailyTrips, 40)
        world.setLandDemand(false)
        XCTAssertNil(world.townGrowth(of: a), "growth starts again")
        try world.advance(ticks: 1_440)
        XCTAssertEqual(world.stationDemand(of: a), kept, "not pulled back to the town it had")
        XCTAssertNoThrow(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))))
    }

    // MARK: - Growth

    /// A world with town growth whose stations growth has seen, and the
    /// rates each would grow at when `served` of its trips arrive.
    func testADaysGrowthFollowsTheRuleWorkedOutCellByCell() throws {
        for seed: UInt32 in [1, 5] {
            var world = world(seed: seed)
            world.setTownGrowth(true)
            let points = [(Self.middle, Self.middle), (Self.middle + 40_000, Self.middle + 10_000), (Self.middle - 45_000, Self.middle)]
            for (index, point) in points.enumerated() {
                try world.buildStation(named: "S\(index)", at: PlanPoint(x: point.0, y: point.1))
            }
            world.growLand(reached: [:]) // growth sees the stations
            // Serve them: all of the first's trips, half of the second's,
            // none of the third's.
            let ids = world.stations.map(\.id)
            for (id, fraction) in zip(ids, [1_000, 500, 0] as [Int64]) {
                let index = try XCTUnwrap(world.passengers.firstIndex { $0.station == id })
                world.passengers[index].arrived += world.passengers[index].demand!.dailyTrips * fraction / 1_000
            }
            let reached: [StationID: Int] = [ids[0]: 2, ids[1]: 9]
            var rates: [StationID: Int64] = [:]
            for id in ids {
                let record = world.passengers.first { $0.station == id }!
                let place = world.townGrowth!.places.first { $0.station == id }!
                rates[id] = TownGrowth.growth(served: record.arrived - place.counted, trips: record.demand!.dailyTrips, reached: reached[id] ?? 0)
            }
            // Fully served and two reached: 10 + 2; half served (rounded
            // down, so just under half: 4) and nine reached (five count):
            // 9; none served: −2.
            XCTAssertEqual(ids.map { rates[$0]! }, [12, 9, -2])
            let expected = Self.referenceGrowth(world.land.cells, world.stations, rates: rates, in: world.bounds)
            let tripsBefore = ids.map { world.stationDemand(of: $0)!.dailyTrips }
            world.growLand(reached: reached)
            XCTAssertEqual(world.land.cells, expected, "seed \(seed)")
            XCTAssertEqual(world.land.cells.count, Land.towns(seed: seed, in: .maximum).cells.count + 2, "two growing stations built a cell each")
            for (index, id) in ids.enumerated() {
                XCTAssertEqual(world.stationDemand(of: id), LandDemand.shares(of: world.land, among: world.stations)[id]?.demand)
                let now = world.stationDemand(of: id)!.dailyTrips
                XCTAssertEqual(world.townGrowth(of: id)?.lastGrowth, (now - tripsBefore[index]) * 1_000 / tripsBefore[index])
            }
            XCTAssertGreaterThan(world.stationDemand(of: ids[0])!.dailyTrips, tripsBefore[0])
            XCTAssertNil(world.landProblem, "the grown land is valid")
        }
    }

    /// A served line in the first town: the land grows each midnight and
    /// the same whether advanced a day at a time, minute by minute, or
    /// saved and loaded on the way.
    func testTheLandGrowsTheSameHoweverTheDaysAreAdvanced() throws {
        var start = world()
        start.setTownGrowth(true)
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
        let days: Int = 3
        var daily = start
        for _ in 0..<days { try daily.advance(ticks: 1_440) }
        var minutes = start
        for _ in 0..<(days * 1_440) { try minutes.advance(ticks: 1) }
        var saved = start
        try saved.advance(ticks: 1_000)
        saved = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(saved))
        try saved.advance(ticks: days * 1_440 - 1_000)
        XCTAssertEqual(minutes, daily)
        XCTAssertEqual(saved, daily)
        XCTAssertGreaterThan(daily.land.totals.residents, start.land.totals.residents, "a served town grows")
        XCTAssertGreaterThan(daily.land.cells.count, start.land.cells.count, "and spreads")
    }
}

extension GameWorld {
    /// The land's problem in this world, for the tests.
    var landProblem: String? {
        land.problem(in: bounds)
    }
}
