@testable import GameCore
import XCTest

/// Decision 609, continued: under traffic control, a line's train between
/// runs whose due run cannot leave, its route held, and that stands on
/// track another train waiting for its route needs, goes into a depot at
/// once, though its run is due: it cannot take that run now, and while it
/// stands there the other cannot leave either. Decision 556's last way
/// out (``GameWorld/runTrainEmptyToDepot(in:memo:)``) sent it in only
/// once both runs were due to leave and the two made a deadlock (decision
/// 570). On the Taoyuan Airport MRT under the simple rules with traffic
/// control, an express that had ended its run at Airport Terminal 2 and
/// an all-stops train that had ended its run at Terminal 1 each waited
/// for a due run to the platform the other stood on, and the services
/// behind them queued for the two terminals' platforms.
final class HeldRunTrainInTheWayTests: XCTestCase {
    private static let depot = StationID(rawValue: 4)

    /// `RunSendOutDeadlockTests.facingRuns`, with a depot D past E: the
    /// single track W–M–E, W's run leaving at 06:05 for E, E's at 06:10
    /// for W, each run's way ending at the platform the other train stands
    /// at. E's train faces D.
    private func facingRunsWithADepot() throws -> (world: GameWorld, line: LineID, west: TrainID, east: TrainID) {
        var world = try GameWorld(bounds: WorldBounds(width: 36_864, height: 12_288),
                                  economy: GameEconomy(balance: 1_000_000, costs: SingleTrackMeet.costs), clock: GameClock(speed: .normal))
        for point in SingleTrackMeet.points() { _ = try world.buildTrackNode(at: point) }
        let (entrance, exit) = SingleTrackMeet.curves()
        for edge in 1...3 { _ = try world.buildTrackEdge(from: .node(edge), to: .node(edge + 1)) }
        _ = try world.buildTrackEdge(from: .node(2), to: .node(5), curve: entrance)
        _ = try world.buildTrackEdge(from: .node(5), to: .node(6))
        _ = try world.buildTrackEdge(from: .node(6), to: .node(3), curve: exit)
        for (name, x) in [("W", Int64(3_072)), ("M", 17_408), ("E", 31_744)] {
            _ = try world.buildStation(named: name, at: PlanPoint(x: x, y: 8_192))
        }
        for (station, edge, start, end) in SingleTrackMeet.platforms() {
            try world.addTrackPlatform(station, on: .edge(edge), from: start, to: end)
        }
        // D, straight on past E: e7.
        let end = try world.buildTrackNode(at: WorldCoordinate(x: 36_352, y: 4_096))
        _ = try world.buildTrackEdge(from: .node(4), to: end)
        let depot = try world.buildStation(named: "D", at: PlanPoint(x: 35_072, y: 8_192)).id
        XCTAssertEqual(depot, Self.depot)
        try world.addTrackPlatform(depot, on: .edge(7), from: 256, to: 2_304)
        try world.setStationDepot(depot, to: true)
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.east]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 21_900, departure: 21_900), LineRunTime(arrival: 22_500, departure: 22_500)]),
            LineRun(from: 1, to: 0, times: [LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_800, departure: 22_800)]),
        ])
        try world.setLineDepots(line, to: [depot])
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(3), offset: 7_168)
        for id in [west, east] { try world.assignTrain(id, to: line) }
        try world.setTrafficControl(true)
        return (world, line, west, east)
    }

    /// From 06:00, when W's run may be sent out, E's train is in its way
    /// and its own run, due from 06:05, cannot leave: it runs into D, and
    /// W's run leaves on time. Before, the two stood until 06:10, when
    /// both runs were due to leave and the deadlock's last way out sent
    /// E's train in.
    func testATrainBetweenRunsInTheWayOfAHeldRunGoesIntoTheDepot() throws {
        var (world, line, west, east) = try facingRunsWithADepot()
        while world.clock.now < GameTime(minutes: 6 * 60 + 6) { try world.advance(ticks: 1) }
        let train = try XCTUnwrap(world.train(id: east))
        XCTAssertTrue(train.isDeadheading || world.stationsStoppedAt(by: east).contains(Self.depot), "E's train went for the depot")
        XCTAssertEqual(world.line(id: line)?.runDays[0], 0, "W's 06:05 left")
        XCTAssertNotNil(world.train(id: west)?.execution, "W's train is on its run")
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }

    /// The trains move at whole minutes, so a batch ends where minute by
    /// minute does.
    func testABatchEndsWhereMinutesDo() throws {
        var (world, _, _, _) = try facingRunsWithADepot()
        while world.clock.now < GameTime(minutes: 5 * 60 + 50) { try world.advance(ticks: 1) }
        var single = world
        for _ in 0..<40 { try single.advance(ticks: 1) }
        var batched = world
        try batched.advance(ticks: 40)
        XCTAssertEqual(batched, single)
    }
}
