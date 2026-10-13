import GameCore
@testable import GamePresentation
import XCTest

/// Decision 206: the train diagram (運行圖) of one line, read from the
/// world: each trip's planned line, where the trains are, the meets and
/// overtakes, and how late a train runs.
@MainActor
final class TrainDiagramTests: XCTestCase {
    /// A straight single track West to East with a passing loop and its
    /// signal station in the middle (decision 204), a line calling at all
    /// three and a train starting from each end.
    private func singleTrackWithLoop(trafficControl: Bool = true, slowTrains: Bool = false) throws -> (GameWorld, line: LineID, signal: StationID) {
        var world = try makeWorld(width: 32_768, height: 16_384, balance: 10_000_000, speed: .x10)
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 8_192))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 31_744, y: 8_192))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let west = try world.buildStation(named: "West", at: PlanPoint(x: 3_072, y: 8_704)).id
        let east = try world.buildStation(named: "East", at: PlanPoint(x: 29_696, y: 8_704)).id
        try world.addTrackPlatform(west, on: edge, from: 1_024, to: 4_096)
        try world.addTrackPlatform(east, on: edge, from: 26_624, to: 29_696)
        let session = GameSession(world: world)
        session.selectTool(.network)
        session.setNetworkMode(.passingLoop)
        session.tapNetwork(at: PlanPoint(x: 16_384, y: 8_192), reach: 64)
        session.addPassingLoop()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        world = session.world
        world.setSpeed(.x10)
        let signal = try XCTUnwrap(world.stations.first { $0.operationMode == .closed }).id
        let line = try world.createLine(named: "Single", stops: [west, signal, east]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 2, offPeak: 2, low: 2))
        if slowTrains { try world.setLinePerformance(line, to: .tiltingTaroko) }
        // Both trains at West, one behind the other.
        let platform = try XCTUnwrap(world.trackPlatforms(of: west).first)
        for (name, head) in [("A", platform.end), ("B", platform.end - 2 * Train.carLength)] {
            let train = try world.purchaseTrain(named: name).id
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: platform.edge, direction: .forward), offset: head))
            try world.setTrainContinuation(train, along: [], stoppingAt: head)
            try world.setTrainMovementRate(train, to: 1_024)
            if slowTrains {
                // Timed for an express, run by a forest railway's train: late.
                try world.setTrainPerformance(train, to: .forestRailway)
            }
            try world.assignTrain(train, to: line)
        }
        try world.setTrafficControl(trafficControl)
        return (world, line, signal)
    }

    /// Runs `world` for `steps` × 10 seconds, building the diagram as a
    /// screen would and keeping its history.
    private func run(_ world: inout GameWorld, line: LineID, steps: Int) throws -> (TrainDiagram, TrainDiagramHistory) {
        let single = TrainDiagram.singleTrackSections(of: line, in: world)
        var history = TrainDiagramHistory()
        for _ in 0..<steps {
            try world.advance(ticks: 10)
            history.record(try XCTUnwrap(TrainDiagram(world: world, line: line, singleTrack: single, remembered: history.trips)))
        }
        return (try XCTUnwrap(TrainDiagram(world: world, line: line, singleTrack: single, remembered: history.trips)), history)
    }

    func testTheRowsAreTheLinesStopsSpacedByDistanceWithTheSignalStationMarked() throws {
        let (world, line, signal) = try singleTrackWithLoop()
        let diagram = try XCTUnwrap(TrainDiagram(world: world, line: line))
        XCTAssertEqual(diagram.stations.map(\.name), ["West", "Signal 1", "East"])
        XCTAssertEqual(diagram.stations.map(\.isSignalStation), [false, true, false])
        XCTAssertEqual(diagram.stations[1].id, signal)
        XCTAssertEqual(diagram.stations[0].offset, 0)
        XCTAssertEqual(diagram.stations[1].offset, 0.5, accuracy: 0.02, "the signal station stands halfway")
        XCTAssertEqual(diagram.stations[2].offset, 1)
        XCTAssertEqual(diagram.offset(at: 0.5), diagram.stations[1].offset / 2, accuracy: 1e-9)
        XCTAssertEqual(TrainDiagram.singleTrackSections(of: line, in: world), [true, true], "the loop is a passing place, not double track")
        XCTAssertEqual(diagram.from, world.clock.now.seconds - TrainDiagram.reachSeconds)
        XCTAssertEqual(diagram.to, world.clock.now.seconds + TrainDiagram.reachSeconds)
        XCTAssertNil(TrainDiagram(world: world, line: LineID(rawValue: 99)))
    }

    func testEachTripIsItsTimetableAtItsStopsRowsAndTheTrainIsOnIt() throws {
        var (world, line, _) = try singleTrackWithLoop()
        let (diagram, _) = try run(&world, line: line, steps: 120)
        XCTAssertFalse(diagram.trips.isEmpty)
        XCTAssertEqual(Set(diagram.trips.map(\.id)).count, diagram.trips.count, "one entry a trip")
        for trainID in try XCTUnwrap(world.line(id: line)).assignedTrains {
            let train = try XCTUnwrap(world.train(id: trainID))
            guard let first = train.timetable.first else { continue }
            let trip = try XCTUnwrap(diagram.trips.first { $0.id == "t\(trainID.rawValue)|\(first.arrival.seconds)" })
            XCTAssertEqual(trip.name, train.name)
            let points = trip.lines.flatMap { $0 }
            // Arriving and leaving at each call, on its row.
            var expected: [TrainDiagram.Point] = []
            for stop in train.timetable {
                let row = try XCTUnwrap(world.line(id: line)?.stops.firstIndex(of: stop.station))
                expected.append(.init(time: stop.arrival.seconds, place: Double(row)))
                if stop.departure > stop.arrival { expected.append(.init(time: stop.departure.seconds, place: Double(row))) }
            }
            XCTAssertEqual(points, expected)
        }
        for running in diagram.running {
            XCTAssertEqual(running.now.time, world.clock.now.seconds)
            XCTAssertTrue((0...2).contains(running.now.place))
        }
    }

    /// The point of a passing loop (decision 204): the two trains meet at
    /// the signal station, and the diagram says so.
    func testTwoTrainsMeetAtTheSignalStation() throws {
        var (world, line, signal) = try singleTrackWithLoop()
        let (diagram, history) = try run(&world, line: line, steps: 360)
        let meets = diagram.marks.filter { $0.kind == .meet }
        XCTAssertFalse(meets.isEmpty, "the two trains meet")
        for meet in meets {
            XCTAssertEqual(meet.station, signal, "only the signal station has two tracks")
            XCTAssertTrue(meet.isSignalStation)
            XCTAssertEqual(meet.place, 1)
            XCTAssertEqual(Set(meet.names), ["A", "B"])
            XCTAssertTrue((diagram.from...diagram.to).contains(meet.time))
        }
        XCTAssertEqual(meets.first?.kindText(in: .traditionalChinese), "交會")
        XCTAssertEqual(diagram.marks.filter { $0.kind == .overtake }, [], "they never run the same way at once")
        // Trips the world no longer holds are remembered while it is open.
        XCTAssertGreaterThan(diagram.trips.count, 2)
        XCTAssertEqual(history.line, line)
        for train in diagram.running {
            let trail = try XCTUnwrap(history.trails[train.train]?.last)
            XCTAssertEqual(trail.last, train.now, "the trail ends where the train is")
            XCTAssertEqual(trail.map(\.time), trail.map(\.time).sorted())
        }
    }

    func testALateTrainShowsHowLateAndTheRestOfItsTripShifted() throws {
        var (world, line, _) = try singleTrackWithLoop(slowTrains: true)
        var seen = false
        let single = TrainDiagram.singleTrackSections(of: line, in: world)
        for _ in 0..<360 where !seen {
            try world.advance(ticks: 10)
            let diagram = try XCTUnwrap(TrainDiagram(world: world, line: line, singleTrack: single))
            for train in diagram.running {
                XCTAssertEqual(train.lateSeconds, max(0, world.lateness(of: train.train) ?? 0))
                guard train.isLate else {
                    XCTAssertEqual(train.expected, [])
                    continue
                }
                seen = true
                XCTAssertEqual(train.lateText(in: .traditionalChinese), "誤點 \(train.lateSeconds / 60) 分")
                XCTAssertEqual(train.isVeryLate, train.lateSeconds >= 300)
                XCTAssertEqual(train.expected.first, train.now)
                XCTAssertGreaterThan(train.expected.count, 1)
                XCTAssertEqual(train.expected.map(\.time), train.expected.map(\.time).sorted(), "never back in time")
                XCTAssertTrue(diagram.lateTrains.contains(train))
            }
        }
        XCTAssertTrue(seen, "a forest railway's train cannot keep an express's times")
    }

    func testAFixedTimetablesRunNotYetSentOutIsDrawnAtItsTimes() throws {
        var (world, line, _) = try singleTrackWithLoop()
        try world.setLineRuns(line, to: [LineRun(from: 0, to: 2, times: [
            LineRunTime(arrival: 3_600, departure: 3_600),
            LineRunTime(arrival: 3_700, departure: 3_760),
            LineRunTime(arrival: 3_800, departure: 3_800),
        ])])
        let diagram = try XCTUnwrap(TrainDiagram(world: world, line: line))
        let run = try XCTUnwrap(diagram.trips.first { $0.train == nil })
        XCTAssertEqual(run.lines, [[.init(time: 3_600, place: 0), .init(time: 3_700, place: 1), .init(time: 3_760, place: 1), .init(time: 3_800, place: 2)]])
    }

    // MARK: Marks from trips alone

    private let ids = (1...3).map { StationID(rawValue: $0) }

    private func stations(signal: Bool = false) -> [TrainDiagram.Station] {
        ids.enumerated().map { TrainDiagram.Station(id: $1, name: "S\($0)", offset: Double($0) / 2, isSignalStation: signal && $0 == 1) }
    }

    private func trip(_ name: String, train: Int, _ points: [(Int64, Double)]) -> TrainDiagram.Trip {
        TrainDiagram.Trip(id: name, train: TrainID(rawValue: train), name: name, service: 0, isEmptyRun: false,
                          lines: [points.map { TrainDiagram.Point(time: $0.0, place: $0.1) }])
    }

    private func marks(_ trips: [TrainDiagram.Trip], singleTrack: [Bool], signal: Bool = false) -> [TrainDiagram.Mark] {
        TrainDiagram.marks(trips: trips, waits: [], rows: .init(stops: ids, isRing: false), stations: stations(signal: signal),
                           singleTrack: singleTrack, from: 0, to: 10_000)
    }

    func testOppositeTripsAtAStationTogetherMeetOnlyBesideSingleTrackOrAtASignalStation() throws {
        let down = trip("down", train: 1, [(0, 0), (100, 1), (200, 1), (300, 2)])
        let up = trip("up", train: 2, [(50, 2), (150, 1), (160, 1), (250, 0)])
        let single = marks([down, up], singleTrack: [true, true])
        XCTAssertEqual(single.map(\.kind), [.meet])
        XCTAssertEqual(single.first?.place, 1)
        XCTAssertEqual(single.first?.time, 155, "the middle of the time they are there together")
        XCTAssertEqual(single.first?.names, ["down", "up"])
        XCTAssertEqual(marks([down, up], singleTrack: [false, false]), [], "double track: passing is no event")
        XCTAssertEqual(marks([down, up], singleTrack: [false, false], signal: true).map(\.kind), [.meet])
        XCTAssertEqual(marks([down, up], singleTrack: []).map(\.kind), [.meet], "unknown track: marked")
    }

    func testAFastTripPassingASlowOneThatWaitsIsAnOvertake() throws {
        let slow = trip("slow", train: 1, [(0, 0), (100, 1), (400, 1), (500, 2)])
        let fast = trip("fast", train: 2, [(150, 0), (200, 1), (300, 2)])
        let found = marks([slow, fast], singleTrack: [false, false])
        XCTAssertEqual(found.map(\.kind), [.overtake])
        XCTAssertEqual(found.first?.place, 1)
        XCTAssertEqual(found.first?.time, 200, "the fast one runs through")
        XCTAssertEqual(found.first?.kindText(in: .traditionalChinese), "越行")
        // Following without passing is nothing.
        let behind = trip("behind", train: 3, [(450, 0), (550, 1), (650, 2)])
        XCTAssertEqual(marks([slow, behind], singleTrack: [true, true]), [])
        // A train's own next trip turning at a terminus is nothing either.
        let back = trip("again", train: 1, [(500, 2), (600, 1)])
        XCTAssertEqual(marks([slow, back], singleTrack: [true, true]), [])
    }

    func testARingsTripRunsDownToItsExtraLastRowAndStartsAgainAtTheTop() throws {
        let rows = TrainDiagram.Rows(stops: ids, isRing: true)
        let outer = TrainDiagram.lines(through: [(ids[1], 0, 10), (ids[2], 100, 110), (ids[0], 200, 210), (ids[1], 300, 300)], rows: rows)
        XCTAssertEqual(outer, [
            [.init(time: 0, place: 1), .init(time: 10, place: 1), .init(time: 100, place: 2), .init(time: 110, place: 2), .init(time: 200, place: 3)],
            [.init(time: 200, place: 0), .init(time: 210, place: 0), .init(time: 300, place: 1)],
        ])
        let inner = TrainDiagram.lines(through: [(ids[1], 0, 10), (ids[0], 100, 110), (ids[2], 200, 200)], rows: rows)
        XCTAssertEqual(inner, [
            [.init(time: 0, place: 1), .init(time: 10, place: 1), .init(time: 100, place: 0), .init(time: 110, place: 0)],
            [.init(time: 110, place: 3), .init(time: 200, place: 2)],
        ])
    }

    // MARK: History

    func testTheHistoryStartsAgainForAnotherLineOrWhenTheClockGoesBack() throws {
        var (world, line, _) = try singleTrackWithLoop()
        try world.advance(ticks: 60)
        let earlier = world
        let (_, history) = try run(&world, line: line, steps: 60)
        XCTAssertFalse(history.trips.isEmpty)
        let other = try world.createLine(named: "Other", stops: Array(try XCTUnwrap(world.line(id: line)).stops.prefix(2))).id
        var moved = history
        moved.record(try XCTUnwrap(TrainDiagram(world: world, line: other)))
        XCTAssertEqual(moved.line, other)
        XCTAssertEqual(moved.trips, [])
        XCTAssertEqual(moved.trails, [:])
        // A game loaded from before: what came after it is forgotten.
        var back = history
        let loaded = try XCTUnwrap(TrainDiagram(world: earlier, line: line))
        back.record(loaded)
        XCTAssertEqual(back.trips, loaded.trips.filter { $0.train != nil }.sorted { $0.id < $1.id })
        XCTAssertEqual(back.trails.values.flatMap { $0 }, loaded.running.map { [$0.now] }, "one fresh piece a train")
    }

    // MARK: Viewport

    func testTheViewportFollowsNowZoomsAboutTheFingersAndStaysInTheDiagram() throws {
        var (world, line, _) = try singleTrackWithLoop()
        try world.advance(ticks: 5 * 3_600)
        let diagram = try XCTUnwrap(TrainDiagram(world: world, line: line))
        var view = TrainDiagramViewport(now: diagram.now)
        view.update(to: diagram)
        XCTAssertTrue(view.follows)
        XCTAssertEqual(view.span, TrainDiagramViewport.openingSpan)
        XCTAssertEqual(view.x(of: diagram.now), TrainDiagramViewport.followShare, accuracy: 1e-9)

        // Pinching in keeps the time under the fingers where it is.
        view.pan(dx: 0.1, dy: 0, in: diagram)
        XCTAssertFalse(view.follows, "a drag through time stops following")
        let under = view.time(at: 0.6)
        view.zoom(by: 2, verticalScale: 2, anchorX: 0.6, anchorY: 0.5, in: diagram)
        XCTAssertEqual(view.span, TrainDiagramViewport.openingSpan / 2)
        XCTAssertEqual(view.time(at: 0.6), under, accuracy: 1e-6)
        XCTAssertEqual(view.height, 0.5)
        XCTAssertEqual(view.top, 0.25, accuracy: 1e-9)
        XCTAssertEqual(view.y(of: 0.5), 0.5, accuracy: 1e-9)
        // Never closer than a quarter of an hour, or wider than the diagram.
        view.zoom(by: 100, verticalScale: 100, anchorX: 0.5, anchorY: 0.5, in: diagram)
        XCTAssertEqual(view.span, TrainDiagramViewport.shortestSpan)
        XCTAssertEqual(view.height, TrainDiagramViewport.shortestHeight, accuracy: 1e-9)
        view.zoom(by: 0.001, verticalScale: 0.001, anchorX: 0.5, anchorY: 0.5, in: diagram)
        XCTAssertEqual(view.span, Double(diagram.to - diagram.from))
        XCTAssertEqual(view.height, 1)
        XCTAssertEqual(view.top, 0)
        // Dragged far away, it stops at the diagram's ends.
        view.zoom(by: 4, verticalScale: 1, anchorX: 0.5, anchorY: 0.5, in: diagram)
        view.pan(dx: 1_000, dy: 1_000, in: diagram)
        XCTAssertEqual(view.start, Double(diagram.from))
        XCTAssertEqual(view.top, 0)
        view.follow(in: diagram)
        XCTAssertTrue(view.follows)
        XCTAssertEqual(view.x(of: diagram.now), TrainDiagramViewport.followShare, accuracy: 1e-9)
    }

    func testTheTimeLabelsFallOnRoundSteps() throws {
        var view = TrainDiagramViewport(now: 8 * 3_600 + 7 * 60)
        XCTAssertEqual(view.ticks().map { $0 % 1_200 }, Array(repeating: 0, count: view.ticks().count), "two hours: every 20 minutes")
        XCTAssertEqual(view.ticks().count, 6)
        let (world, line, _) = try singleTrackWithLoop()
        let diagram = try XCTUnwrap(TrainDiagram(world: world, line: line, from: 0, to: 24 * 3_600))
        view.zoom(by: 8, verticalScale: 1, anchorX: 0.5, anchorY: 0.5, in: diagram)
        XCTAssertEqual(view.ticks().map { $0 % 300 }, Array(repeating: 0, count: view.ticks().count), "a quarter hour: every 5 minutes")
        for tick in view.ticks() { XCTAssertTrue((view.start...(view.start + view.span)).contains(Double(tick))) }
    }
}
