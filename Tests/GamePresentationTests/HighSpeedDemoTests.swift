import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The high-speed demo (ARCHITECTURE decision 170, the author's idea of
/// 2026-10-11): the real Taiwan High Speed Rail built as the game's own
/// track on its real alignment, with its twelve stations and three stopping
/// patterns running at once.
final class HighSpeedDemoTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func railways() throws -> RealRailways {
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        return try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
    }

    static let population = try? PopulationGrid(
        data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json"))
    )

    static let places = try? PlaceGrid(
        data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_places.json"))
    )

    private static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// The layout as the game builds it, then built on a world with just
    /// what it costs on top of a new game's money, and not run: the tracks,
    /// the stations and the sets as they stand at midnight. Built once for
    /// every test that needs it: it takes a minute in a debug build.
    private static let built: Result<(layout: HighSpeedDemo.Layout, world: GameWorld, tracks: Tracks), Error> = Result {
        let layout = try HighSpeedDemo.Layout(railways: railways())
        var world = HighSpeedDemo.newWorld(paying: layout.cost(at: ConstructionCosts.newGame), eventSeed: 1)
        let (down, up) = try layout.build(in: &world, language: .english)
        return (layout, world, Tracks(layout: layout, down: down, up: up))
    }

    /// The two tracks' edges, as built (the demo's game builds the same).
    struct Tracks {
        let down: [TrackEdgeID]
        let upInOrder: [TrackEdgeID]
        let up: Set<TrackEdgeID>
        /// The down track's edges between the two turnouts, where only
        /// southbound sets run: beyond them are the ends' platforms, where
        /// the sets turn back.
        let between: Set<TrackEdgeID>

        init(layout: HighSpeedDemo.Layout, down: RealWorldDemo.Track, up: RealWorldDemo.Track) {
            self.down = down.edges
            upInOrder = up.edges
            self.up = Set(up.edges)
            let distances = layout.plan.distances
            between = Set(down.edges.indices.filter {
                distances[$0] >= layout.junctions.north - 1 && distances[$0 + 1] <= layout.junctions.south + 1
            }.map { down.edges[$0] })
        }

        /// Whether a set travelling `traversal` runs against its track: on
        /// the down track between the turnouts northbound, or on the up
        /// track southbound.
        func isAgainst(_ traversal: TrackTraversal) -> Bool {
            (between.contains(traversal.edge) && traversal.direction == .backward) || (up.contains(traversal.edge) && traversal.direction == .forward)
        }
    }

    /// The demo as the game opens it, with the people round its stations.
    private static let opened: Result<GameWorld, Error> = Result {
        try HighSpeedDemo.make(in: .english, railways: railways(), population: population, places: places)
    }

    // MARK: - The track and the stations

    func testItBuildsTheRealHighSpeedRailsTwelveStations() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(
            world.stations.map(\.name),
            ["Nangang", "Taipei", "Banqiao", "Taoyuan", "Hsinchu", "Miaoli", "Taichung", "Changhua", "Yunlin", "Chiayi", "Tainan", "Zuoying"]
        )
    }

    func testItsStationsStandWhereTheRealOnesDo() throws {
        let (layout, world, _) = try Self.built.get()
        for (station, stop) in zip(world.stations, layout.stops) {
            let east = Double(station.point.x) - stop.point.x
            let south = Double(station.point.y) - stop.point.y
            // The platform is on the track, which passes the real station
            // within a few hundred metres.
            XCTAssertLessThan((east * east + south * south).squareRoot() / Self.metre, 500, station.name)
        }
    }

    func testItsTrackIsTheRealAlignmentsLength() throws {
        let (layout, world, tracks) = try Self.built.get()
        func length(_ edges: some Sequence<TrackEdgeID>) -> Int64 {
            edges.reduce(0) { $0 + (world.network.edge($1)?.length ?? 0) }
        }
        let track = length(tracks.down)
        let real = layout.plan.path.length
        // From Nangang's end to Zuoying's: about 352 km; the cubic edges
        // are a few metres either side of the polyline.
        XCTAssertEqual(Double(track) / Self.metre / 1_000, 352.2, accuracy: 2)
        XCTAssertEqual(Double(track), real, accuracy: real * 0.005)
        XCTAssertLessThan(tracks.down.count, 300, "the track is fitted loosely: every edge is checked against all before it")
        // The up track runs beside it from turnout to turnout: as long
        // within a few metres (the inside of a curve is shorter), and the
        // two make up the whole network.
        XCTAssertEqual(Double(length(tracks.up)), Double(length(tracks.between)), accuracy: 30 * Self.metre)
        XCTAssertEqual(tracks.down.count + tracks.up.count, world.network.edges.count)
    }

    /// Double track: between its ramps the up track runs 5 m beside the
    /// down track, the middle of each of its edges about that far from the
    /// middle of the down track's edge beside it (on a curve the two
    /// middles are a little apart along the track too, and the inner edge
    /// bows a little); the game would refuse track closer than 4 m
    /// (``GameError/trackTooClose(_:)``).
    func testItsTwoTracksRunSideBySide() throws {
        let (layout, world, tracks) = try Self.built.get()
        func middle(_ id: TrackEdgeID) throws -> WorldCoordinate {
            let geometry = try XCTUnwrap(world.network.geometry(of: id))
            return geometry.location(at: geometry.length / 2).position
        }
        var apart: [Double] = []
        for index in 1..<(tracks.upInOrder.count - 1) {
            let twin = try XCTUnwrap(layout.plan.distances.firstIndex(of: layout.up.distances[index]))
            let (a, b) = (try middle(tracks.upInOrder[index]), try middle(tracks.down[twin]))
            let (dx, dy) = (Double(a.x - b.x), Double(a.y - b.y))
            apart.append((dx * dx + dy * dy).squareRoot() / Self.metre)
        }
        XCTAssertGreaterThan(apart.count, 200)
        XCTAssertGreaterThan(apart.min() ?? 0, 4.0)
        XCTAssertLessThan(apart.max() ?? .infinity, 5.5)
    }

    // MARK: - The line and its sets

    func testItsLineCallsAtAllTwelveStationsAndIsAHighSpeedLine() throws {
        let world = try Self.built.get().world
        let line = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(world.lines.count, 1)
        XCTAssertEqual(line.stops, world.stations.map(\.id))
        XCTAssertEqual(line.patterns.map(\.calls), [[0, 1, 2, 3, 4, 6, 9, 10, 11], [0, 1, 2, 6, 11]])
        XCTAssertTrue(line.isHighSpeed, "planned at PERF_HSR: the line is a high-speed line (decision 168)")
        XCTAssertEqual(line.window, .standard, "the real day's first train is at 06:00 and the last at midnight")
        XCTAssertFalse(world.isTrafficControlEnabled, "route reservation over 30 to 180 km legs would take the game minutes an hour")
        XCTAssertFalse(world.doorCrowding, "dwells do not lengthen in a crowd, as in the other demos (decision 169)")
    }

    func testItsSetsAreTwelveCarHighSpeedSets() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(world.trains.count, HighSpeedDemo.services.reduce(0) { $0 + $1.sets })
        for train in world.trains {
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 12, train.name)
            XCTAssertEqual(train.performance, .highSpeed, train.name)
            XCTAssertEqual(train.capacity, 960, "12 cars of 80, not overloaded")
        }
    }

    /// The sets of every service are what its headway needs of its round
    /// trip on the track as built (the money to buy them is worked out
    /// from the count before anything is built).
    func testEveryServiceHasTheSetsItsHeadwayNeeds() throws {
        let world = try Self.built.get().world
        let line = try XCTUnwrap(world.lines.first)
        for (index, service) in HighSpeedDemo.services.enumerated() {
            let pattern: Int? = index == 0 ? nil : index - 1
            let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: pattern), service.english)
            XCTAssertEqual(
                HighSpeedDemo.sets(roundTripMinutes: journey.roundTripMinutes, headway: service.headway), service.sets,
                "\(service.english): a round trip of \(journey.roundTripMinutes) minutes every \(service.headway)"
            )
            XCTAssertEqual((index == 0 ? line.trains : line.patterns[index - 1].trains).count, service.sets, service.english)
            XCTAssertEqual(
                index == 0 ? line.targetHeadways : line.patterns[index - 1].targetHeadways,
                TargetHeadways(peak: service.headway, offPeak: service.headway, low: service.headway), service.english
            )
        }
    }

    /// Each way keeps to its own track (the author saw the sets of the two
    /// ways run through each other on what was one track): every leg of
    /// every service, as the game drives it, runs southbound on the down
    /// track only and northbound on the up track, turning back only beyond
    /// the turnouts at the ends.
    func testEveryLegKeepsToItsWaysTrack() throws {
        let (_, world, tracks) = try Self.built.get()
        let line = try XCTUnwrap(world.lines.first)
        for (index, service) in HighSpeedDemo.services.enumerated() {
            let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: index == 0 ? nil : index - 1), service.english)
            XCTAssertEqual(journey.legs.count, 2 * (service.stops.count - 1), service.english)
            for leg in journey.legs {
                let southbound = leg.to > leg.from
                for traversal in leg.path.traversals {
                    let place = "\(service.english), \(leg.from) to \(leg.to)"
                    XCTAssertFalse(tracks.isAgainst(traversal), place)
                    XCTAssertFalse((southbound ? tracks.up : tracks.between).contains(traversal.edge), "\(place): on the other way's track")
                }
            }
        }
    }

    /// The game starts with the money of a new game: what the track, the
    /// stations and the sets cost was added to it.
    func testItIsPaidForBeforeItStarts() throws {
        let world = try Self.built.get().world
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance)
    }

    func testItSavesAndLoads() throws {
        let world = try Self.built.get().world
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
    }

    // MARK: - The game as it opens

    func testItOpensAtSevenWithTheSetsOnTheirWay() throws {
        let world = try Self.opened.get()
        XCTAssertEqual(world.clock.now.minute, 7 * 60)
        XCTAssertEqual(world.clock.speed, .normal, "it runs at once, like the other demos")
        XCTAssertFalse(world.doorCrowding)
        XCTAssertEqual(world.stations.count, 12)
        // The first set of each kind left at six, a third and a half more
        // since: seven by seven o'clock, spread along the line, the first
        // already past Taichung (the edges are numbered from Nangang).
        let running = world.trains.filter { $0.execution != nil }
        XCTAssertGreaterThanOrEqual(running.count, 7)
        let down = try Self.built.get().tracks.down
        let along = running.compactMap { train -> Int? in
            if case .onEdge(let traversal, _) = train.position { return down.firstIndex(of: traversal.edge) }
            return nil
        }
        XCTAssertEqual(along.count, running.count, "all southbound so far, on the down track")
        XCTAssertGreaterThanOrEqual(Set(along).count, 5, "spread along the line")
        XCTAssertGreaterThan(along.max() ?? 0, down.count / 2, "the first sets are in the south")
    }

    /// The game as it runs, from 07:00 to half past seven the next morning,
    /// every ten minutes: no set runs against its way's track, so no two
    /// sets going opposite ways are ever on the same track; both tracks
    /// are used all day; and the next morning the sets are out again.
    func testItsSetsKeepToTheirWaysTracksAllDay() throws {
        var world = try Self.opened.get()
        let tracks = try Self.built.get().tracks
        world.setSpeed(.fast)
        var seen = (down: 0, up: 0)
        for _ in 0..<(6 * 24 + 3) {
            try world.advance(ticks: 1)
            for train in world.trains where train.execution != nil {
                guard case .onEdge(let traversal, _)? = train.position else { continue }
                XCTAssertFalse(tracks.isAgainst(traversal), "\(train.name) at minute \(world.clock.now.minute)")
                if tracks.between.contains(traversal.edge) { seen.down += 1 }
                if tracks.up.contains(traversal.edge) { seen.up += 1 }
            }
        }
        XCTAssertGreaterThan(seen.down, 500)
        XCTAssertGreaterThan(seen.up, 500)
        XCTAssertEqual(world.clock.now.minute % 1_440, 7 * 60 + 30)
        XCTAssertGreaterThanOrEqual(world.trains.filter { $0.execution != nil }.count, 7, "the sets are out again")
    }

    func testPeopleLiveRoundItsStationsAndTravelBetweenThem() throws {
        try XCTSkipIf(Self.population == nil, "The population file is not here.")
        let world = try Self.opened.get()
        var total: Int64 = 0
        for station in world.stations {
            let hinterland = try XCTUnwrap(world.stationDemand(of: station.id)?.hinterland, station.name)
            XCTAssertGreaterThan(hinterland, 100_000, "\(station.name): the people within 8 km")
            total += hinterland
        }
        XCTAssertGreaterThan(total, 10_000_000, "Taipei, Taichung and Kaohsiung's towns are in it")
        // An hour of the day has passed with the people there: passengers
        // were released at the stations and some have arrived.
        XCTAssertGreaterThan(world.passengers.reduce(0) { $0 + $1.released }, 0)
        XCTAssertGreaterThan(world.passengers.reduce(0) { $0 + $1.arrived }, 0)
    }

    // MARK: - The game launcher

    /// The launcher builds it off the main actor, says so while it does,
    /// and opens the game when it is built.
    @MainActor
    func testTheLauncherBuildsAndOpensIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HighSpeedDemoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let railways = try Self.railways()
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.population = Self.population
        launcher.places = Self.places
        let task = launcher.openHighSpeedDemo(railways: railways)
        // A second tap while it builds does nothing.
        XCTAssertNil(launcher.openHighSpeedDemo(railways: railways), "one build at a time")
        XCTAssertTrue(launcher.isOpeningHighSpeedDemo)
        XCTAssertNil(launcher.session, "still on the start screen")
        await task?.value
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertEqual(launcher.session?.world.stations.count, 12, "the game is open")
        XCTAssertEqual(launcher.session?.world.lines.first?.isHighSpeed, true)
        try XCTSkipIf(Self.population == nil, "The population file is not here.")
        let taipei = try XCTUnwrap(launcher.session?.world.stations.first { $0.name == "Taipei" })
        XCTAssertGreaterThan(launcher.session?.world.stationDemand(of: taipei.id)?.hinterland ?? 0, 1_000_000, "the people were handed to the build")
    }

    /// A game the player starts while it builds is not taken over by it.
    @MainActor
    func testAGameStartedWhileItBuildsStays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HighSpeedDemoTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let task = launcher.openHighSpeedDemo(railways: try Self.railways())
        launcher.openDemo()
        let simple = try XCTUnwrap(launcher.session?.world)
        await task?.value
        XCTAssertFalse(launcher.isOpeningHighSpeedDemo)
        XCTAssertEqual(launcher.session?.world, simple, "the simple demo is still the game being played")
    }

    // MARK: - Report

    /// What the demo is, measured: the track, what it costs, the services
    /// and two days' accounts. Printed, and only on request:
    ///
    ///     HSR_DEMO_REPORT=1 swift test -c release -Xswiftc -enable-testing --filter HighSpeedDemoTests/testReport
    func testReport() throws {
        guard ProcessInfo.processInfo.environment["HSR_DEMO_REPORT"] != nil else { throw XCTSkip("Set HSR_DEMO_REPORT=1.") }
        func say(_ text: String) {
            FileHandle.standardError.write(Data((text + "\n").utf8))
        }
        var clock = Date()
        func lap(_ what: String) {
            say("\(what): \(String(format: "%.2f", Date().timeIntervalSince(clock))) s")
            clock = Date()
        }
        let railways = try Self.railways()
        let layout = try HighSpeedDemo.Layout(railways: railways)
        say("\(layout.plan.curves.count) edges, \(Int(layout.plan.path.length / Self.metre / 1_000)) km; costs \(layout.cost(at: ConstructionCosts.newGame).moneyText)")
        clock = Date()
        var world = try HighSpeedDemo.make(in: .english, railways: railways, population: Self.population, places: Self.places)
        lap("make")
        say("at \(world.clock.now.minute / 60):00, balance \(world.economy.balance.moneyText); stations \(world.stations.count), sets \(world.trains.count), edges \(world.network.edges.count), land cells \(world.land.cells.count)")
        for line in world.lines {
            let services: [(pattern: Int?, calls: Int, sets: Int)] =
                [(nil, line.stops.count, line.trains.count)] + line.patterns.enumerated().map { ($0.offset, $0.element.calls.count, $0.element.trains.count) }
            for (service, entry) in services.enumerated() {
                let journey = world.lineJourney(line.id, pattern: entry.pattern)
                say("service \(service): \(entry.calls) calls, \(entry.sets) sets, round trip \(journey?.roundTripMinutes ?? -1) min")
            }
        }
        say("hinterlands \(world.stations.map { world.stationDemand(of: $0.id)?.hinterland ?? 0 })")
        let ordinary = world.stations.map { world.stationDemand(of: $0.id)?.dailyTrips ?? 0 }
        say("stations' own daily trips \(ordinary), together \(ordinary.reduce(0, +))")
        // To midnight, then two whole days.
        try world.advance(ticks: Int(1_440 - world.clock.now.minute % 1_440))
        for _ in 1...2 {
            try world.advance(ticks: 1_440)
            lap("day")
            if let last = world.accounts.days.last {
                say("day \(last.day): trips \(last.fareTrips), fares \(last.fareRevenue.moneyText), costs \(last.totalCost.moneyText), balance \(world.economy.balance.moneyText)")
            }
        }
        let released = world.passengers.reduce(0) { $0 + $1.released }
        let arrived = world.passengers.reduce(0) { $0 + $1.arrived }
        let overflowed = world.passengers.reduce(0) { $0 + $1.overflowed }
        let abandoned = world.passengers.reduce(0) { $0 + $1.abandoned }
        say("released \(released), arrived \(arrived), overflowed \(overflowed), abandoned \(abandoned)")
        let data = try JSONEncoder().encode(SavedGame(world: world))
        lap("encode \(data.count / 1_000) kB")
        _ = try JSONDecoder().decode(SavedGame.self, from: data)
        lap("decode")
    }
}
