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
        let away = switch ProcessInfo.processInfo.environment["BUS_DIRECTION"] {
        case "toward": (x: -out.x, y: -out.y)
        case "side": (x: -out.y, y: out.x)
        default: out
        }
        let length = FixedPoint.roundedSquareRoot(away.x * away.x + away.y * away.y)
        func point(metres: Int64) -> PlanPoint {
            let units = metres * WorldCoordinate.unitsPerMetre
            return PlanPoint(x: station.location.x + away.x * units / length, y: station.location.y + away.y * units / length)
        }
        func cell(_ point: PlanPoint) -> CellPosition {
            CellPosition(row: Int(point.y / Land.cellLength), column: Int(point.x / Land.cellLength))
        }
        let cells = Set(stride(from: Int64(0), through: 2_000, by: 16).map { cell(point(metres: $0)) })
        let blocks = Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })
        try fed.setRoads(Array(cells), in: Array(blocks))
        let stops = [1_800, 1_400, 1_000].map { cell(point(metres: $0)) }
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

    private func dollars(_ cents: Int64) -> String {
        "$\(cents / 100)"
    }
}
