import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 438: what a city bus route earns beside the trains, measured
/// against the targets of `docs/research/CITY_BUS_ROADS_DESIGN_2026-10-27.md`
/// §3.4. Not an assertion: with `CITY_BUS_REPORT=<days>` each test plays
/// its worlds and prints a Markdown table.
final class CityBusReportTests: XCTestCase {
    private var days: Int {
        get throws {
            guard let days = ProcessInfo.processInfo.environment["CITY_BUS_REPORT"].flatMap(Int.init), days > 0 else {
                throw XCTSkip("CITY_BUS_REPORT=<days> runs the report")
            }
            return days
        }
    }

    /// The blank map of seed 1: (i) the line between the first two towns
    /// only, (ii) with a city route from 300 m out of the first station
    /// to three stops in the third town, which has no station, and (iii)
    /// the route alone, no railway. Targets 2, 3, 5, 6 and 7.
    func testACityRouteBetweenTowns() throws {
        let days = try days
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let railway = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(railway.stations.first)
        let away = (x: towns[2].x - station.location.x, y: towns[2].y - station.location.y)
        let length = FixedPoint.roundedSquareRoot(away.x * away.x + away.y * away.y)
        let reach = length / WorldCoordinate.unitsPerMetre + 400
        func cell(metres: Int64) -> CellPosition {
            let units = metres * WorldCoordinate.unitsPerMetre
            return CellPosition(containing: PlanPoint(x: station.location.x + away.x * units / length, y: station.location.y + away.y * units / length))
        }
        func laid(_ start: GameWorld) throws -> GameWorld {
            var world = start
            if world.roads == nil { world.enableRoads(towns: towns) }
            let cells = Set(stride(from: Int64(0), through: reach, by: 16).map(cell(metres:)))
            try world.setRoads(Array(cells), in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
            return world
        }
        let stops = [300, reach - 1_000, reach - 600, reach - 200].map(cell(metres:))
        let plain = try laid(railway)
        var both = plain
        let route = try both.createBusRoute(to: nil, stops: stops, service: .every(minutes: 10), buses: 2).id
        var alone = try laid(GameWorld.newGame())
        alone.setEconomyMode(.management)
        alone.setLandDemand(true)
        try alone.createBusRoute(to: nil, stops: Array(stops.dropFirst()), service: .every(minutes: 10), buses: 2)

        let i = try play(plain, days: days, route: nil)
        let ii = try play(both, days: days, route: route)
        let iii = try play(alone, days: days, route: BusRouteID(rawValue: 1))
        let bus = try XCTUnwrap(both.busRoute(id: route))
        let price = BusRoute.stopPrice.amount * Int64(stops.count) + BusRoute.busPrice.amount * 2
        let per = Int64(days)
        let lineKilometres = Double(FixedPoint.roundedSquareRoot((towns[1].x - towns[0].x) * (towns[1].x - towns[0].x) + (towns[1].y - towns[0].y) * (towns[1].y - towns[0].y))) / Double(WorldCoordinate.unitsPerMetre) / 1_000
        let busKilometres = Double(bus.metres) / 2 / 1_000
        let railPerKm = Double(i.railOperating) / Double(max(1, i.fareTrips)) / lineKilometres
        let busPerKm = Double(ii.busNet) / Double(max(1, ii.riders)) / busKilometres
        print("""
            ### A city route between towns (seed 1; \(days) days; route \(bus.metres) m, headway \(bus.headway ?? 0), \
            local \(bus.localTrips) trips at \(bus.localMinutes) min, transfer \(bus.transfer.map { "#\($0.station.rawValue)" } ?? "none"), \
            feeder \(bus.feederTrips) trips at \(bus.feederMinutes) min)
            | World | Fare trips a day | Rail operating a day | Bus riders a day | Riders a departure | Bus net a day |
            | --- | --: | --: | --: | --: | --: |
            | (i) railway | \(i.fareTrips / per) | \(dollars(i.railOperating / per)) | | | |
            | (ii) railway + city route | \(ii.fareTrips / per) | \(dollars(ii.railOperating / per)) | \(ii.riders / per) | \
            \(ii.riders / per / max(1, 2 * bus.dailyDepartures)) | \(dollars(ii.busNet / per)) |
            | (iii) city route alone | | | \(iii.riders / per) | | \(dollars(iii.busNet / per)) |

            - #2 operating profit a passenger-km, bus ÷ rail (bus at half the route a ride, rail the whole line): \
            \(ratio(busPerKm, railPerKm)) (bus \(cents(busPerKm)), rail \(cents(railPerKm)))
            - #3 bus net ÷ rail operating (i): \(ratio(Double(ii.busNet), Double(i.railOperating)))
            - #5 payback of \(dollars(price)): \(ii.busNet > 0 ? "\(price * per / ii.busNet) days" : "never (net ≤ 0)")
            - #6 fare trips (ii) − (i): \(ii.fareTrips - i.fareTrips) over \(days) days
            - #7 riders a departure: \(ii.riders / per / max(1, 2 * bus.dailyDepartures)) of \(BusRoute.capacity)
            """)
    }

    /// Three city routes in the first town, stops 1.0, 1.4 and 1.8 km out
    /// of its station away from, toward and square to the other town, as
    /// decision 400's feeders. Target 9: they lose money.
    func testACityRouteInsideATown() throws {
        let days = try days
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let railway = try newGameLine(through: [towns[0], towns[1]])
        let station = try XCTUnwrap(railway.stations.first)
        let out = (x: station.location.x - towns[1].x, y: station.location.y - towns[1].y)
        var rows = ["| Direction | Route m | Local trips | Riders a day | Bus net a day |", "| --- | --: | --: | --: | --: |"]
        for (label, away) in [("away", out), ("toward", (x: -out.x, y: -out.y)), ("side", (x: -out.y, y: out.x))] {
            let length = FixedPoint.roundedSquareRoot(away.x * away.x + away.y * away.y)
            func cell(metres: Int64) -> CellPosition {
                let units = metres * WorldCoordinate.unitsPerMetre
                return CellPosition(containing: PlanPoint(x: station.location.x + away.x * units / length, y: station.location.y + away.y * units / length))
            }
            var world = railway
            if world.roads == nil { world.enableRoads(towns: towns) }
            let cells = Set(stride(from: Int64(0), through: 2_000, by: 16).map(cell(metres:)))
            try world.setRoads(Array(cells), in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
            let route = try world.createBusRoute(to: nil, stops: [1_000, 1_400, 1_800].map(cell(metres:)), service: .every(minutes: 10), buses: 2)
            let measured = try play(world, days: days, route: route.id)
            let bus = try XCTUnwrap(world.busRoute(id: route.id))
            rows.append("| \(label) | \(bus.metres) | \(bus.localTrips) | \(measured.riders / Int64(days)) | \(dollars(measured.busNet / Int64(days))) |")
        }
        print("### City routes inside a town (seed 1; \(days) days; 2 buses, every 10 min)\n" + rows.joined(separator: "\n"))
    }

    /// The real map: decision 400's four stations, each with its real
    /// neighbour and a line between them, and in each of four directions a
    /// city route of stops 1.0, 2.0 and 3.0 km out. Targets 4, 6 and 7:
    /// the best route's net against the line's operating profit (and
    /// Taipei's against decision 400's $637,631 of days 331 to 360).
    @MainActor
    func testACityRouteOnTheRealMap() throws {
        let days = try days
        let pairs = [(("Taipei", 25.0478, 121.5170), ("Songshan", 25.0492, 121.5781)),
                     (("Zhubei", 24.8393, 121.0094), ("Hsinchu", 24.8016, 120.9717)),
                     (("Fengyuan", 24.2541, 120.7234), ("Tanzi", 24.2120, 120.7031)),
                     (("Pingtung", 22.6693, 120.4862), ("Guilai", 22.6610, 120.5135))]
        let only = ProcessInfo.processInfo.environment["CITY_BUS_ONLY"]
        var rows = ["| Station | Direction | Fare trips a day (no bus → bus) | Rail operating a day | Bus riders a day | Riders a departure | "
                        + "Bus net a day | Net ÷ rail | Route m | Local trips | Transfer |",
                    "| --- | --- | --: | --: | --: | --: | --: | --: | --: | --: | --- |"]
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
            session.readLand(within: 3_500 * WorldCoordinate.unitsPerMetre, of: centre)
            session.readLand(within: 3_000 * WorldCoordinate.unitsPerMetre, of: neighbour)
            var base = session.world
            base.setEconomyMode(.management)
            base.setLandDemand(true)
            base.economy = GameEconomy(balance: Money(100_000_000_000), costs: base.economy.costs)
            base = try LineBuilder.line(through: [centre, neighbour], in: base)
            let roads = try XCTUnwrap(base.roads)
            func nearestRoad(to point: PlanPoint) -> CellPosition? {
                let row = Int(point.y / Land.cellLength), column = Int(point.x / Land.cellLength)
                for reach in 0...8 {
                    let ring = (-reach...reach).flatMap { dr in (-reach...reach).map { CellPosition(row: row + dr, column: column + $0) } }
                        .filter { max(abs($0.row - row), abs($0.column - column)) == reach && roads.contains($0) }
                    if let cell = ring.min() { return cell }
                }
                return nil
            }
            let measured = try play(base, days: days, route: nil)
            let per = Int64(days)
            for (label, dx, dy) in [("east", Int64(1), Int64(0)), ("west", -1, 0), ("north", 0, -1), ("south", 0, 1)] {
                var world = base
                let stops = [3_000, 2_000, 1_000].compactMap { (metres: Int64) in
                    nearestRoad(to: PlanPoint(x: centre.x + dx * metres * WorldCoordinate.unitsPerMetre, y: centre.y + dy * metres * WorldCoordinate.unitsPerMetre))
                }
                guard stops.count == 3, let route = try? world.createBusRoute(to: nil, stops: stops, service: .every(minutes: 10), buses: 2) else {
                    rows.append("| \(name) | \(label) | | | | | no way along the roads | | | | |")
                    continue
                }
                let played = try play(world, days: days, route: route.id)
                let bus = try XCTUnwrap(world.busRoute(id: route.id))
                let against = name == "Taipei" ? "\(ratio(Double(played.busNet / per), 63_763_100)) (Taipei $637,631); " : ""
                rows.append("| \(name)–\(other) | \(label) | \(measured.fareTrips / per) → \(played.fareTrips / per) | \(dollars(measured.railOperating / per)) | "
                    + "\(played.riders / per) | \(played.riders / per / max(1, 2 * bus.dailyDepartures)) | \(dollars(played.busNet / per)) | "
                    + "\(against)\(ratio(Double(played.busNet), Double(measured.railOperating))) | \(bus.metres) | \(bus.localTrips) | "
                    + "\(bus.transfer.map { "#\($0.station.rawValue)" } ?? "—") |")
            }
        }
        print("### City routes on the real map (2 buses, every 10 min, \(days) days)\n" + rows.joined(separator: "\n"))
    }

    /// Target 1, worked out from the rules: a passenger-km's fare by bus
    /// and by train at 2, 5 and 10 km under the new game's fares; and the
    /// seat-km's cost of a bus against a train of four cars.
    func testFareAndCostPerPassengerKilometre() throws {
        _ = try days
        let rules = GameWorld.newGame().accounts.fareRules ?? .standard
        var rows = ["| Km | Bus fare | Rail fare | Bus ÷ rail a passenger-km |", "| --: | --: | --: | --: |"]
        for kilometres: Int64 in [2, 5, 10] {
            let units = kilometres * 1_000 * WorldCoordinate.unitsPerMetre
            let rail = rules.fare(squaredDistance: units * units).amount
            rows.append("| \(kilometres) | \(dollars(BusRoute.fare.amount)) | \(dollars(rail)) | \(ratio(Double(BusRoute.fare.amount), Double(rail))) |")
        }
        let busSeat = Double(BusRoute.costPerKilometre.amount) / Double(BusRoute.capacity)
        print("### Fares a passenger-km (\(rules))\n" + rows.joined(separator: "\n")
            + "\n\nA bus's seat-km: \(cents(busSeat)) (\(dollars(BusRoute.costPerKilometre.amount)) a bus-km ÷ \(BusRoute.capacity)).")
    }

    /// `world` played `days` days after its first tick: the days' fare
    /// trips, the railway's operating profit (fares less its running
    /// costs) and route `route`'s riders and net.
    private func play(_ world: GameWorld, days: Int, route: BusRouteID?) throws
        -> (fareTrips: Int64, railOperating: Int64, riders: Int64, busNet: Int64) {
        var player = try reportPlayer(world)
        try player.advance(ticks: 1)
        var totals = (fareTrips: Int64(0), railOperating: Int64(0), riders: Int64(0), busNet: Int64(0))
        for _ in 1...days {
            try player.playDay()
            let world = player.world
            if let yesterday = world.accounts.days.first(where: { $0.day == world.dayIndex(of: world.clock.now) - 1 }) {
                totals.fareTrips += yesterday.fareTrips
                totals.railOperating += (yesterday.fareRevenue - yesterday.totalCost).amount
            }
            if let route, let bus = world.busRoute(id: route)?.days.last {
                totals.riders += bus.riders
                totals.busNet += bus.fares.amount - bus.cost.amount
            }
        }
        return totals
    }

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }

    private func cents(_ value: Double) -> String {
        String(format: "$%.3f", value / 100)
    }

    private func ratio(_ a: Double, _ b: Double) -> String {
        b == 0 ? "—" : String(format: "%.2f", a / b)
    }
}
