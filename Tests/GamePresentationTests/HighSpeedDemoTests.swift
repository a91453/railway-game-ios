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
        let schedule = try file("thsr-schedule.json")
        return try RealRailways(
            lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"),
            operations: RealRailwayOperations(systems: [:], timetables: [:], schedules: ["thsr": schedule])
        )
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
        let built = try layout.build(in: &world, language: .english)
        return (layout, world, Tracks(layout: layout, built: built))
    }

    /// The tracks' edges, as built (the demo's game builds the same).
    struct Tracks {
        let down: [TrackEdgeID]
        let upInOrder: [TrackEdgeID]
        let up: Set<TrackEdgeID>
        /// The down track's edges between the two turnouts, where only
        /// southbound sets run: beyond them are the ends' platforms, where
        /// the sets turn back.
        let between: Set<TrackEdgeID>
        /// Every loop beside the down track and the up track, the second
        /// loops too.
        let downLoops: Set<TrackEdgeID>
        let upLoops: Set<TrackEdgeID>
        let crossovers: Set<TrackEdgeID>
        let yards: Set<TrackEdgeID>
        /// The track run both ways: the ends' yards, and at the stations
        /// where sets turn back, everything from one crossover to the other
        /// (decision 197).
        let bothWays: Set<TrackEdgeID>

        init(layout: HighSpeedDemo.Layout, built: HighSpeedDemo.Built) {
            down = built.down.edges
            upInOrder = built.up.edges
            up = Set(built.up.edges)
            let distances = layout.plan.distances
            between = Set(down.indices.filter {
                distances[$0] >= layout.junctions.north - 1 && distances[$0 + 1] <= layout.junctions.south + 1
            }.map { built.down.edges[$0] })
            downLoops = Set((built.loops + built.outerLoops).flatMap(\.down.edges))
            upLoops = Set((built.loops + built.outerLoops).flatMap(\.up.edges))
            crossovers = Set(built.crossovers)
            yards = Set(built.yards.flatMap(\.edges))
            var bothWays = crossovers.union(yards)
            for reach in layout.turnbackReach.values {
                func within(_ track: RealWorldDemo.Track) -> [TrackEdgeID] {
                    let d = track.plan.distances
                    return track.edges.indices.filter { reach.contains(d[$0]) && reach.contains(d[$0 + 1]) }.map { track.edges[$0] }
                }
                bothWays.formUnion(within(built.down))
                bothWays.formUnion(within(built.up))
                for loop in built.loops + built.outerLoops {
                    bothWays.formUnion(within(loop.down))
                    bothWays.formUnion(within(loop.up))
                }
            }
            self.bothWays = bothWays
        }

        /// The edges only southbound sets run on, and only northbound.
        var southbound: Set<TrackEdgeID> { between.union(downLoops).subtracting(bothWays) }
        var northbound: Set<TrackEdgeID> { up.union(upLoops).subtracting(bothWays) }

        /// Whether a set travelling `traversal` runs against its track: on
        /// a southbound edge northbound or the other way round (every edge
        /// runs north to south).
        func isAgainst(_ traversal: TrackTraversal) -> Bool {
            (southbound.contains(traversal.edge) && traversal.direction == .backward)
                || (northbound.contains(traversal.edge) && traversal.direction == .forward)
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
        // A loop beside each track at each of the ten stations between the
        // ends, a second at Taichung, a crossover north of Taichung and one
        // south of Taipei, where sets turn back, and the two ends' yards:
        // with them, the whole network.
        XCTAssertEqual(tracks.downLoops.count, 33)
        XCTAssertEqual(tracks.upLoops.count, 33)
        XCTAssertEqual(tracks.crossovers.count, 2)
        XCTAssertEqual(
            tracks.down.count + tracks.up.count + tracks.downLoops.count + tracks.upLoops.count + tracks.crossovers.count + tracks.yards.count,
            world.network.edges.count
        )
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

    // MARK: - The lines and their sets

    /// The real day's three kinds of train (decision 197): a line each,
    /// calling at its stations, with the day's trains as runs.
    func testItsLinesAreTheRealDaysThreeKindsOfTrain() throws {
        let (layout, world, _) = try Self.built.get()
        let ids = world.stations.map(\.id)
        XCTAssertEqual(world.lines.map { $0.stops.map { ids.firstIndex(of: $0)! } }, [Array(0..<12), [0, 1, 2, 3, 4, 6, 9, 10, 11], [0, 1, 2, 6, 11]])
        for (line, planned) in zip(world.lines, layout.timetable.lines) {
            XCTAssertTrue(line.patterns.isEmpty, "a line with runs has no stopping patterns (decision 133)")
            XCTAssertTrue(line.isHighSpeed, "planned at PERF_HSR: a high-speed line (decision 168)")
            XCTAssertEqual(line.runs, planned.runs)
        }
        // The 169 real trains and the positioning runs.
        XCTAssertEqual(layout.timetable.lines.map { $0.runs.count - $0.positioning }, [59, 60, 50])
        XCTAssertEqual(layout.timetable.lines.map(\.positioning), [7, 4, 11])
        XCTAssertFalse(world.isTrafficControlEnabled, "decision 197: under traffic control the real day cannot be run")
        XCTAssertFalse(world.doorCrowding, "dwells do not lengthen in a crowd, as in the other demos (decision 169)")
        XCTAssertFalse(world.keepLeft, "its routes are as they were measured; its up line is laid west of the down line already (decision 202)")
        XCTAssertFalse(world.realisticOperation, "it runs the real timetable, whose times its trains keep to (decision 207)")
    }

    /// Each line runs the same day again and again: the day's runs and
    /// positioning runs leave as many sets at each station as it began
    /// with, and the first run of each set leaves from where it stands.
    func testEachLinesDayEndsWhereItBegan() throws {
        let timetable = try Self.built.get().layout.timetable
        for line in timetable.lines {
            var change = [Int: Int]()
            for run in line.runs {
                change[line.stops[run.from], default: 0] -= 1
                change[line.stops[run.to], default: 0] += 1
            }
            XCTAssertTrue(change.values.allSatisfy { $0 == 0 }, "\(line.english): \(change)")
        }
        XCTAssertEqual(timetable.lines.map(\.sets), [14, 11, 10], "35 sets; the real High Speed Rail has 34")
    }

    func testItsSetsAreTwelveCarHighSpeedSets() throws {
        let (layout, world, _) = try Self.built.get()
        XCTAssertEqual(world.trains.count, layout.sets)
        for train in world.trains {
            XCTAssertEqual(train.type, .highSpeed, train.name)
            XCTAssertEqual(train.cars, 12, train.name)
            XCTAssertEqual(train.performance, .highSpeed, train.name)
            XCTAssertEqual(train.capacity, 960, "12 cars of 80, not overloaded")
        }
    }

    /// At midnight every set stands at a platform of the station its first
    /// run leaves, facing the way it goes.
    func testEverySetStandsWhereItsFirstRunLeaves() throws {
        let (layout, world, _) = try Self.built.get()
        for (line, planned) in zip(world.lines, layout.timetable.lines) {
            XCTAssertEqual(line.trains.count, planned.sets, planned.english)
            var expected = planned.overnight.map { "\($0.station)\($0.southbound)" }.sorted()
            var found: [String] = []
            for id in line.trains {
                let train = try XCTUnwrap(world.train(id: id))
                guard case .onEdge(let traversal, _)? = train.position,
                      let station = world.stationsStoppedAt(by: id).first, let index = world.stations.firstIndex(where: { $0.id == station })
                else { XCTFail("\(train.name) stands at no station"); continue }
                found.append("\(index)\(traversal.direction == .forward)")
            }
            found.sort()
            expected.sort()
            XCTAssertEqual(found, expected, planned.english)
        }
    }

    /// Each way keeps to its own track (the author saw the sets of the two
    /// ways run through each other on what was one track): every leg of
    /// every line, as the game drives it, runs southbound on the down
    /// track (and its loops) only and northbound on the up track, but where
    /// sets turn back; the all-stops sets call on the loops, and the
    /// expresses never use them.
    func testEveryLegKeepsToItsWaysTrack() throws {
        let (_, world, tracks) = try Self.built.get()
        for (index, line) in world.lines.enumerated() {
            let journey = try XCTUnwrap(world.lineJourney(line.id, pattern: nil), line.name)
            XCTAssertEqual(journey.legs.count, 2 * (line.stops.count - 1), line.name)
            for leg in journey.legs {
                let southbound = leg.to > leg.from
                for traversal in leg.path.traversals {
                    let place = "\(line.name), \(leg.from) to \(leg.to)"
                    XCTAssertFalse(tracks.isAgainst(traversal), place)
                    XCTAssertFalse((southbound ? tracks.northbound : tracks.southbound).contains(traversal.edge), "\(place): on the other way's track")
                    if index > 0 { XCTAssertFalse(tracks.downLoops.union(tracks.upLoops).contains(traversal.edge), "\(place): an express on a loop") }
                }
                if index == 0, leg.to != 0, leg.to != 11, let last = leg.path.traversals.last {
                    XCTAssertTrue((southbound ? tracks.downLoops : tracks.upLoops).contains(last.edge), "\(leg.from) to \(leg.to): stops on the loop")
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

    /// At 07:00 every run due by then has sent its set out, both ways.
    func testItOpensAtSevenWithTheSetsOnTheirWay() throws {
        let world = try Self.opened.get()
        let tracks = try Self.built.get().tracks
        XCTAssertEqual(world.clock.now.minute, 7 * 60)
        XCTAssertEqual(world.clock.speed, .normal, "it runs at once, like the other demos")
        XCTAssertFalse(world.doorCrowding)
        XCTAssertEqual(world.stations.count, 12)
        for line in world.lines {
            for (index, run) in line.runs.enumerated() where run.times[0].departure <= 7 * 3_600 {
                XCTAssertEqual(line.runDays[index], 0, "\(line.name): the run leaving at \(run.times[0].departure / 60) min has gone")
            }
        }
        var ways = (south: 0, north: 0)
        for train in world.trains where train.execution != nil {
            guard case .onEdge(let traversal, _)? = train.position else { continue }
            if tracks.southbound.contains(traversal.edge) { ways.south += 1 }
            if tracks.northbound.contains(traversal.edge) { ways.north += 1 }
        }
        XCTAssertGreaterThanOrEqual(ways.south, 4, "sets on their way south")
        XCTAssertGreaterThanOrEqual(ways.north, 4, "and north")
    }

    /// The game as it runs, from 07:00 to half past seven the next morning,
    /// every ten minutes: no set runs against its way's track, so no two
    /// sets going opposite ways are ever on the same track (but where sets
    /// turn back); both tracks are used all day; no set is more than a few
    /// minutes late; no run is dropped; and the next morning's runs leave
    /// again (decision 197).
    func testItsSetsKeepToTheRealDay() throws {
        var world = try Self.opened.get()
        let tracks = try Self.built.get().tracks
        world.setSpeed(.fast)
        var seen = (down: 0, up: 0)
        var latest: Int64 = 0
        for _ in 0..<(6 * 24 + 3) {
            try world.advance(ticks: 1)
            for train in world.trains where train.execution != nil {
                latest = max(latest, world.lateness(of: train.id) ?? 0)
                guard case .onEdge(let traversal, _)? = train.position else { continue }
                XCTAssertFalse(tracks.isAgainst(traversal), "\(train.name) at minute \(world.clock.now.minute)")
                if tracks.southbound.contains(traversal.edge) { seen.down += 1 }
                if tracks.northbound.contains(traversal.edge) { seen.up += 1 }
            }
        }
        XCTAssertGreaterThan(seen.down, 500)
        XCTAssertGreaterThan(seen.up, 500)
        XCTAssertLessThan(latest, 5 * 60, "on the real timetable, a few minutes late at most")
        XCTAssertEqual(world.clock.now.minute % 1_440, 7 * 60 + 30)
        let now = world.clock.now.seconds - GameTime.secondsPerDay
        for line in world.lines {
            for (index, run) in line.runs.enumerated() {
                let day: Int64 = run.times[0].departure + LineRun.latestDispatch < now ? 1 : 0
                XCTAssertGreaterThanOrEqual(line.runDays[index] ?? -1, day, "\(line.name): the run leaving at \(run.times[0].departure / 60) min")
            }
        }
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
            let journey = world.lineJourney(line.id, pattern: nil)
            say("\(line.name): \(line.stops.count) calls, \(line.runs.count) runs, \(line.trains.count) sets, round trip \(journey?.roundTripMinutes ?? -1) min")
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
