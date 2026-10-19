@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 255's turn back short on the train card (TestFlight 74.1): two
/// lines sharing a single track with no passing place, C ── A ── B, a
/// shuttle between A and B and a second line from C through A to B. The
/// second line's train turns back at A; its card's trip runs from A, where
/// it turned, not from B, where it never went, and says it turned back.
final class ShortTurnCardTests: XCTestCase {
    static let c = StationID(rawValue: 1)
    static let a = StationID(rawValue: 2)
    static let b = StationID(rawValue: 3)

    /// As `SharedSingleTrackTests` builds it: the shuttle at A heading for
    /// B, the other train at C heading for A.
    func world() throws -> (world: GameWorld, shuttle: TrainID, through: TrainID) {
        var world = try GameWorld(
            bounds: WorldBounds(width: 36_864, height: 8_192),
            economy: GameEconomy(balance: 1_000_000, costs: ConstructionCosts(track: 10, station: 1_000, train: 500)),
            clock: GameClock(speed: .normal)
        )
        for x in [Int64(1_024), 17_408, 33_792] { _ = try world.buildTrackNode(at: WorldCoordinate(x: x, y: 4_096)) }
        // e1: A → B, e2: A → C.
        _ = try world.buildTrackEdge(from: .node(2), to: .node(3))
        _ = try world.buildTrackEdge(from: .node(2), to: .node(1))
        for (name, x) in [("C", Int64(3_072)), ("A", 17_408), ("B", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 6_144))
        }
        let length = try XCTUnwrap(world.trackEdge(.edge(1))?.length)
        try world.addTrackPlatform(Self.a, on: .edge(1), from: 1_024, to: 3_072)
        try world.addTrackPlatform(Self.b, on: .edge(1), from: length - 3_072, to: length - 1_024)
        try world.addTrackPlatform(Self.c, on: .edge(2), from: length - 3_072, to: length - 1_024)
        try world.setTrafficControl(true)
        let shuttle = try line(&world, stops: [Self.a, Self.b], at: TrackTraversal(edge: .edge(1), direction: .forward))
        let through = try line(&world, stops: [Self.c, Self.a, Self.b], at: TrackTraversal(edge: .edge(2), direction: .backward))
        return (world, shuttle, through)
    }

    private func line(_ world: inout GameWorld, stops: [StationID], at traversal: TrackTraversal) throws -> TrainID {
        let line = try world.createLine(named: "L\(world.lines.count + 1)", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T").id
        try world.setTrainCars(train, to: 2)
        try world.placeTrain(train, at: .onEdge(traversal, offset: 3_072))
        try world.setTrainContinuation(train, along: [], stoppingAt: 3_072)
        try world.setTrainMovementRate(train, to: 1_024)
        try world.assignTrain(train, to: line)
        return train
    }

    func testTheCardOfATrainTurnedBackShortRunsFromWhereItTurned() throws {
        var (world, _, through) = try world()
        try world.advance(ticks: 4)
        XCTAssertNil(world.train(id: through)?.shortTurnCall, "not turned yet")
        XCTAssertNil(world.trainCard(of: through, in: .english)?.turnedBackAt)
        // The turn comes in the step from minute 4 to 5 (decision 288's test).
        try world.advance(ticks: 1)
        let train = try XCTUnwrap(world.train(id: through))
        XCTAssertEqual(train.timetable.map(\.station), [Self.c, Self.a, Self.b, Self.a, Self.c])
        XCTAssertEqual(train.execution, .waitingAtStop(3))
        XCTAssertEqual(train.shortTurnCall, 3)
        XCTAssertEqual(train.currentTrip, 3...4, "from A, where it turned, not from B")

        let card = try XCTUnwrap(world.trainCard(of: through, in: .english))
        XCTAssertEqual(card.origin, "A")
        XCTAssertEqual(card.terminus, "C")
        XCTAssertEqual(card.departure, train.timetable[3].departure, "it leaves A after its dwell")
        XCTAssertFalse(card.hasDeparted, "standing at A, it has not left yet")
        XCTAssertEqual(card.turnedBackAt, "A")
        XCTAssertEqual(card.turnedBackText(in: .english), "Turned back early at A")
        XCTAssertEqual(world.trainCard(of: through, in: .traditionalChinese)?.turnedBackText(in: .traditionalChinese), "在A提早折返")
        XCTAssertEqual(card.nextStop, "C")
        let info = try XCTUnwrap(world.followBarInfo(of: through, in: .english))
        XCTAssertEqual(info.origin, "A")
        XCTAssertEqual(info.status, .notDeparted)

        // Gone from A, the same trip, now under way.
        try world.advance(ticks: 1)
        let gone = try XCTUnwrap(world.trainCard(of: through, in: .english))
        XCTAssertNotEqual(world.train(id: through)?.execution, .waitingAtStop(3))
        XCTAssertEqual(gone.origin, "A")
        XCTAssertEqual(gone.turnedBackAt, "A")
        XCTAssertTrue(gone.hasDeparted)
    }

    /// A train that runs its trips whole never reads as turned back: the
    /// shuttle here all day, and every train of the demo.
    func testATripRunWholeIsNotATurnBack() throws {
        var (world, shuttle, through) = try world()
        var turns = 0
        for _ in 0..<(24 * 60) {
            try world.advance(ticks: 1)
            XCTAssertNil(world.train(id: shuttle)?.shortTurnCall)
            if world.trainCard(of: through, in: .english)?.turnedBackAt != nil { turns += 1 }
        }
        XCTAssertGreaterThan(turns, 0, "the other train still turns back short")
        var demo = DemoWorld.make(in: .english)
        for _ in 0..<240 {
            try demo.advance(ticks: 1)
            for train in demo.trains {
                XCTAssertNil(train.shortTurnCall, train.name)
            }
        }
    }
}
