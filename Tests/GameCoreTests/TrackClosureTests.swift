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

    func testATrackATrainStandsOnIsNotClosed() throws {
        let (world, east, _) = try world()
        assertRejected(world, .trackReserved(east)) { world throws(GameError) in try world.closeTrack(.edge(1)) }
        // With traffic control off as well: the train is there all the same.
        var plain = try SingleTrackMeet.world()
        let train = try SingleTrackMeet.stand(&plain, edge: SingleTrackMeet.forward(1), offset: 3_072)
        assertRejected(plain, .trackReserved(train)) { world throws(GameError) in try world.closeTrack(.edge(1)) }
    }

    func testATrackOnATrainsRouteIsNotClosed() throws {
        var (world, east, _) = try world()
        try world.advance(ticks: 1)
        // On its way to M along the main track, still on e1.
        XCTAssertEqual(world.train(id: east)?.position?.edge, .edge(1))
        XCTAssertTrue(world.reservedResources(of: east).contains { $0.edge == Self.main })
        assertRejected(world, .trackReserved(east)) { world throws(GameError) in try world.closeTrack(Self.main) }
        // The loop it does not use can be closed under it.
        try world.closeTrack(Self.loop)
        // Once it has run through, the main track can be closed.
        try world.advance(ticks: 10)
        XCTAssertEqual(world.stationsStoppedAt(by: east), [SingleTrackMeet.east])
        try world.closeTrack(Self.main)
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

        // Closed as soon as the train is clear of it.
        var closed = false
        for _ in 0..<30 where !closed {
            do { try world.closeTrack(Self.main); closed = true } catch { try world.advance(ticks: 1) }
        }
        XCTAssertTrue(closed)
        let round = try run(60)
        XCTAssertFalse(round.usedMain)
        XCTAssertGreaterThanOrEqual(round.calls.count, 4, "it keeps running, through the loop")
        XCTAssertTrue(round.calls.contains(SingleTrackMeet.middle))

        // The loop closed too: no way at all.
        closed = false
        for _ in 0..<30 where !closed {
            do { try world.closeTrack(Self.loop); closed = true } catch { try world.advance(ticks: 1) }
        }
        XCTAssertTrue(closed)
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
        // Ticks to advance, then a command: a closure taken, one refused,
        // the wait, the opening, the recovery and closures after it.
        let script: [(ticks: Int, edge: TrackEdgeID, close: Bool)] = [
            (0, Self.main, true), (1, Self.loop, true), (9, Self.main, false), (3, Self.main, false), (30, Self.main, true), (5, Self.loop, true),
        ]
        for speed in [GameSpeed.normal, .double] {
            var (batched, _, _) = try world(opposing: true)
            batched.setSpeed(speed)
            var stepped = batched
            var refusals = 0
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
                if results[0] != nil { refusals += 1 }
                XCTAssertEqual(batched, stepped)
            }
            if speed == .normal {
                XCTAssertEqual(refusals, 1, "the loop is refused once, while the eastbound train is bound along it")
            }
            XCTAssertTrue(batched.trains.allSatisfy { $0.execution == nil }, "both services ran to their ends")
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
