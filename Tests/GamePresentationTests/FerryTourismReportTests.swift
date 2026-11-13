import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 589: what the ferries earn, run only when asked
/// (`FERRY_TOURISM_REPORT=<days>`). Three maps:
///
/// - the demo: the Tamsui–Bali screenshot scene's game (decision 585 PR-2),
///   a new game at the river mouth with no railway, two boats every 15
///   minutes, played those days;
/// - real Tamsui: the same ferry on a map with a line of the player's own
///   east from MRT Tamsui (the real people read in round the stations, as
///   decision 586's report), so the Bali sight (`t190`) is reached by train
///   to Tamsui and on by boat;
/// - real Gushan–Cijin: the Kaohsiung ferry with a line east from MRT
///   Hamasen, for the Cijin sight (`t105`).
///
/// For each it prints the station the ferry's tourists come through, and
/// for each day whether the boats sail, the sight's tourists (the rail
/// stations' own rule), their crossings, the boats' seats, fares and
/// running, worked out without playing; `FERRY_TOURISM_PLAY=<days>` then
/// plays those days on the real maps and prints the riders the ferry booked
/// (the demo is always played: it is small); `FERRY_BOATS` and
/// `FERRY_MINUTES` change the real maps' boats and headway (two every 15
/// minutes). It asserts nothing: the
/// numbers are in the decision.
@MainActor
final class FerryTourismReportTests: XCTestCase {
    private func reportDays() throws -> Int64 {
        guard let wanted = ProcessInfo.processInfo.environment["FERRY_TOURISM_REPORT"], let days = Int64(wanted), days > 0 else {
            throw XCTSkip("Set FERRY_TOURISM_REPORT=<days> to measure the ferries' riders and money (decision 589).")
        }
        return days
    }

    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testTheDemo() throws {
        let days = try reportDays()
        let water = try WaterGrid(data: Data(contentsOf: Self.root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_water.json")))
        let place = try XCTUnwrap(ScreenshotScene.tamsuiFerry.place)
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude))
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        var world = GameWorld.newGame(anchor: anchor, water: water.cells(frame: frame, bounds: GameWorld.newGameBounds),
                                      steep: water.steepCells(frame: frame, bounds: GameWorld.newGameBounds))
        let piers = try XCTUnwrap(RealFerry.tamsuiBali.piers(in: world))
        let id = try world.createFerryRoute(piers: piers, legMetres: RealFerry.tamsuiBali.legMetres, service: .every(minutes: 15), boats: 2).id
        let route = try XCTUnwrap(world.ferryRoute(id: id))
        print("""

        ### Demo: Tamsui–Bali on a new game, no railway (decision 589), days 0 to \(days - 1)
        stations \(world.stations.count), sights \(world.tourism?.attractions.count ?? 0); feeder trips \(route.feederTrips), local trips \(route.localTrips)
        """)
        try play(&world, id: id, days: days)
    }

    /// Neither city's line through the ferry's station is on sale (only
    /// the lines whose runs the bundle keeps are: in Taipei the Wenhu Line
    /// and the Xinbeitou branch), so a line of the player's own: three
    /// stations on a straight track east from the station by the ferry
    /// (the app's `track_stations.geojson`), 1.1 and 2.2 km apart, one train
    /// of four cars.
    func testRealTamsui() throws {
        try report(ferry: .tamsuiBali, railway: "a line east from MRT Tamsui", sight: "t190") { world in
            try Self.layLine(east: (25.167626, 121.445881), names: ["淡水", "竹圍", "東"], in: &world)
        }
    }

    func testRealGushanCijin() throws {
        try report(ferry: .gushanCijin, railway: "a line east from MRT Hamasen", sight: "t105") { world in
            try Self.layLine(east: (22.621485, 120.274504), names: ["哈瑪星", "鹽埕", "東"], in: &world)
        }
    }

    private static func layLine(east place: (latitude: Double, longitude: Double), names: [String], in world: inout GameWorld) throws {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let (hx, hy) = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let tile = Int64(1_024), cars = 4
        let platform = Int64(cars) * Train.carLength
        let x = Int64(hx.rounded()) - tile - platform / 2, y = Int64(hy.rounded())
        let west = try world.buildTrackNode(at: WorldCoordinate(x: x, y: y))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: x + 140 * tile + platform, y: y))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for (index, name) in names.enumerated() {
            let middle = tile + platform / 2 + Int64(index) * 69 * tile
            let station = try world.buildStation(named: name, at: PlanPoint(x: x + middle, y: y)).id
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
    }

    private func report(ferry: RealFerry, railway: String, sight id: String,
                        build: (inout GameWorld) throws -> Void) throws {
        let days = try reportDays()
        let middle = (latitude: ferry.piers.map(\.latitude).reduce(0, +) / Double(ferry.piers.count),
                      longitude: ferry.piers.map(\.longitude).reduce(0, +) / Double(ferry.piers.count))
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: middle.latitude, longitudeDegrees: middle.longitude))
        let bounds = try WorldBounds(width: 1 << 22, height: 1 << 22)
        var opened = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: Money(200_000_000_000), land: [])
        opened.setLandOnDemand()
        try build(&opened)
        let data = RealWorldData.load(pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        let session = GameSession(world: opened, language: .traditionalChinese)
        session.railways = try BundledRealData.railways()
        session.population = data.population
        session.places = data.places
        session.water = data.water
        // The land, and the water with it, round the stations.
        session.readLandRoundStations()
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        // `FERRY_BOATS`, `FERRY_MINUTES`: the other end of the range (two
        // boats every 15 minutes unless set).
        let environment = ProcessInfo.processInfo.environment
        session.setFerryDraftBoats(environment["FERRY_BOATS"].flatMap { Int($0) } ?? 2)
        session.setFerryDraftMinutesApart(environment["FERRY_MINUTES"].flatMap { Int64($0) } ?? 15)
        session.traceRealFerry(ferry)
        XCTAssertTrue(session.buildFerryRoute(), "\(session.ferryDraft) \(String(describing: session.ferryPreview?.problem)) \(session.message?.text ?? "")")
        var world = session.world
        let route = try XCTUnwrap(world.ferryRoutes.last)
        let sight = try XCTUnwrap(world.tourism?.attractions.first { $0.englishName == AttractionCatalog.spots.first { $0.id == id }?.englishName })
        let name: (StationID?) -> String = { $0.flatMap { world.station(id: $0)?.name } ?? "-" }
        print("""

        ### \(ferry.englishName) with \(railway) (decision 589), days 0 to \(days - 1)
        commuter transfer: \(name(route.transfer?.station)); feeder trips \(route.feederTrips), local trips \(route.localTrips); \
        \(route.metres) m, headway \(route.headway ?? 0) min, \(route.boats) boats
        sight \(sight.name): \(sight.stars) hundredths of a star, \(sight.kind); on foot \(name(world.servingStation(at: sight.point))); \
        its station \(name(world.attractionStation(of: sight.id)))

        | day | weekday | holiday | sails | reached | tourists | crossings | seats | fares | running |
        | --: | --: | --- | --- | --- | --: | --: | --: | --: | --: |
        """)
        for day in 0..<days {
            let sails = world.ferryRouteIsOpen(route.id, onDay: day)
            let access = world.servingStation(at: sight.point) == nil ? world.feederAccess(to: sight.point, onDay: day) : nil
            let reached = access?.feeder == .ferry(route.id)
            let tourists = reached ? world.touristsExpected(for: sight, onDay: day) : 0
            let crossings = min(2 * tourists, route.dailyCapacity(onDay: day))
            print("| \(day) | \(StationDemand.weekday(ofDay: day)) | \(world.holiday(onDay: day) != nil ? "yes" : "") | \(sails ? "yes" : "no") "
                + "| \(reached ? "yes" : "no") | \(tourists) | \(crossings) | \(route.dailyCapacity(onDay: day)) "
                + "| \(crossings * FerryRoute.fare.amount / 100) | \(route.dailyCost(onDay: day).amount / 100) |")
        }
        guard let played = ProcessInfo.processInfo.environment["FERRY_TOURISM_PLAY"].flatMap({ Int64($0) }), played > 0 else { return }
        try play(&world, id: route.id, days: played)
    }

    /// Plays `days` days at the top speed and prints each day the ferry
    /// booked, and the sums.
    private func play(_ world: inout GameWorld, id: FerryRouteID, days: Int64) throws {
        world.setSpeed(.fast)
        let started = Date()
        while world.clock.now.seconds < days * GameTime.secondsPerDay + 60 {
            try world.advance(ticks: 1)
        }
        let route = try XCTUnwrap(world.ferryRoute(id: id))
        print("\n| day | weekday | riders | fares | running | net | closed |\n| --: | --: | --: | --: | --: | --: | --- |")
        var net: Int64 = 0
        for day in route.days {
            net += (day.fares - day.cost).amount
            print("| \(day.day) | \(StationDemand.weekday(ofDay: day.day)) | \(day.riders) | \(day.fares.amount / 100) | \(day.cost.amount / 100) "
                + "| \((day.fares - day.cost).amount / 100) | \(day.closed ? "yes" : "") |")
        }
        print("| all | | \(route.days.map(\.riders).reduce(0, +)) | | | \(net / 100) | |")
        print("played \(days) days in \(Int(Date().timeIntervalSince(started))) s\n")
    }
}
