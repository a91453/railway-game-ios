import Foundation
@testable import GameCore
import XCTest

/// Closing track by hand (decision 716), on the single track with a
/// passing loop at M (``SingleTrackMeet``): e1 from W to the loop's west
/// turnout, e2 the main track through M, e3 on to E, and e4, e5, e6 the
/// loop, whose platform is on e5.
final class TrackClosureTests: XCTestCase {
    static let main = TrackEdgeID.edge(2)
    static let loop = TrackEdgeID.edge(5)

    /// The world under traffic control with a train at W about to run
    /// W, M, E, and, with `opposing`, one at E about to run E, M, W.
    func world(opposing: Bool = false) throws -> (world: GameWorld, east: TrainID, west: TrainID?) {
        var world = try SingleTrackMeet.world()
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let west = opposing ? try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072) : nil
        try world.setTrafficControl(true)
        try world.setTrainTimetable(east, to: SingleTrackMeet.timetable(eastbound: true))
        try world.startTrainService(east)
        if let west {
            try world.setTrainTimetable(west, to: SingleTrackMeet.timetable(eastbound: false))
            try world.startTrainService(west)
        }
        return (world, east, west)
    }

    /// The edges a train stands on, has reserved or has on its path.
    func edges(of id: TrainID, in world: GameWorld) -> Set<TrackEdgeID> {
        var edges = Set(world.train(id: id)?.movement.edges ?? [])
        for resource in world.heldResources(of: id) {
            if case .span(let span) = resource { edges.insert(span.edge) }
        }
        return edges
    }

    func assertRejected(_ world: GameWorld, _ expected: GameError, file: StaticString = #filePath, line: UInt = #line,
                        _ command: (inout GameWorld) throws(GameError) -> Void) {
        var changed = world
        do {
            try command(&changed)
            XCTFail("the command was not refused", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
        XCTAssertEqual(changed, world, "a refused command changes nothing", file: file, line: line)
    }

    // MARK: - The commands

    func testClosingAndOpeningATrack() throws {
        var (world, _, _) = try world()
        let before = world
        XCTAssertEqual(world.closedTrack, [])
        try world.closeTrack(Self.loop)
        try world.closeTrack(Self.main)
        XCTAssertEqual(world.closedTrack, [Self.main, Self.loop], "in edge order")
        XCTAssertTrue(world.isTrackClosed(Self.main))
        let closed = world
        try world.closeTrack(Self.main)
        XCTAssertEqual(world, closed, "closing a closed track changes nothing")
        try world.openTrack(Self.loop)
        try world.openTrack(Self.main)
        XCTAssertEqual(world, before, "opened again, the world is as it was")
        try world.openTrack(Self.main)
        XCTAssertEqual(world, before, "opening an open track changes nothing")
        assertRejected(world, .unknownTrackEdge(.edge(9))) { world throws(GameError) in try world.closeTrack(.edge(9)) }
        assertRejected(world, .unknownTrackEdge(.edge(9))) { world throws(GameError) in try world.openTrack(.edge(9)) }
    }

    // Decision 716, continued: before, both of these were refused with
    // `trackReserved`; now the track is being closed.
    func testATrackATrainStandsOnIsBeingClosed() throws {
        var (world, _, _) = try world()
        let before = world
        try world.closeTrack(.edge(1))
        XCTAssertEqual(world.closingTrack, [.edge(1)])
        XCTAssertEqual(world.closedTrack, [])
        XCTAssertTrue(world.isTrackClosing(.edge(1)))
        XCTAssertFalse(world.isTrackClosed(.edge(1)))
        let closing = world
        try world.closeTrack(.edge(1))
        XCTAssertEqual(world, closing, "closing it again changes nothing")
        try world.openTrack(.edge(1))
        XCTAssertEqual(world, before, "opening calls it off: the world is as it was")
        // With traffic control off as well: the train is there all the same.
        var plain = try SingleTrackMeet.world()
        _ = try SingleTrackMeet.stand(&plain, edge: SingleTrackMeet.forward(1), offset: 3_072)
        try plain.closeTrack(.edge(1))
        XCTAssertEqual(plain.closingTrack, [.edge(1)])
    }

    func testATrackOnATrainsRouteIsClosedOnceTheTrainHasPassed() throws {
        var (world, east, west) = try world(opposing: true)
        let westbound = try XCTUnwrap(west)
        try world.advance(ticks: 1)
        // On its way to M along the main track, still on e1.
        XCTAssertEqual(world.train(id: east)?.position?.edge, .edge(1))
        XCTAssertTrue(world.reservedResources(of: east).contains { $0.edge == Self.main })
        XCTAssertEqual(world.trainUsing(Self.main), east)
        let path = world.train(id: east)?.movement.edges
        try world.closeTrack(Self.main)
        XCTAssertEqual(world.closingTrack, [Self.main], "not refused: closed once the train has passed")
        XCTAssertEqual(world.train(id: east)?.movement.edges, path, "the train keeps its path")
        // No new route along it, for a search or a command.
        let fromE = TrainPosition.onEdge(SingleTrackMeet.backward(3), offset: 3_072)
        XCTAssertEqual(world.path(from: fromE, toStation: SingleTrackMeet.middle)?.traversals, [SingleTrackMeet.backward(6), SingleTrackMeet.backward(5)])
        XCTAssertEqual(world.route(from: fromE, to: .node(2)), [6, 5, 4].map(SingleTrackMeet.backward))
        let spare = try world.purchaseTrain(named: "S").id
        assertRejected(world, .trackClosed(Self.main)) { world throws(GameError) in
            try world.placeTrain(spare, at: .onEdge(SingleTrackMeet.forward(2), offset: 4_096))
        }
        // Track no train uses that joins it at a turnout is closed with
        // it, not ahead of it.
        var both = world
        try both.closeTrack(.edge(4))
        XCTAssertEqual(both.closedTrack, [])
        XCTAssertEqual(both.closingTrack, [Self.main, .edge(4)])

        // The eastbound train runs through M on the main track; the
        // westbound one never takes it; then it is closed.
        var usedMain = false
        var closedAt: Int?
        for minute in 0..<20 {
            try world.advance(ticks: 1)
            if edges(of: east, in: world).contains(Self.main) { usedMain = true }
            XCTAssertFalse(edges(of: westbound, in: world).contains(Self.main), "minute \(minute)")
            XCTAssertEqual(world.isTrackClosing(Self.main), world.trainUsing(Self.main) != nil, "closed at the step its last train leaves")
            if closedAt == nil, world.isTrackClosed(Self.main) { closedAt = minute }
        }
        XCTAssertTrue(usedMain)
        XCTAssertNotNil(closedAt)
        XCTAssertEqual(world.closedTrack, [Self.main])
        XCTAssertEqual(world.closingTrack, [])
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: westbound), [SingleTrackMeet.west], "by the loop")
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// A train standing on track being closed finds its way out along it;
    /// no train comes in.
    func testATrainOnTrackBeingClosedRunsOutAndNoneComesIn() throws {
        var (world, east, west) = try world(opposing: true)
        let westbound = try XCTUnwrap(west)
        // e1, where the eastbound train stands at W, and the main track
        // with it: together, though no train uses the main track yet.
        try world.closeTrack([.edge(1), Self.main])
        XCTAssertEqual(world.closingTrack, [.edge(1), Self.main], "the unused piece is not closed ahead of the train")
        XCTAssertEqual(world.closedTrack, [])
        try world.advance(ticks: 12)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east], "it ran out, and on to E")
        XCTAssertEqual(world.closedTrack, [.edge(1), Self.main])
        XCTAssertEqual(world.closingTrack, [])
        // The westbound train came as far as M, by the loop, and waits.
        try world.advance(ticks: 30)
        XCTAssertEqual(world.stationsStoppedAt(by: westbound), [SingleTrackMeet.middle])
        XCTAssertEqual(world.train(id: westbound)?.position?.edge, Self.loop)
        XCTAssertNotNil(world.train(id: westbound)?.execution)
        XCTAssertEqual(world.deadlockedTrains(), [])
        // A command moves a train on track being closed, not one off it.
        var (plain, train, _) = try self.world()
        try plain.setTrafficControl(false)
        try plain.stopTrainService(train)
        try plain.closeTrack([.edge(1), Self.main])
        var sent = plain
        try sent.setTrainContinuation(train, along: [SingleTrackMeet.forward(2), SingleTrackMeet.forward(3)], stoppingAt: 7_168)
        XCTAssertEqual(sent.closingTrack, [.edge(1), Self.main])
        let spare = try plain.purchaseTrain(named: "S").id
        assertRejected(plain, .trackClosed(Self.main)) { world throws(GameError) in
            try world.placeTrain(spare, at: .onEdge(SingleTrackMeet.forward(2), offset: 4_096))
        }
    }

    /// Stage U2: a train following others holds only part of its path. It
    /// goes on taking the rest, over track being closed, a part at a time.
    func testAFollowingTrainTakesItsPathOverTrackBeingClosed() throws {
        //   n0 ──e1── P ──────e2────── Q ──e6── z
        //               ╲            ╱
        //                e3── e4 ──e5
        // X stands on e2 and goes on along e6; A, on e1, follows it by
        // the loop to e6, holding only where it stands.
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 16_384), economy: GameEconomy(balance: 100_000_000, costs: testCosts),
                                  clock: GameClock(speed: .normal))
        let nodes = try [(1_024, 8_192), (61_440, 8_192), (98_304, 8_192), (71_680, 8_704), (88_064, 8_704), (129_024, 8_192)]
            .map { try world.buildTrackNode(at: WorldCoordinate(x: $0.0, y: $0.1)) }
        for (from, to) in [(0, 1), (1, 2), (1, 3), (3, 4), (4, 2), (2, 5)] { try world.buildTrackEdge(from: nodes[from], to: nodes[to]) }
        let e1 = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        let e6 = try XCTUnwrap(world.trackEdge(.edge(6))?.length)
        var ids: [TrainID] = []
        for (name, edge, offset) in [("A", 1, e1 - 30_000), ("X", 2, Int64(16_384))] {
            let id = try world.purchaseTrain(named: name).id
            try world.setTrainCars(id, to: 2)
            try world.placeTrain(id, at: .onEdge(SingleTrackMeet.forward(edge), offset: offset))
            try world.setTrainContinuation(id, along: [], stoppingAt: offset)
            try world.setTrainMovementRate(id, to: 16_384)
            ids.append(id)
        }
        let (a, x) = (ids[0], ids[1])
        try world.setTrafficControl(true)
        for (id, edges, end) in [(a, [3, 4, 5, 6], Int64(12_288)), (x, [6], e6 - 2_048)] {
            var train = try XCTUnwrap(world.train(id: id))
            train.movement.edges = edges.map { .edge($0) }
            train.movement.end = end
            train.movement.cursor = 0
            train.reservation = world.authorityEnvelope(of: train, to: 0).sorted()
            world = world.replacing(train)
        }
        XCTAssertTrue(world.isFollowing(try XCTUnwrap(world.train(id: a))))
        XCTAssertFalse(world.reservedResources(of: a).contains { $0.edge == .edge(4) }, "the loop is on its path, not yet taken")
        var open = world
        try world.closeTrack([.edge(3), .edge(4), .edge(5)])
        XCTAssertEqual(world.closingTrack, [.edge(3), .edge(4), .edge(5)])
        var stepped = world
        for _ in 0..<60 {
            try open.advance(ticks: 1)
            try stepped.advance(ticks: 1)
            XCTAssertEqual(stepped.train(id: a), open.train(id: a), "it runs as it would have")
        }
        XCTAssertEqual(stepped.train(id: a)?.position, .onEdge(SingleTrackMeet.forward(6), offset: 12_288))
        XCTAssertEqual(stepped.closedTrack, [.edge(3), .edge(4), .edge(5)])
        XCTAssertEqual(stepped.closingTrack, [])
        try world.advance(ticks: 60)
        XCTAssertEqual(world, stepped, "a batch ends where minutes do")
    }

    func testNoTrainIsPlacedOnOrSentAlongAClosedTrack() throws {
        for control in [false, true] {
            var world = try SingleTrackMeet.world()
            let train = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
            let spare = try world.purchaseTrain(named: "S").id
            try world.setTrafficControl(control)
            try world.closeTrack(Self.main)
            assertRejected(world, .trackClosed(Self.main)) { world throws(GameError) in
                try world.placeTrain(spare, at: .onEdge(SingleTrackMeet.forward(2), offset: 4_096))
            }
            assertRejected(world, .trackClosed(Self.main)) { world throws(GameError) in
                try world.setTrainContinuation(train, along: [SingleTrackMeet.forward(2), SingleTrackMeet.forward(3)], stoppingAt: 7_168)
            }
            // The way round is still there for a command.
            var sent = world
            try sent.setTrainContinuation(train, along: [4, 5, 6, 3].map(SingleTrackMeet.forward), stoppingAt: 7_168)
            XCTAssertEqual(sent.train(id: train)?.movement.edges, [.edge(4), .edge(5), .edge(6), .edge(3)])
            // No route is found along it either.
            let found = try XCTUnwrap(world.path(from: .onEdge(SingleTrackMeet.forward(1), offset: 3_072), toStation: SingleTrackMeet.east))
            XCTAssertEqual(found.traversals, [4, 5, 6, 3].map(SingleTrackMeet.forward))
            XCTAssertEqual(world.route(from: .onEdge(SingleTrackMeet.forward(1), offset: 3_072), to: .node(4)), [4, 5, 6, 3].map(SingleTrackMeet.forward))
            try world.closeTrack(Self.loop)
            XCTAssertNil(world.path(from: .onEdge(SingleTrackMeet.forward(1), offset: 3_072), toStation: SingleTrackMeet.east))
            XCTAssertNil(world.route(from: .onEdge(SingleTrackMeet.forward(1), offset: 3_072), to: .node(4)))
        }
    }

    // MARK: - Trains

    func testATrainTakesTheLoopWhileTheMainTrackIsClosed() throws {
        // As it is: straight through on the main track.
        var (open, train, _) = try world()
        try open.advance(ticks: 1)
        XCTAssertEqual(open.train(id: train)?.movement.edges, [Self.main])

        var (world, east, _) = try world()
        try world.closeTrack(Self.main)
        var calls: [StationID] = []
        for _ in 0..<12 {
            try world.advance(ticks: 1)
            XCTAssertFalse(edges(of: east, in: world).contains(Self.main), "never on, holding or bound along the closed track")
            if let call = world.stationsStoppedAt(by: east).first, calls.last != call { calls.append(call) }
        }
        XCTAssertEqual(calls, [SingleTrackMeet.middle, SingleTrackMeet.east], "M at the loop's platform, then E")
        XCTAssertNil(world.train(id: east)?.execution, "the service ran to its end")
        XCTAssertEqual(world.train(id: east)?.position, .onEdge(SingleTrackMeet.forward(3), offset: 7_168))
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    func testATrainWithNoWayWaitsAtItsStationUntilTheTrackOpens() throws {
        var (world, east, _) = try world()
        try world.closeTrack(Self.main)
        try world.closeTrack(Self.loop)
        let start = world.train(id: east)?.position
        for _ in 0..<60 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.train(id: east)?.position, start, "it stays at W")
            XCTAssertEqual(world.train(id: east)?.execution, .waitingAtStop(0, cycle: 0), "its service goes on waiting")
            XCTAssertEqual(world.reservedResources(of: east), [])
            XCTAssertEqual(world.deadlockedTrains(), [])
        }
        try world.openTrack(Self.main)
        try world.advance(ticks: 8)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertNil(world.train(id: east)?.execution, "an hour late, the service ran to its end")
    }

    func testOpposingTrainsWaitOutAClosureAndThenMeet() throws {
        // With the main track closed M has one track left: the eastbound
        // train takes the loop and the two stand facing each other.
        var (world, east, west) = try world(opposing: true)
        let westbound = try XCTUnwrap(west)
        try world.closeTrack(Self.main)
        try world.advance(ticks: 60)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.middle])
        XCTAssertEqual(world.stationsStoppedAt(by: westbound), [SingleTrackMeet.east])
        for id in [east, westbound] {
            XCTAssertFalse(edges(of: id, in: world).contains(Self.main))
            XCTAssertNotNil(world.train(id: id)?.execution, "neither service was given up")
        }
        // Opened, the westbound train passes on the main track and both
        // run to their ends.
        try world.openTrack(Self.main)
        try world.advance(ticks: 10)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(world.stationsStoppedAt(by: westbound), [SingleTrackMeet.west])
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertNil(world.train(id: westbound)?.execution)
        XCTAssertEqual(world.deadlockedTrains(), [])
    }

    /// A line's train (W, M, E and back) keeps running round a closure,
    /// stands at a station while there is no way at all, and runs again
    /// once the track opens.
    func testALinesTrainRunsRoundAClosureAndWaitsOutOneWithNoWay() throws {
        var world = try SingleTrackMeet.world()
        try world.setTrafficControl(true)
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        try world.assignTrain(train, to: line)

        /// Runs `ticks` minutes; the stations it came to a stop at, and
        /// whether it was ever on or bound along the main track.
        func run(_ ticks: Int) throws -> (calls: [StationID], usedMain: Bool) {
            var calls: [StationID] = []
            var usedMain = false
            var last = world.stationsStoppedAt(by: train).first
            for _ in 0..<ticks {
                try world.advance(ticks: 1)
                if edges(of: train, in: world).contains(Self.main) { usedMain = true }
                let here = world.stationsStoppedAt(by: train).first
                if let here, here != last { calls.append(here) }
                last = here
            }
            return (calls, usedMain)
        }

        let open = try run(60)
        XCTAssertTrue(open.usedMain, "as it is, through M on the main track")
        XCTAssertGreaterThanOrEqual(open.calls.count, 4)

        // Closed as soon as the train is clear of it (decision 716,
        // continued: being closed until then, no longer refused).
        try world.closeTrack(Self.main)
        for _ in 0..<30 where !world.isTrackClosed(Self.main) { try world.advance(ticks: 1) }
        XCTAssertEqual(world.closedTrack, [Self.main])
        let round = try run(60)
        XCTAssertFalse(round.usedMain)
        XCTAssertGreaterThanOrEqual(round.calls.count, 4, "it keeps running, through the loop")
        XCTAssertTrue(round.calls.contains(SingleTrackMeet.middle))

        // The loop closed too: no way at all.
        try world.closeTrack(Self.loop)
        for _ in 0..<30 where !world.isTrackClosed(Self.loop) { try world.advance(ticks: 1) }
        XCTAssertEqual(world.closedTrack, [Self.main, Self.loop])
        _ = try run(10)
        let place = world.train(id: train)?.position
        let none = try run(120)
        XCTAssertEqual(none.calls, [], "it goes nowhere")
        XCTAssertEqual(world.train(id: train)?.position, place)
        XCTAssertEqual(world.stationsStoppedAt(by: train).count, 1, "it stands at a station")
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.assignedLine(of: train), line, "still the line's train")
        XCTAssertNil(world.lineJourney(line), "the line has no way through")
        XCTAssertEqual(world.routeWaits().map(\.train), [], "it waits for no train")

        try world.openTrack(Self.loop)
        let again = try run(60)
        XCTAssertFalse(again.usedMain)
        XCTAssertGreaterThanOrEqual(again.calls.count, 4, "it runs again")
    }

    // MARK: - Editing closed track

    func testRemovingOrSplittingAClosedTrack() throws {
        var (world, _, _) = try world()
        try world.closeTrack(Self.main)
        try world.closeTrack(Self.loop)
        var split = world
        try split.setTrafficControl(false)
        try split.splitTrackEdge(Self.main, at: 4_096)
        XCTAssertEqual(split.closedTrack, [Self.loop, .edge(7), .edge(8)], "both parts stay closed")
        // Track being closed likewise.
        var (closing, _, _) = try self.world()
        try closing.closeTrack([.edge(1), Self.main])
        try closing.setTrafficControl(false)
        var parts = closing
        try parts.splitTrackEdge(Self.main, at: 4_096)
        XCTAssertEqual(parts.closingTrack, [.edge(1), .edge(7), .edge(8)], "both parts are still being closed")
        XCTAssertEqual(parts.closedTrack, [])
        try world.removeTrackPlatform(SingleTrackMeet.middle, on: Self.main, from: 7_168)
        try world.removeTrackEdge(Self.main)
        XCTAssertEqual(world.closedTrack, [Self.loop], "a removed edge is no longer listed")
    }

    // MARK: - Saves

    func testASaveKeepsTheClosedTracksAndWritesNothingWithoutThem() throws {
        var (world, _, _) = try world()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let plain = try encoder.encode(SavedGame(world: world))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("closedEdges"), "a world that closed nothing writes nothing of it")
        try world.closeTrack(Self.loop)
        try world.closeTrack(Self.main)
        try world.advance(ticks: 1)
        let data = try encoder.encode(SavedGame(world: world))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        XCTAssertEqual(network["closedEdges"] as? [Int], [2, 5])
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), data)
        // Opened again it writes what it wrote before.
        var reopened = try self.world().world
        try reopened.closeTrack(Self.main)
        try reopened.openTrack(Self.main)
        XCTAssertEqual(try encoder.encode(SavedGame(world: reopened)), plain)

        // Rejected rather than repaired.
        func load(_ closed: [Int]) -> GameWorld? {
            var object = object
            var world = object["world"] as! [String: Any]
            var network = world["network"] as! [String: Any]
            network["closedEdges"] = closed
            world["network"] = network
            object["world"] = world
            return try? JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)).world
        }
        XCTAssertNotNil(load([2, 5]))
        XCTAssertNil(load([5, 2]), "out of order")
        XCTAssertNil(load([2, 2]), "twice")
        XCTAssertNil(load([9]), "no such edge")
        XCTAssertNil(load([0]))
    }

    /// `v94-closed-track.json`: the single track with its loop at M, its
    /// main track through M closed, a minute after an eastbound and a
    /// westbound service set off. Written once by the version 94 build
    /// (`CLOSE_TRACK_SAVE_NEW=1`).
    func testVersionNinetyFourKeepsTheClosedTrack() throws {
        var (world, east, west) = try world(opposing: true)
        try world.closeTrack(Self.main)
        try world.advance(ticks: 1)

        let url = SavedGameTests.fixtures.appendingPathComponent("v94-closed-track.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CLOSE_TRACK_SAVE_NEW"] != nil, SavedGame.currentVersion == 94 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 94)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.closedTrack, [Self.main])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        // Run on: the eastbound train calls at the loop, and after the
        // track opens both reach their ends.
        try loaded.advance(ticks: 5)
        XCTAssertEqual(loaded.stationsStoppedAt(by: east), [SingleTrackMeet.middle])
        XCTAssertEqual(loaded.train(id: east)?.position?.edge, Self.loop)
        try loaded.openTrack(Self.main)
        try loaded.advance(ticks: 10)
        XCTAssertEqual(loaded.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(loaded.stationsStoppedAt(by: try XCTUnwrap(west)), [SingleTrackMeet.west])
    }

    // MARK: - Batches

    func testBatchesAndSingleStepsAgreeAcrossAClosure() throws {
        // Ticks to advance, then a command: a closure taken, one that waits for its train,
        // the wait, the opening, the recovery and closures after it.
        let script: [(ticks: Int, edge: TrackEdgeID, close: Bool)] = [
            (0, Self.main, true), (1, Self.loop, true), (9, Self.main, false), (3, Self.main, false), (30, Self.main, true), (5, Self.loop, true),
        ]
        for speed in [GameSpeed.normal, .double] {
            var (batched, _, _) = try world(opposing: true)
            batched.setSpeed(speed)
            var stepped = batched
            var closings = 0
            for step in script {
                try batched.advance(ticks: step.ticks)
                for _ in 0..<step.ticks { try stepped.advance(ticks: 1) }
                XCTAssertEqual(batched, stepped, "after \(step.ticks) ticks at \(speed)")
                var results: [GameError?] = []
                for index in 0..<2 {
                    do {
                        if index == 0 {
                            try step.close ? batched.closeTrack(step.edge) : batched.openTrack(step.edge)
                        } else {
                            try step.close ? stepped.closeTrack(step.edge) : stepped.openTrack(step.edge)
                        }
                        results.append(nil)
                    } catch {
                        results.append(error)
                    }
                }
                XCTAssertEqual(results[0], results[1])
                XCTAssertNil(results[0], "nothing is refused for a train (decision 716, continued)")
                if !batched.closingTrack.isEmpty { closings += 1 }
                XCTAssertEqual(batched, stepped)
            }
            if speed == .normal {
                XCTAssertGreaterThanOrEqual(closings, 1, "the loop is being closed while the eastbound train is bound along it")
            }
            XCTAssertTrue(batched.trains.allSatisfy { $0.execution == nil }, "both services ran to their ends")
        }
    }
}

extension TrackClosureTests {
    // MARK: - Track being closed (decision 716, continued)

    func testASaveKeepsTheTrackBeingClosedAndWritesNothingWithoutIt() throws {
        var (world, _, _) = try world()
        try world.closeTrack(Self.loop)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertFalse(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self).contains("closingEdges"), "nothing is being closed")
        try world.advance(ticks: 1)
        try world.closeTrack([.edge(1), Self.main])
        XCTAssertEqual(world.closingTrack, [.edge(1), Self.main])
        let data = try encoder.encode(SavedGame(world: world))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, SavedGame.currentVersion)
        let network = try XCTUnwrap((object["world"] as? [String: Any])?["network"] as? [String: Any])
        XCTAssertEqual(network["closingEdges"] as? [Int], [1, 2])
        XCTAssertEqual(network["closedEdges"] as? [Int], [5])
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), data)
        // The loaded game goes on as the one that was not saved.
        try world.advance(ticks: 30)
        try loaded.advance(ticks: 30)
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(world.closingTrack, [])
        XCTAssertFalse(String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self).contains("closingEdges"))

        // Rejected rather than repaired.
        func load(_ closing: [Int]) -> GameWorld? {
            var object = object
            var world = object["world"] as! [String: Any]
            var network = world["network"] as! [String: Any]
            network["closingEdges"] = closing
            world["network"] = network
            object["world"] = world
            return try? JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: object)).world
        }
        XCTAssertNotNil(load([1, 2]))
        XCTAssertNil(load([2, 1]), "out of order")
        XCTAssertNil(load([1, 1]), "twice")
        XCTAssertNil(load([9]), "no such edge")
        XCTAssertNil(load([1, 5]), "closed already")
    }

    /// `v95-closing-track.json`: the single track with its loop at M, a
    /// minute after an eastbound and a westbound service set off, the
    /// main track through M being closed under the eastbound train bound
    /// along it. Written once by the version 95 build
    /// (`CLOSE_TRACK_SAVE_NEW=1`).
    func testVersionNinetyFiveKeepsTheTrackBeingClosed() throws {
        var (world, east, west) = try world(opposing: true)
        try world.advance(ticks: 1)
        try world.closeTrack(Self.main)

        let url = SavedGameTests.fixtures.appendingPathComponent("v95-closing-track.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["CLOSE_TRACK_SAVE_NEW"] != nil, SavedGame.currentVersion == 95 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 95)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded.closingTrack, [Self.main])
        XCTAssertEqual(loaded.closedTrack, [])
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        // Run on: the eastbound train goes through on the main track,
        // which is then closed; the westbound one goes by the loop.
        try loaded.advance(ticks: 20)
        XCTAssertEqual(loaded.closedTrack, [Self.main])
        XCTAssertEqual(loaded.closingTrack, [])
        XCTAssertEqual(loaded.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        XCTAssertEqual(loaded.stationsStoppedAt(by: try XCTUnwrap(west)), [SingleTrackMeet.west])
    }

    func testBatchesAndSingleStepsAgreeWhileTrackIsBeingClosed() throws {
        // Ticks to advance, then the edges to close together or to open.
        let script: [(ticks: Int, edges: [TrackEdgeID], close: Bool)] = [
            (1, [Self.main], true), (2, [Self.loop], true), (7, [.edge(3)], true), (1, [.edge(3)], false),
            (20, [Self.main, Self.loop], false), (3, [.edge(1), Self.main], true), (40, [.edge(1)], false), (15, [Self.main], false), (30, [], true),
        ]
        for speed in [GameSpeed.normal, .double, .x1, .x10] {
            var (batched, _, _) = try world(opposing: true)
            batched.setSpeed(speed)
            var stepped = batched
            var seen: Set<[TrackEdgeID]> = []
            for step in script {
                try batched.advance(ticks: step.ticks)
                for _ in 0..<step.ticks {
                    try stepped.advance(ticks: 1)
                    seen.insert(stepped.closingTrack)
                }
                XCTAssertEqual(batched, stepped, "after \(step.ticks) ticks at \(speed)")
                if step.close {
                    try batched.closeTrack(step.edges)
                    try stepped.closeTrack(step.edges)
                } else {
                    for edge in step.edges {
                        try batched.openTrack(edge)
                        try stepped.openTrack(edge)
                    }
                }
                seen.insert(stepped.closingTrack)
                XCTAssertEqual(batched, stepped)
            }
            XCTAssertGreaterThan(seen.count, 1, "track was being closed along the way at \(speed)")
            XCTAssertEqual(batched.closingTrack, [])
        }
    }
}

private extension TrainPosition {
    var edge: TrackEdgeID {
        switch self {
        case .onEdge(let traversal, _): traversal.edge
        }
    }
}

private extension TrackResource {
    var edge: TrackEdgeID? {
        if case .span(let span) = self { span.edge } else { nil }
    }
}
