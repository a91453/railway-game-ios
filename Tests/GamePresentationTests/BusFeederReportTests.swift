import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400, 10i-2: what a feeder bus adds, measured on the new game's
/// line between two towns (`BalanceReportTests.testALineBetweenTwoTowns`).
/// Not an assertion: with `BUS_REPORT=<days>` it plays the line with and
/// without a bus route at the first station and prints a Markdown table of
/// the station's trips, the company's fare trips and the route's takings.
final class BusFeederReportTests: XCTestCase {
    func testAFeederAtTheFirstStation() throws {
        guard let days = ProcessInfo.processInfo.environment["BUS_REPORT"].flatMap(Int.init), days > 0 else {
            throw XCTSkip("BUS_REPORT=<days> runs the report")
        }
        let buses = ProcessInfo.processInfo.environment["BUS_COUNT"].flatMap(Int.init) ?? 2
        let headway = ProcessInfo.processInfo.environment["BUS_HEADWAY"].flatMap(Int64.init) ?? 10
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let plain = try newGameLine(through: [towns[0], towns[1]])
        var fed = plain
        let station = try XCTUnwrap(fed.stations.first)
        // A road straight out of the station, away from the other town,
        // 2 km long, laid as a base map's road would be, and three stops
        // on it 1.0, 1.4 and 1.8 km out, past the station's 800 m.
        // `BUS_DIRECTION`: `away` (the default), `toward` the other town,
        // or `side`, square to the line.
        let out = (x: station.location.x - towns[1].x, y: station.location.y - towns[1].y)
        // `town`: toward the third town, which has no station, its stops
        // in that town (the route as long as the way there).
        let third = (x: towns[2].x - station.location.x, y: towns[2].y - station.location.y)
        let direction = ProcessInfo.processInfo.environment["BUS_DIRECTION"]
        let away = switch direction {
        case "toward": (x: -out.x, y: -out.y)
        case "side": (x: -out.y, y: out.x)
        case "town": third
        default: out
        }
        let length = FixedPoint.roundedSquareRoot(away.x * away.x + away.y * away.y)
        let reach = direction == "town" ? length / WorldCoordinate.unitsPerMetre + 400 : 2_000
        func point(metres: Int64) -> PlanPoint {
            let units = metres * WorldCoordinate.unitsPerMetre
            return PlanPoint(x: station.location.x + away.x * units / length, y: station.location.y + away.y * units / length)
        }
        func cell(_ point: PlanPoint) -> CellPosition {
            CellPosition(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
        }
        let cells = Set(stride(from: Int64(0), through: reach, by: 16).map { cell(point(metres: $0)) })
        let blocks = Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })
        try fed.setRoads(Array(cells), in: Array(blocks))
        let stops = (direction == "town" ? [reach - 200, reach - 600, reach - 1_000] : [1_800, 1_400, 1_000]).map { cell(point(metres: $0)) }
        let route = try fed.createBusRoute(to: station.id, stops: stops, service: .every(minutes: headway), buses: buses)

        var rows = ["| Day | Station trips (no bus) | Station trips (bus) | Fare trips (no bus) | Fare trips (bus) | Bus riders | Bus fares | Bus cost | Bus net |",
                    "| --: | --: | --: | --: | --: | --: | --: | --: | --: |"]
        var without = try reportPlayer(plain), with = try reportPlayer(fed)
        try without.advance(ticks: 1)
        try with.advance(ticks: 1)
        var totals = (plain: Int64(0), fed: Int64(0), riders: Int64(0), net: Int64(0))
        for day in 1...days {
            try without.playDay()
            try with.playDay()
            let yesterday = { (world: GameWorld) in
                world.accounts.days.first { $0.day == world.dayIndex(of: world.clock.now) - 1 }?.fareTrips ?? 0
            }
            let plainTrips = yesterday(without.world), fedTrips = yesterday(with.world)
            let bus = with.world.busRoute(id: route.id)?.days.last
            totals.plain += plainTrips
            totals.fed += fedTrips
            totals.riders += bus?.riders ?? 0
            totals.net += (bus?.fares.amount ?? 0) - (bus?.cost.amount ?? 0)
            if day <= 3 || day % 10 == 0 || day == days {
                let demand = { (world: GameWorld) in world.passengers.first { $0.station == station.id }?.demand?.dailyTrips ?? 0 }
                rows.append("| \(day) | \(demand(without.world)) | \(demand(with.world)) | \(plainTrips) | \(fedTrips) | \(bus?.riders ?? 0) | "
                    + "\(dollars(bus?.fares.amount ?? 0)) | \(dollars(bus?.cost.amount ?? 0)) | \(dollars((bus?.fares.amount ?? 0) - (bus?.cost.amount ?? 0))) |")
            }
        }
        let route0 = try XCTUnwrap(with.world.busRoute(id: route.id))
        print("### A feeder at the first station (\(buses) buses, every \(headway) min; \(route0.metres) m, headway \(route0.headway ?? 0), "
            + "feeder \(route0.feederTrips) trips at \(route0.feederMinutes) min)\n" + rows.joined(separator: "\n"))
        print("\nOver \(days) days: fare trips \(totals.plain) → \(totals.fed) (+\(totals.plain > 0 ? (totals.fed - totals.plain) * 1_000 / totals.plain : 0)‰), "
            + "bus riders \(totals.riders), bus net \(dollars(totals.net))")
    }

    /// The real map: a station alone at a real station's place, the land
    /// and the base map's roads within 3 km read, and a route of three
    /// stops on the road cells nearest 1.0, 1.4 and 1.8 km out in each of
    /// four directions. Prints the station's trips, what each route adds
    /// and its minutes; the day's fares at one ride a trip against two
    /// buses' cost.
    @MainActor
    func testAFeederOnTheRealMap() throws {
        guard ProcessInfo.processInfo.environment["BUS_REPORT"] != nil else { throw XCTSkip("BUS_REPORT=<days> runs the report") }
        let places = [("Taipei", 25.0478, 121.5170), ("Zhubei", 24.8393, 121.0094), ("Fengyuan", 24.2541, 120.7234), ("Pingtung", 22.6693, 120.4862)]
        var rows = ["| Station | Direction | Station trips | With the bus | Added | Feeder minutes | Route m | Fares a day | Two buses a day |",
                    "| --- | --- | --: | --: | --: | --: | --: | --: | --: |"]
        for (name, latitude, longitude) in places {
            let session = GameSession(world: GameWorld.newWholeTaiwanGame())
            try CommandLogReplay.realWorld.install(
                RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
            )
            let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
            let position = frame.worldPosition(latitude: latitude, longitude: longitude)
            let centre = PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
            session.readLand(within: 3_000 * WorldCoordinate.unitsPerMetre, of: centre)
            var base = session.world
            base.setEconomyMode(.management)
            base.setLandDemand(true)
            let station = try base.buildStation(named: name, at: centre).id
            let roads = try XCTUnwrap(base.roads)
            func nearestRoad(to point: PlanPoint) -> CellPosition? {
                let row = Int(point.y / Land.cellLength), column = Int(point.x / Land.cellLength)
                for reach in 0...8 {
                    let ring = (-reach...reach).flatMap { dr in (-reach...reach).map { CellPosition(row: row + dr, column: column + $0) } }
                        .filter { max(abs($0.row - row), abs($0.column - column)) == reach && roads.cells.contains($0) }
                    if let cell = ring.min() { return cell }
                }
                return nil
            }
            let own = base.passengers.first { $0.station == station }?.demand?.dailyTrips ?? 0
            // The station's own cell on a road, as a station road gives it.
            if !roads.cells.contains(base.roadCell(of: centre)), (try? base.stationRoadQuote(at: station)) != nil {
                _ = try base.buildStationRoad(at: station)
            }
            for (label, dx, dy) in [("east", Int64(1), Int64(0)), ("west", -1, 0), ("north", 0, -1), ("south", 0, 1)] {
                var world = base
                let stops = [1_800, 1_400, 1_000].compactMap { (metres: Int64) in
                    nearestRoad(to: PlanPoint(x: centre.x + dx * metres * WorldCoordinate.unitsPerMetre, y: centre.y + dy * metres * WorldCoordinate.unitsPerMetre))
                }
                guard stops.count == 3, let route = try? world.createBusRoute(to: station, stops: stops, service: .every(minutes: 10), buses: 2) else {
                    rows.append("| \(name) | \(label) | \(own) | — | no way along the roads | | | | |")
                    continue
                }
                let fed = world.busRoute(id: route.id)!
                let with = world.passengers.first { $0.station == station }?.demand?.dailyTrips ?? 0
                rows.append("| \(name) | \(label) | \(own) | \(with) | \(own > 0 ? (with - own) * 1_000 / own : 0)‰ | \(fed.feederMinutes) | \(fed.metres) | "
                    + "\(dollars(fed.feederTrips * BusRoute.fare.amount)) | \(dollars(2 * BusRoute.dailyCostPerBus.amount)) |")
            }
        }
        print("### A feeder on the real map (2 buses, every 10 minutes)\n" + rows.joined(separator: "\n"))
    }

    /// The real map with trains: each station of
    /// ``testAFeederOnTheRealMap()`` and a real neighbour a few km away,
    /// the land and roads within 3 km of both read, a line between them
    /// (`LineBuilder`, one train of four cars) and the same routes from
    /// the first. Plays `BUS_REPORT` days with and without each route and
    /// prints the riders who really travelled: the company's fare trips,
    /// the bus's riders and its takings, and the railway's added fares.
    @MainActor
    func testAFeederOnTheRealMapWithTrains() throws {
        guard let days = ProcessInfo.processInfo.environment["BUS_REPORT"].flatMap(Int.init), days > 0 else {
            throw XCTSkip("BUS_REPORT=<days> runs the report")
        }
        let buses = ProcessInfo.processInfo.environment["BUS_COUNT"].flatMap(Int.init) ?? 2
        let headway = ProcessInfo.processInfo.environment["BUS_HEADWAY"].flatMap(Int64.init) ?? 10
        let trains = ProcessInfo.processInfo.environment["BUS_TRAINS"].flatMap(Int.init) ?? 1
        let pairs = [(("Taipei", 25.0478, 121.5170), ("Songshan", 25.0492, 121.5781)),
                     (("Zhubei", 24.8393, 121.0094), ("Hsinchu", 24.8016, 120.9717)),
                     (("Fengyuan", 24.2541, 120.7234), ("Tanzi", 24.2120, 120.7031)),
                     (("Pingtung", 22.6693, 120.4862), ("Guilai", 22.6610, 120.5135))]
        let only = ProcessInfo.processInfo.environment["BUS_ONLY"]
        var rows = ["| Station | Direction | Station trips (no bus → bus) | Fare trips a day (no bus → bus) | Added | Bus riders a day | "
                        + "Bus fares a day | Bus cost a day | Rail fares added a day | Route m | Feeder trips | Feeder min |",
                    "| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --: | --: |"]
        for ((name, latitude, longitude), (other, latitude2, longitude2)) in pairs where only == nil || only == name {
            let session = GameSession(world: GameWorld.newWholeTaiwanGame())
            try CommandLogReplay.realWorld.install(
                RealWorldDataSet(population: true, places: true, water: true, heights: true, coverage: true, baseMap: true), in: session
            )
            let frame = RealWorldFrame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds)
            func plan(_ latitude: Double, _ longitude: Double) -> PlanPoint {
                let position = frame.worldPosition(latitude: latitude, longitude: longitude)
                return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
            }
            let centre = plan(latitude, longitude), neighbour = plan(latitude2, longitude2)
            session.readLand(within: 3_000 * WorldCoordinate.unitsPerMetre, of: centre)
            session.readLand(within: 3_000 * WorldCoordinate.unitsPerMetre, of: neighbour)
            var base = session.world
            base.setEconomyMode(.management)
            base.setLandDemand(true)
            base.economy = GameEconomy(balance: Money(100_000_000_000), costs: base.economy.costs)
            base = try LineBuilder.line(through: [centre, neighbour], in: base)
            if trains > 1, let line = base.lines.first?.id {
                try base.setLineTrainsInService(line, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
            }
            let station = try XCTUnwrap(base.stations.first).id
            let roads = try XCTUnwrap(base.roads)
            func nearestRoad(to point: PlanPoint) -> CellPosition? {
                let row = Int(point.y / Land.cellLength), column = Int(point.x / Land.cellLength)
                for reach in 0...8 {
                    let ring = (-reach...reach).flatMap { dr in (-reach...reach).map { CellPosition(row: row + dr, column: column + $0) } }
                        .filter { max(abs($0.row - row), abs($0.column - column)) == reach && roads.cells.contains($0) }
                    if let cell = ring.min() { return cell }
                }
                return nil
            }
            if !roads.cells.contains(base.roadCell(of: centre)), (try? base.stationRoadQuote(at: station)) != nil {
                _ = try base.buildStationRoad(at: station)
            }
            let measured = try play(base, days: days, route: nil)
            for (label, dx, dy) in [("east", Int64(1), Int64(0)), ("west", -1, 0), ("north", 0, -1), ("south", 0, 1)] {
                var world = base
                let stops = [1_800, 1_400, 1_000].compactMap { (metres: Int64) in
                    nearestRoad(to: PlanPoint(x: centre.x + dx * metres * WorldCoordinate.unitsPerMetre, y: centre.y + dy * metres * WorldCoordinate.unitsPerMetre))
                }
                guard stops.count == 3, let route = try? world.createBusRoute(to: station, stops: stops, service: .every(minutes: headway), buses: buses) else {
                    rows.append("| \(name) | \(label) | | | | no way along the roads | | | | | | |")
                    continue
                }
                let fed = try play(world, days: days, route: route.id)
                let feeder = try XCTUnwrap(world.busRoute(id: route.id))
                let per = Int64(days)
                rows.append("| \(name)–\(other) | \(label) | \(measured.demand) → \(fed.demand) | \(measured.fareTrips / per) → \(fed.fareTrips / per) | "
                    + "\(measured.fareTrips > 0 ? (fed.fareTrips - measured.fareTrips) * 1_000 / measured.fareTrips : 0)‰ | \(fed.riders / per) | "
                    + "\(dollars(fed.busFares / per)) | \(dollars(fed.busCost / per)) | \(dollars((fed.fares - measured.fares) / per)) | "
                    + "\(feeder.metres) | \(feeder.feederTrips) | \(feeder.feederMinutes) |")
            }
        }
        print("### A feeder on the real map with trains (\(buses) buses, every \(headway) min, \(trains) train(s), \(days) days)\n" + rows.joined(separator: "\n"))
    }

    /// `world` played `days` days after its first tick: the first
    /// station's trips, the days' fare trips and fares, and route
    /// `route`'s riders, fares and cost.
    private func play(_ world: GameWorld, days: Int, route: BusRouteID?) throws
        -> (demand: Int64, fareTrips: Int64, fares: Int64, riders: Int64, busFares: Int64, busCost: Int64) {
        var player = try reportPlayer(world)
        try player.advance(ticks: 1)
        var totals = (demand: Int64(0), fareTrips: Int64(0), fares: Int64(0), riders: Int64(0), busFares: Int64(0), busCost: Int64(0))
        for _ in 1...days {
            try player.playDay()
            let world = player.world
            let yesterday = world.accounts.days.first { $0.day == world.dayIndex(of: world.clock.now) - 1 }
            totals.fareTrips += yesterday?.fareTrips ?? 0
            totals.fares += yesterday?.fareRevenue.amount ?? 0
            if let route, let bus = world.busRoute(id: route)?.days.last {
                totals.riders += bus.riders
                totals.busFares += bus.fares.amount
                totals.busCost += bus.cost.amount
            }
        }
        let first = player.world.stations.first?.id
        totals.demand = player.world.passengers.first { $0.station == first }?.demand?.dailyTrips ?? 0
        return totals
    }

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
