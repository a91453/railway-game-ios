import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 587: tourists on by bus, run only when asked
/// (`BUS_TOURISM_REPORT=<days>`). It asserts nothing: the numbers are in
/// the decision.
///
/// 1. The balance report's first line (``BalanceReportTests``' own,
///    rebuilt here) with a three-star mountain 2 km past its last
///    station, and a city route of two stops, one by the station and one
///    by the sight, an hour apart with one bus: each day played, the
///    sight's tourists, the route's riders against what its buses hold,
///    and the cash against the same line without the route.
/// 2. The Wenhu Line bought (`trtc:BR`, as decision 586's report buys it)
///    with Taipei's Brown 15 (`TPE10744_0`, 富德 to 貓空纜車站, by MRT
///    Taipei Zoo) laid as a city route with its real stops, lengths and
///    headway: the station it meets, and for each day the Maokong sight's
///    tourists and the rides, worked out without playing; then with the
///    Maokong Gondola built too, which goes first.
@MainActor
final class BusTourismReportTests: XCTestCase {
    private func requestedDays() throws -> Int64 {
        guard let wanted = ProcessInfo.processInfo.environment["BUS_TOURISM_REPORT"], let days = Int64(wanted), days > 0 else {
            throw XCTSkip("Set BUS_TOURISM_REPORT=<days> to measure the tourists taken on by bus (decision 587).")
        }
        return days
    }

    private func dollars(_ cents: Int64) -> String { "NT$\(cents / 100)" }

    // MARK: - 1. The first line

    func testAFirstLineWithASightByBus() throws {
        let days = try requestedDays()
        var plain = try firstLine()
        let last = try XCTUnwrap(plain.stations.last)
        let sightPoint = PlanPoint(x: last.point.x, y: last.point.y + 2_000 * WorldCoordinate.unitsPerMetre)
        plain.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "山", englishName: "Hill",
                                     point: sightPoint, kind: .mountain, baseStars: 300)])
        if plain.roads == nil { plain.enableRoads() }
        let near = CellPosition(row: Int((last.point.y + 192 * WorldCoordinate.unitsPerMetre) / Land.cellLength),
                                column: Int(last.point.x / Land.cellLength))
        let far = CellPosition(row: Int(sightPoint.y / Land.cellLength), column: Int(sightPoint.x / Land.cellLength))
        try plain.setRoads([near, far], in: [LandBlock(cellRow: near.row, column: near.column), LandBlock(cellRow: far.row, column: far.column)])
        var bused = plain
        let route = try bused.createBusRoute(to: nil, stops: [near, far], legMetres: [2_400], service: .every(minutes: 60), buses: 1).id
        let built = try XCTUnwrap(bused.busRoute(id: route))
        let sight = AttractionID(rawValue: 1)
        print("""

        ### The first line with a 3-star mountain 2 km past its last station, a city bus to it (decision 587)
        without the bus: its station \(plain.attractionStation(of: sight).map { "\($0.rawValue)" } ?? "-"); \
        with: \(bused.attractionStation(of: sight).map { "\($0.rawValue)" } ?? "-"), the route meeting \(built.transfer.map { "\($0.station.rawValue)" } ?? "-")
        route: \(built.metres) m, every \(built.headway ?? 0) min, \(built.dailyDepartures) departures, holds \(built.dailyCapacity) a day, costs \(dollars(built.dailyCost.amount)) a day

        | day | weekday | tourists | rides | riders | of them local | balance without | balance with | difference |
        | --: | --: | --: | --: | --: | --: | --: | --: | --: |
        """)
        try plain.advance(ticks: 1)
        try bused.advance(ticks: 1)
        for day in 0..<days {
            let rides = bused.touristFlows(onDay: day) { bused.reaches(from: $0, to: $1, graph: nil) }.flows.feederRides[.bus(route)] ?? 0
            try plain.advance(ticks: 1_440)
            try bused.advance(ticks: 1_440)
            let played = try XCTUnwrap(bused.busRoute(id: route))
            let riders = played.days.last?.riders ?? 0
            let tourists = bused.attraction(id: sight)?.yesterday ?? 0
            print("| \(day) | \(StationDemand.weekday(ofDay: day)) | \(tourists) | \(rides) | \(riders) | \(played.localTrips) "
                + "| \(dollars(plain.economy.balance.amount)) | \(dollars(bused.economy.balance.amount)) "
                + "| \(dollars((bused.economy.balance - plain.economy.balance).amount)) |")
        }
    }

    /// BalanceReportTests' first line: three stations on a 28-tile track
    /// across the new game's middle, one train of four cars.
    private func firstLine() throws -> GameWorld {
        var world = GameWorld.newGame()
        let tile = Int64(1_024)
        let cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = GameWorld.newGameBounds.width / 2 - 16 * tile, y = GameWorld.newGameBounds.height / 2
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x + 2 * tile, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 30 * tile, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for middle in [tile + platform / 2, 14 * tile, 27 * tile - platform / 2] {
            let station = try world.buildStation(named: "S\(stops.count)", at: PlanPoint(x: x + 2 * tile + middle, y: y)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Line 1", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "Train 1").id
        try world.setTrainCars(train, to: cars)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        return world
    }

    // MARK: - 2. Brown 15 to Maokong

    func testBrownFifteenToMaokong() throws {
        let days = try requestedDays()
        let railways = try BundledRealData.railways()
        let runs = try XCTUnwrap(railways.metroRuns["trtc:BR"])
        let stations = try runs.stops.map { try BundledRealData.station($0, in: "mrt") }
        let latitude = stations.map(\.coordinate.latitude).reduce(0, +) / Double(stations.count)
        let longitude = stations.map(\.coordinate.longitude).reduce(0, +) / Double(stations.count)
        let anchor = try XCTUnwrap(GeoAnchor(latitude: Int64((latitude * 10_000_000).rounded()), longitude: Int64((longitude * 10_000_000).rounded())))
        var opened = GameWorld.newGame(anchor: anchor, bounds: try WorldBounds(width: 1 << 21, height: 1 << 21), balance: Money(200_000_000_000), land: [])
        opened.setLandOnDemand()
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let session = GameSession(world: opened, language: .traditionalChinese)
        session.railways = railways
        session.population = data.population
        session.places = data.places
        session.water = data.water
        let wenhu = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:BR" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: wenhu)), session.message?.text ?? "")
        var world = session.world

        // Brown 15, as the bundle keeps it: its stops on the map, each on a
        // road, its legs the shape's metres between them.
        let file = try Data(contentsOf: BundledRealData.directory.deletingLastPathComponent().appendingPathComponent("RealBuses/real_buses_Taipei.json"))
        let routes = try RealBusRoute.routes(in: file, city: "Taipei", scale: 1e-5)
        let brown = try XCTUnwrap(routes.first { $0.id == "Taipei/TPE10744_0" })
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let cells = brown.stops.map { stop -> CellPosition in
            let (x, y) = frame.worldPosition(latitude: stop.coordinate.latitude, longitude: stop.coordinate.longitude)
            return CellPosition(row: Int(y.rounded()) / Int(Land.cellLength), column: Int(x.rounded()) / Int(Land.cellLength))
        }
        if world.roads == nil { world.enableRoads() }
        try world.setRoads(cells, in: cells.map { LandBlock(cellRow: $0.row, column: $0.column) })
        let legs = zip(brown.stops, brown.stops.dropFirst()).map { Int64(max(1, $1.metres - $0.metres)) }
        let roundTrip = (2 * legs.reduce(0, +) * 60 + BusRoute.metresPerHour - 1) / BusRoute.metresPerHour + BusRoute.layoverMinutes
        let buses = Int((roundTrip + Int64(brown.headwayMinutes) - 1) / Int64(brown.headwayMinutes))
        let id = try world.createBusRoute(to: nil, stops: cells, legMetres: legs, service: .every(minutes: Int64(brown.headwayMinutes)), buses: buses).id
        let route = try XCTUnwrap(world.busRoute(id: id))
        let sight = try XCTUnwrap(world.tourism?.attractions.first { $0.englishName == "Maokong" })
        let meets = route.transfer.flatMap { world.station(id: $0.station)?.name } ?? "-"
        print("""

        ### Brown 15 meeting the Wenhu Line (decision 587), days 0 to \(days - 1)
        route: \(brown.stops.count) stops, \(route.metres) m, every \(route.headway ?? 0) min with \(buses) buses, \(route.dailyDepartures) departures, \
        holds \(route.dailyCapacity) a day, costs \(dollars(route.dailyCost.amount)) a day; meets \(meets) at stop \(route.transfer.map { "\($0.stop)" } ?? "-"); \
        feeder trips \(route.feederTrips), local trips \(route.localTrips)
        stations near its stops: \(world.stations.filter { ["動物園", "木柵", "木柵機廠"].contains($0.name) }.map { "\($0.name) \(world.stationDemand(of: $0.id)?.dailyTrips ?? 0) trips\($0.isDepot ? " (depot)" : "")" }.joined(separator: ", "))
        sight: \(sight.stars) hundredths of a star, \(sight.kind); its station \(world.attractionStation(of: sight.id).flatMap { world.station(id: $0)?.name } ?? "-")
        """)
        table(world, sight: sight, days: days, title: "Brown 15 alone")

        let maokong = RealCableway.maokong
        try world.createCableway(stops: try XCTUnwrap(maokong.stops(in: world)), legMetres: maokong.legMetres, meetsNear: maokong.meetsNear(in: world))
        table(world, sight: sight, days: days, title: "Brown 15 and the Maokong Gondola")
    }

    private func table(_ world: GameWorld, sight: Attraction, days: Int64, title: String) {
        print("""

        #### \(title)

        | day | weekday | holiday | by | tourists | rides | fares |
        | --: | --: | --- | --- | --: | --: | --: |
        """)
        var totals: [String: Int64] = [:]
        for day in 0..<days {
            let access = world.feederAccess(to: sight.point, onDay: day)
            let tourists = access == nil ? 0 : world.touristsExpected(for: sight, onDay: day)
            let (by, fare): (String, Money) = switch access?.feeder {
            case .bus?: ("bus", BusRoute.fare)
            case .cableway?: ("cableway", Cableway.fare)
            case nil: ("-", .zero)
            }
            totals[by, default: 0] += 2 * tourists
            print("| \(day) | \(StationDemand.weekday(ofDay: day)) | \(world.holiday(onDay: day) != nil ? "yes" : "") | \(by) "
                + "| \(tourists) | \(2 * tourists) | \(dollars(2 * tourists * fare.amount)) |")
        }
        print("rides: " + totals.keys.sorted().map { "\($0) \(totals[$0]!)" }.joined(separator: ", ") + "\n")
    }
}
