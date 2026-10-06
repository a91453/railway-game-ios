import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The real-world demo (2026-10-05, the author's request): Taiwan's Pingxi,
/// Yilan and Shenao Lines built as the game's own track on their real
/// alignments, with ordinary commands, and running at once.
final class RealWorldDemoTests: XCTestCase {
    private static func bundledRailways() throws -> RealRailways {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        func file(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealRailways/\(name)"))
        }
        return try RealRailways(lines: file("track_lines.geojson"), stations: file("track_stations.geojson"), names: file("station_names.json"))
    }

    /// Built once for every test here: building it takes seconds in a debug
    /// build.
    private static let built: Result<(RealRailways, GameWorld), Error> = Result {
        let railways = try bundledRailways()
        return (railways, RealWorldDemo.make(in: .traditionalChinese, railways: railways))
    }

    func testExpressPatternsCanRouteBetweenEveryPairOfRealDemoStops() throws {
        let (_, original) = try Self.built.get()
        for line in original.lines {
            for first in 0..<(line.stops.count - 1) {
                for last in (first + 1)..<line.stops.count where last > first + 1 {
                    var world = original
                    let pattern = try world.addLinePattern(line.id, calling: [first, last])
                    XCTAssertNotNil(world.lineJourney(line.id, pattern: pattern), "\(line.name): \(first) to \(last)")
                }
            }
        }
    }

    /// The passenger route graph drives each service once; what it finds
    /// must be what `lineHeadway` and `lineJourney` find service by service.
    func testPassengerRouteGraphMatchesTheServiceQueries() throws {
        var (_, world) = try Self.built.get()
        let line = try XCTUnwrap(world.lines.first { $0.stops.count >= 3 })
        let express = try world.addLinePattern(line.id, calling: [0, line.stops.count - 1])
        try world.setLineTrainsInService(line.id, to: .init(peak: 1, offPeak: 1, low: 1), pattern: express)
        let graph = PassengerRouteGraph(world: world)
        var expected = 0
        for line in world.lines {
            guard let level = world.serviceLevel(of: line.id, at: world.clock.now) else { continue }
            for service in 0..<line.serviceCount {
                let pattern = service == 0 ? nil : service - 1
                guard let headway = world.lineHeadway(line.id, at: level, pattern: pattern),
                      let journey = world.lineJourney(line.id, pattern: pattern) else { continue }
                let paths = graph.paths.filter { $0.line == line.id && (line.isRing || $0.pattern == pattern) }
                XCTAssertFalse(paths.isEmpty, "\(line.name) service \(service)")
                for path in paths {
                    XCTAssertEqual(path.headway, headway, "\(line.name) service \(service)")
                    XCTAssertEqual(path.runSeconds.reduce(0, +) > 0, true)
                    if !line.isRing, path.direction == .outbound {
                        XCTAssertEqual(path.runSeconds, Array(journey.legs.prefix(path.stations.count - 1).map(\.seconds)))
                    }
                }
                expected += line.isRing ? 2 : 2
            }
        }
        XCTAssertEqual(graph.paths.count, expected)
    }

    func testNewRuifangShifenExpressDepartsWithoutSettingALegacyRate() async throws {
        var (_, world) = try Self.built.get()
        for line in world.lines { try world.removeLine(line.id) }
        for train in world.trains { try world.unplaceTrain(train.id) }
        let names = ["瑞芳", "猴硐", "三貂嶺", "大華", "十分"]
        let stops = try names.map { name in try XCTUnwrap(world.stations.first { $0.name == name }?.id) }
        let line = try world.createLine(named: "瑞芳十分快車", stops: stops).id
        let pattern = try world.addLinePattern(line, calling: [0, 4])
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: .init(peak: 1, offPeak: 1, low: 1), pattern: pattern)
        XCTAssertNotNil(world.lineJourney(line, pattern: pattern), "The physical route exists")
        await MainActor.run { [world] in
            let session = GameSession(world: world)
            session.selectLine(line)
            session.selectStation(stops[0])
            session.purchaseTrain()
            session.setSelectedTrainCars(3)
            session.placeSelectedTrain()
            session.assignSelectedTrainToSelectedLine(pattern: pattern)
            session.advance(realElapsed: .milliseconds(200))
            XCTAssertNotNil(session.selectedTrain?.execution, "A newly placed express must not be held by an invisible legacy rate of zero")
            XCTAssertEqual(session.selectedTrain?.timetable.map(\.station), [stops[0], stops[4], stops[0]])
            XCTAssertNotEqual(session.selectedTrain?.pathText(in: .traditionalChinese), "前方沒有路徑")
        }
    }

    /// V4d on the bundled physical Pingxi track: Shifen -> Jingtong ->
    /// Pingxi reverses at the intermediate terminal, then again on return.
    /// The requested call order is a player scenario, not a real timetable.
    func testAPlayerSwitchbackServiceReversesAtJingtongAndCompletesItsRoundTrip() throws {
        var (_, world) = try Self.built.get()
        for line in world.lines { try world.removeLine(line.id) }
        for train in world.trains { try world.unplaceTrain(train.id) }
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        let shifen = try XCTUnwrap(ids["十分"]), jingtong = try XCTUnwrap(ids["菁桐"]), pingxi = try XCTUnwrap(ids["平溪"])
        let lineID = try world.createLine(named: "Player switchback", stops: [shifen, jingtong, pingxi]).id
        try world.setLineServiceWindow(lineID, to: .allDay)
        try world.setLineTrainsInService(lineID, to: .init(peak: 1, offPeak: 1, low: 1))
        let journey = try XCTUnwrap(world.lineJourney(lineID))
        XCTAssertEqual(journey.intermediateTurnbacks, [1, 3])
        let train = try XCTUnwrap(world.trains.first).id
        try world.placeTrain(train, at: journey.start)
        guard case .onEdge(_, let offset) = journey.start else { return XCTFail("missing start") }
        try world.setTrainContinuation(train, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: lineID)
        world.setSpeed(.x1)
        let started = world.clock.now.seconds
        var visits: Set<Int> = []
        var departedReversed = false
        for _ in 0..<Int((journey.roundTripSeconds + 600) / 10) {
            try world.advance(ticks: 100)
            let unit = try XCTUnwrap(world.train(id: train))
            if case .waitingAtStop(let stop, _)? = unit.execution, stop == 1 || stop == 3 {
                visits.insert(stop)
                XCTAssertEqual(world.stationsBesideWholeTrain(train), [jingtong])
                XCTAssertTrue(unit.timetable[stop].reverses)
                let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
                XCTAssertEqual(world, loaded)
            }
            if case .travellingToStop(let stop, _)? = unit.execution, stop == 2 {
                departedReversed = true
                XCTAssertFalse(world.reservedResources(of: train).isEmpty)
            }
            if unit.execution == nil, world.clock.now.seconds > started + 60 { break }
        }
        XCTAssertEqual(visits, [1, 3])
        XCTAssertTrue(departedReversed)
        XCTAssertNil(world.train(id: train)?.execution)
        XCTAssertEqual(world.stationsStoppedAt(by: train), [shifen])
    }

    /// Passengers ride through a mid-route turnback (V4d): reversing at
    /// Jingtong to go on to Pingxi ends no direction, so those from Shifen
    /// for Pingxi board, stay aboard through the reversal (saved and loaded
    /// there) and arrive, as the line's stop order and the planners assume.
    func testPassengersRideThroughAMidRouteTurnback() throws {
        var (_, world) = try Self.built.get()
        for line in world.lines { try world.removeLine(line.id) }
        for train in world.trains { try world.unplaceTrain(train.id) }
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        let shifen = try XCTUnwrap(ids["十分"]), jingtong = try XCTUnwrap(ids["菁桐"]), pingxi = try XCTUnwrap(ids["平溪"])
        let lineID = try world.createLine(named: "Player switchback", stops: [shifen, jingtong, pingxi]).id
        try world.setLineServiceWindow(lineID, to: .allDay)
        try world.setLineTrainsInService(lineID, to: .init(peak: 1, offPeak: 1, low: 1))
        let journey = try XCTUnwrap(world.lineJourney(lineID))
        XCTAssertEqual(journey.intermediateTurnbacks, [1, 3])
        let train = try XCTUnwrap(world.trains.first).id
        try world.setTrainCars(train, to: 3)
        try world.placeTrain(train, at: journey.start)
        guard case .onEdge(_, let offset) = journey.start else { return XCTFail("missing start") }
        try world.setTrainContinuation(train, along: [], stoppingAt: offset)
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: lineID)
        world.setSpeed(.x1)
        var throughTurnback: Int64 = 0
        var savedThrough = false
        for _ in 0..<1_080 {
            try world.advance(ticks: 100)
            XCTAssertNil(world.riderProblem())
            let unit = try XCTUnwrap(world.train(id: train))
            let forPingxi = world.riders.first { $0.train == train }?.groups
                .filter { $0.origin == shifen && $0.destination == pingxi }
                .reduce(Int64(0)) { $0 + $1.count } ?? 0
            if case .waitingAtStop(1, _)? = unit.execution, forPingxi > 0 {
                throughTurnback = max(throughTurnback, forPingxi)
                if !savedThrough {
                    let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
                    XCTAssertEqual(world, loaded)
                    savedThrough = true
                }
            }
        }
        XCTAssertGreaterThan(throughTurnback, 0, "riders from Shifen for Pingxi stay aboard while the train reverses at Jingtong")
        let waitingForPingxi = world.passengers.first { $0.station == shifen }?.waiting
            .filter { $0.destination == pingxi }.reduce(Int64(0)) { $0 + $1.count } ?? 0
        XCTAssertLessThan(waitingForPingxi, 49, "Shifen's queue for Pingxi is carried (49 waited when nobody could ride through)")
        _ = jingtong
    }

    // MARK: - Where the world lies

    /// A point's place in the world is the same as on the app's map: the
    /// anchor at the middle, a metre at the anchor's latitude 64 units, east
    /// along x and south along y.
    func testTheEarthLiesOverTheWorldAsTheMapShowsIt() throws {
        let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
        let middle = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees, longitude: RealWorldDemo.anchor.longitudeDegrees)
        XCTAssertEqual(middle.x, 524_288, accuracy: 1e-6)
        XCTAssertEqual(middle.y, 524_288, accuracy: 1e-6)
        // A kilometre east at the anchor's latitude: a hundredth of a degree
        // of longitude is 1,007.6 m at 25.08°.
        let east = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees, longitude: RealWorldDemo.anchor.longitudeDegrees + 0.01)
        let metres = 0.01 * .pi / 180 * 6_378_137 * cos(25.0805 * .pi / 180)
        XCTAssertEqual((east.x - 524_288) / 64, metres, accuracy: 1e-6)
        XCTAssertEqual(east.y, 524_288, accuracy: 1e-6)
        // North is up the map, so a smaller y; and the frame's own metres
        // agree with it.
        let north = frame.worldPosition(latitude: RealWorldDemo.anchor.latitudeDegrees + 0.01, longitude: RealWorldDemo.anchor.longitudeDegrees)
        XCTAssertLessThan(north.y, 524_288)
        XCTAssertEqual(frame.metresFromAnchor(worldX: north.x, worldY: north.y).south, (north.y - 524_288) / 64, accuracy: 1e-9)
    }

    // MARK: - What it builds

    func testTheRealLinesAreBuiltAsTheGamesTrack() throws {
        let (railways, world) = try Self.built.get()
        XCTAssertEqual(world.geoAnchor, RealWorldDemo.anchor)
        XCTAssertEqual(world.stations.map(\.name), ["四腳亭", "瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐", "海科館", "八斗子"])
        // A platform at each, and a second on a passing loop at Ruifang,
        // Houtong, Sandiaoling and Shifen.
        XCTAssertEqual(world.stations.map { world.trackPlatforms(of: $0.id).count }, [1, 2, 2, 2, 1, 2, 1, 1, 1, 1, 1, 1])
        XCTAssertTrue(world.network.edges.allSatisfy { $0.structure == .surface && $0.profile == .uniform }, "all on the ground")

        // Each station stands on its real line, within 60 m of the real
        // station: its platform lies on the track nearest it, and at the
        // ends of the lines, where the site's line ends at the station,
        // stops short of the end.
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        for station in world.stations {
            let real = try XCTUnwrap(railways.stations.first { $0.system.id == "tra_sched" && $0.name(in: .traditionalChinese) == station.name })
            let point = frame.worldPosition(latitude: real.coordinate.latitude, longitude: real.coordinate.longitude)
            let away = ((Double(station.point.x) - point.x) * (Double(station.point.x) - point.x)
                + (Double(station.point.y) - point.y) * (Double(station.point.y) - point.y)).squareRoot() / 64
            XCTAssertLessThan(away, 60, "\(station.name) is \(away) m from the real one")
        }

        XCTAssertEqual(world.lines.map(\.name), ["平溪線", "宜蘭線", "深澳線"])
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        XCTAssertEqual(world.lines[0].stops, ["瑞芳", "猴硐", "三貂嶺", "大華", "十分", "望古", "嶺腳", "平溪", "菁桐"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[1].stops, ["四腳亭", "瑞芳", "猴硐", "三貂嶺"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines[2].stops, ["八斗子", "海科館", "瑞芳"].compactMap { ids[$0] })
        XCTAssertEqual(world.lines.map(\.trainsInService.peak), [2, 1, 1])
        XCTAssertEqual(world.trains.map(\.name), ["平溪線列車 1", "平溪線列車 2", "宜蘭線列車 1", "深澳線列車 1"])
        XCTAssertEqual(world.trains.map(\.cars), [3, 3, 3, 3])
        for train in world.trains {
            XCTAssertFalse(world.stationsStoppedAt(by: train.id).isEmpty, "\(train.name) stands at its first platform")
        }

        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(world.accounts.mode, .management)
        XCTAssertEqual(world.economy.balance, GameWorld.startingBalance, "what it built was added to a new game's money, and paid")
        XCTAssertEqual(RealWorldDemo.lineNames(in: .english), ["Pingxi Line", "Yilan Line", "Shenao Line"])
        XCTAssertEqual(RealWorldDemo.trainName(line: "Pingxi Line", number: 2, in: .english), "Pingxi Line Train 2")
    }

    /// Every node joins the edges on either side (their directions agree),
    /// so trains run the whole way: from Sijiaoting to Jingtong, and from
    /// Badouzi into Ruifang's platforms.
    func testTheTrackRunsThrough() throws {
        let (_, world) = try Self.built.get()
        // Every edge at a node goes on from it, but at the three terminals.
        for node in world.network.nodes where node.ends.count > 1 {
            XCTAssertTrue(node.ends.allSatisfy { !$0.exits.isEmpty }, "every edge at node \(node.id) goes on")
        }
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 1 }.count, 3, "Sijiaoting, Jingtong and Badouzi")
        // The junction west of Ruifang: the Yilan Line west, the main track
        // and the loop east, and the Shenao Line.
        XCTAssertEqual(world.network.nodes.filter { $0.ends.count == 4 }.count, 1)
    }

    // MARK: - Running

    func testPingxiCapacityComesFromItsBuiltSingleTrackAndPassingLoops() throws {
        var (_, world) = try Self.built.get()
        let line = world.lines[0]
        let journey = try XCTUnwrap(world.lineJourney(line.id))
        let layout = world.capacityLayout(of: line)
        let profile = world.capacityProfile(of: line, service: 0, journey: journey, layout: layout)
        XCTAssertEqual(journey.legs.map(\.seconds), [208, 140, 178, 152, 115, 126, 87, 115, 117, 87, 126, 115, 152, 178, 140, 208])
        XCTAssertEqual(journey.roundTripSeconds, 3324)
        XCTAssertEqual(layout.blocks, [[0], [1], [2, 3], [4, 5, 6, 7]])
        XCTAssertEqual(layout.passing, [0, 1, 2, 4])
        // Four nominal resources: 2*208+60; 2*140+60;
        // 2*(178+152)+120+60; 888+4*120+30 seconds.
        XCTAssertEqual(profile.work, [476, 340, 840, 840, 1398, 1398, 1398, 1398])
        XCTAssertEqual(profile.minimumHeadway, 24) // ceil(1398/60)
        let controlled = try XCTUnwrap(world.lineMaximumTrains(line.id))
        XCTAssertEqual(controlled, 2) // floor(ceil(3324/60)/24)
        XCTAssertEqual(world.lineTrainsInService(line.id, at: .peak), 2)
        XCTAssertEqual(world.lineHeadway(line.id, at: .peak), 28) // ceil(56/2)
        XCTAssertEqual(world.line(id: line.id)?.trainsInService.peak, 2)
        try world.setTrafficControl(false)
        let legacy = try XCTUnwrap(world.lineMaximumTrains(line.id))
        XCTAssertEqual(legacy, 28)
        XCTAssertLessThan(controlled, legacy)
    }

    func testTheDemoRunsAtOnce() throws {
        var (_, world) = try Self.built.get()
        // A tick is a game minute at a new game's speed: an hour.
        try world.advance(ticks: 60)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertTrue(world.lines.allSatisfy { $0.lastDispatch != nil }, "every line sent its trains out")
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        let shenao = try XCTUnwrap(world.train(id: world.lines[2].trains[0]))
        XCTAssertTrue(shenao.timetable.contains { $0.station == ids["瑞芳"] }, "the Shenao Line's train runs through the junction to Ruifang")
        let carried = world.stations.map { world.passengerLedger(of: $0.id).arrived }.reduce(0, +)
        XCTAssertGreaterThan(carried, 0, "passengers rode")
    }
    /// V4e: over the demo's first hour the map shows every running train's
    /// movement authority along its own track, and every wait names a
    /// train of the world; a deadlocked train waits for another one.
    func testTheMapShowsTheDemosMovementAuthorities() throws {
        var (_, world) = try Self.built.get()
        XCTAssertTrue(world.isTrafficControlEnabled)
        var trainsWithAuthority: Set<TrainID> = []
        for _ in 0..<60 {
            try world.advance(ticks: 1)
            let overlay = world.trafficOverlay()
            for authority in overlay.authorities {
                trainsWithAuthority.insert(authority.train)
                XCTAssertFalse(world.reservedResources(of: authority.train).isEmpty)
                XCTAssertFalse(authority.track.lines.isEmpty)
                XCTAssertTrue(authority.track.lines.allSatisfy { $0.count >= 2 })
            }
            let deadlocked = Set(world.deadlockedTrains())
            for wait in overlay.waits {
                XCTAssertNotNil(world.train(id: wait.holder))
                XCTAssertNotEqual(wait.train, wait.holder)
                XCTAssertEqual(wait.isDeadlocked, deadlocked.contains(wait.train))
                if wait.isDeadlocked { XCTAssertTrue(deadlocked.contains(wait.holder)) }
            }
            XCTAssertEqual(overlay.summary(in: .english) == nil, overlay.isEmpty)
        }
        XCTAssertEqual(trainsWithAuthority, Set(world.trains.map(\.id)), "every demo train took a route")
    }

    /// V4a on the demo's own geometry: a slow train starts at Sijiaoting and calls at Houtong,
    /// an express catches it before Sandiaoling. The waiting body must
    /// clear the express's nominal corridor, on the other physical track.
    func testAnOvertakeWaitsClearOfTheExpressAtHoutong() throws {
        var (_, world) = try Self.built.get()
        for line in world.lines { try world.removeLine(line.id) }
        for train in world.trains { try world.unplaceTrain(train.id) }
        try world.setTrafficControl(false)
        let ids = Dictionary(uniqueKeysWithValues: world.stations.map { ($0.name, $0.id) })
        let origin = try XCTUnwrap(ids["四腳亭"]), middle = try XCTUnwrap(ids["猴硐"])
        let end = try XCTUnwrap(ids["三貂嶺"]), beyond = try XCTUnwrap(ids["大華"])
        let platform = try XCTUnwrap(world.trackPlatforms(of: origin).first)
        let traversal = TrackTraversal(edge: platform.edge, direction: .forward)
        func train(_ offset: Int64) throws -> TrainID {
            let id = try world.purchaseTrain(named: "V4a").id
            try world.setTrainCars(id, to: 1)
            try world.placeTrain(id, at: .onEdge(traversal, offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 1_024)
            return id
        }
        let slow = try train(platform.end), fast = try train(platform.start)
        let now = world.clock.now.seconds
        func call(_ station: StationID, _ arrival: Int64, _ departure: Int64) -> ScheduledStop {
            .init(station: station, arrival: .init(seconds: now + arrival), departure: .init(seconds: now + departure))
        }
        try world.setTrainTimetable(slow, to: [call(origin, 0, 60), call(middle, 450, 450), call(end, 1_500, 1_560)])
        try world.setTrainTimetable(fast, to: [call(origin, 0, 300), call(beyond, 1_100, 1_160)])
        try world.startTrainService(slow); try world.startTrainService(fast)
        try world.setTrafficControl(true)
        XCTAssertTrue(world.scheduledTrafficWaits().contains { $0.train == slow && $0.station == middle && $0.kind == .overtake })
        let express = try XCTUnwrap(world.path(from: .onEdge(traversal, offset: platform.end), toStation: beyond, length: Train.carLength))
        let expressTrack = try XCTUnwrap(world.trackPlatforms(of: middle).first { express.traversals.map(\.edge).contains($0.edge) })
        world.setSpeed(.x10)
        var seen = false
        for _ in 0..<120 {
            try world.advance(ticks: 10)
            if let wait = world.scheduledTrafficWait(of: slow), wait.kind == .overtake, wait.station == middle {
                let waiting = try XCTUnwrap(world.train(id: slow))
                guard case .onEdge(let run, _)? = waiting.position else { return XCTFail("waiting train is unplaced") }
                XCTAssertTrue(world.trackPlatforms(of: middle).contains { $0.edge == run.edge })
                XCTAssertNotEqual(run.edge, expressTrack.edge)
                XCTAssertFalse(world.network.fouls(Set(world.heldResources(of: slow)), Set(world.reservedResources(of: fast))))
                XCTAssertEqual(world.occupancyConflicts(), [])
                seen = true
                break
            }
        }
        XCTAssertTrue(seen, "the planned wait uses Houtong's other physical track")
    }

    /// V4b: select Houtong's original physical platform instead of the
    /// shorter constructed loop, then witness the actual train stop there.
    func testASharedPreferenceUsesHoutongsSelectedPhysicalPlatform() throws {
        var (_, world) = try Self.built.get()
        let line = world.lines[0], train = line.trains[0]
        for other in world.lines where other.id != line.id { try world.removeLine(other.id) }
        for other in world.trains where other.id != train { try world.unplaceTrain(other.id) }
        try world.setLineTrainsInService(line.id, to: .init(peak: 1, offPeak: 1, low: 1))
        let houtong = try XCTUnwrap(world.stations.first { $0.name == "猴硐" })
        let platform = try XCTUnwrap(world.trackPlatforms(of: houtong.id).first)
        let preference = LineRoutePreference(from: 0, to: 1, platform: platform)
        try world.setLineRoutePreferences(line.id, to: [preference])
        let journey = try XCTUnwrap(world.lineJourney(line.id))
        XCTAssertEqual(journey.legs[0].path.traversals.last?.edge, platform.edge)
        world.setSpeed(.x1)
        var seen = false
        for _ in 0..<180 {
            try world.advance(ticks: 100)
            guard let actual = world.train(id: train) else { return XCTFail("missing train") }
            if case .waitingAtStop(1, _)? = actual.execution {
                guard case .onEdge(let track, _)? = actual.position else { return XCTFail("missing position") }
                XCTAssertEqual(track.edge, platform.edge)
                seen = true
                break
            }
        }
        XCTAssertTrue(seen, "the selected physical platform must be reached")
        XCTAssertEqual(world.occupancyConflicts(), [])
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world, world)
    }

    @MainActor
    func testTheLinePanelSessionSetsAndClearsOnlyTheSelectedLeg() throws {
        let (_, world) = try Self.built.get()
        let session = GameSession(world: world, language: .traditionalChinese)
        let line = world.lines[0]
        session.selectLine(line.id)
        let choices = session.world.lineRouteChoices(line.id, from: 0, to: 1)
        let choice = try XCTUnwrap(choices.first)
        session.setSelectedLineRoute(from: 0, to: 1, preference: choice)
        XCTAssertEqual(session.world.line(id: line.id)?.routePreferences, [choice])
        XCTAssertTrue(session.message?.text.contains("股道") == true)
        session.setSelectedLineRoute(from: 0, to: 1, preference: nil)
        XCTAssertEqual(session.world.line(id: line.id)?.routePreferences, [])
    }

}
