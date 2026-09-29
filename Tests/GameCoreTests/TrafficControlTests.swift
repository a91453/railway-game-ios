import Foundation
import GameCore
import XCTest

/// Route reservation under traffic control (Phase 4.6 Stage T,
/// ARCHITECTURE decision 28): the track each train holds, turning traffic
/// control on, commands refused for held track, a service that waits for
/// its route, and saves.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class TrafficControlTests: XCTestCase {
    //   row 0:  .  A  .  .  .  .  B  .
    //   row 1:  o - o - o - o - o - o - o - o     dead ends at (0,1), (7,1)
    private func p(_ x: Int, _ y: Int) -> GridPosition {
        GridPosition(x: x, y: y)
    }

    private func makeWorld() throws -> (world: GameWorld, a: StationID, b: StationID) {
        var world = try GameWorld(width: 8, height: 2, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        try world.buildTrack(at: p(0, 1), connections: .east)
        for x in 1...6 {
            try world.buildTrack(at: p(x, 1), connections: [.east, .west])
        }
        try world.buildTrack(at: p(7, 1), connections: .west)
        let a = try world.buildStation(named: "A", at: p(1, 0)).id
        let b = try world.buildStation(named: "B", at: p(6, 0)).id
        return (world, a, b)
    }

    private func buy(_ world: inout GameWorld, at position: TrainPosition) throws -> TrainID {
        let id = try world.purchaseTrain(named: "T\(world.trains.count + 1)").id
        try world.placeTrain(id, at: position)
        return id
    }

    /// A train holds what it stands on, the node ahead and the rest of its
    /// route, whether or not traffic control is on.
    func testATrainHoldsItsPlaceAndItsRouteAhead() throws {
        var (world, _, _) = try makeWorld()
        XCTAssertFalse(world.trafficControl)
        let one = try buy(&world, at: .atNode(p(2, 1), heading: .east))
        try world.setTrainContinuation(one, to: [p(3, 1), p(4, 1)])
        XCTAssertEqual(world.occupiedResources(of: one), [.node(p(2, 1))])
        XCTAssertEqual(world.reservedResources(of: one), [
            .node(p(2, 1)), .node(p(3, 1)), .node(p(4, 1)), .link(p(2, 1), p(3, 1)), .link(p(3, 1), p(4, 1)),
        ])

        // On a link: the link and the node it runs to.
        let two = try buy(&world, at: .onLink(from: p(6, 1), to: p(5, 1), offset: 256))
        XCTAssertEqual(world.reservedResources(of: two), [.node(p(5, 1)), .link(p(5, 1), p(6, 1))])
        XCTAssertEqual(world.reservedResources(of: TrainID(rawValue: 9)), [])
    }

    /// Turning traffic control on needs every two trains' track apart.
    func testTurningTrafficControlOnNeedsTrainsApart() throws {
        var (world, _, _) = try makeWorld()
        let one = try buy(&world, at: .onLink(from: p(2, 1), to: p(3, 1), offset: 512))
        let two = try buy(&world, at: .atNode(p(3, 1), heading: .east))
        _ = try buy(&world, at: .atNode(p(3, 1), heading: .west))
        let before = world

        XCTAssertThrowsGameError(try world.setTrafficControl(true), .trainsShareTrack(one, two))
        XCTAssertEqual(world, before)

        try world.unplaceTrain(two)
        try world.unplaceTrain(TrainID(rawValue: 3))
        try world.setTrafficControl(true)
        XCTAssertTrue(world.trafficControl)
        try world.setTrafficControl(false)
        XCTAssertFalse(world.trafficControl)
    }

    /// Under traffic control, placing, sending and turning round are
    /// refused when another train holds the track they need; the lowest
    /// such train is named. Track on a route ahead cannot be removed.
    func testCommandsAreRefusedForHeldTrack() throws {
        var (world, _, _) = try makeWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world, at: .atNode(p(2, 1), heading: .east))
        try world.setTrainContinuation(one, to: [p(3, 1), p(4, 1)])
        let two = try world.purchaseTrain(named: "T2").id

        XCTAssertThrowsGameError(try world.placeTrain(two, at: .atNode(p(4, 1), heading: .west)), .trackReserved(one))
        // On the link (4,1)-(5,1) running to (4,1): the node ahead is held.
        XCTAssertThrowsGameError(try world.placeTrain(two, at: .onLink(from: p(5, 1), to: p(4, 1), offset: 512)), .trackReserved(one))
        try world.placeTrain(two, at: .atNode(p(5, 1), heading: .west))
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(4, 1)]), .trackReserved(one))
        XCTAssertThrowsGameError(try world.removeTrack(at: p(4, 1)), .trackInUse(p(4, 1)))
        try world.removeTrack(at: p(7, 1))

        // One runs to (4,1) and stops there: it holds only that node.
        try world.setTrainMovementRate(one, to: 1_024)
        try world.advance(ticks: 2)
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(4, 1), heading: .east))
        XCTAssertEqual(world.reservedResources(of: one), [.node(p(4, 1))])
        XCTAssertThrowsGameError(try world.setTrainContinuation(two, to: [p(4, 1)]), .trackReserved(one))

        // Turned round and sent back west, it frees (4,1) once it is off it.
        try world.reverseTrain(one)
        try world.setTrainContinuation(one, to: [p(3, 1), p(2, 1)])
        try world.advance(ticks: 2)
        try world.setTrainContinuation(two, to: [p(4, 1), p(3, 1)])
        XCTAssertEqual(world.reservedResources(of: two), [
            .node(p(3, 1)), .node(p(4, 1)), .node(p(5, 1)), .link(p(3, 1), p(4, 1)), .link(p(4, 1), p(5, 1)),
        ])

        // Without traffic control the same track is free to take.
        try world.setTrafficControl(false)
        try world.setTrainContinuation(one, to: [p(1, 1)])
        try world.setTrainContinuation(two, to: [p(4, 1), p(3, 1), p(2, 1)])
    }

    /// A train on a link that turns round runs to the other end: that node
    /// must be free.
    func testTurningRoundOnALinkNeedsTheNodeBehind() throws {
        var (world, _, _) = try makeWorld()
        let one = try buy(&world, at: .onLink(from: p(3, 1), to: p(4, 1), offset: 512))
        let two = try buy(&world, at: .atNode(p(3, 1), heading: .west))
        try world.setTrafficControl(true)

        XCTAssertThrowsGameError(try world.reverseTrain(one), .trackReserved(two))
        try world.setTrainContinuation(two, to: [p(2, 1)])
        try world.setTrainMovementRate(two, to: 1_024)
        try world.advance(ticks: 1)
        try world.reverseTrain(one)
        XCTAssertEqual(world.train(id: one)?.position, .onLink(from: p(4, 1), to: p(3, 1), offset: 512))
    }

    /// A service whose route to its next stop is held waits at its stop,
    /// and leaves at the first step the route is free.
    func testAServiceWaitsForItsRoute() throws {
        var (world, a, b) = try makeWorld()
        try world.setTrafficControl(true)
        let one = try buy(&world, at: .atNode(p(1, 1), heading: .east))
        try world.setTrainMovementRate(one, to: 1_024)
        try world.setTrainTimetable(one, to: [
            ScheduledStop(station: a, arrival: GameTime(minutes: 0), departure: GameTime(minutes: 1)),
            ScheduledStop(station: b, arrival: GameTime(minutes: 10), departure: GameTime(minutes: 10)),
        ])
        try world.startTrainService(one)
        let blocker = try buy(&world, at: .atNode(p(4, 1), heading: .west))

        // Due at minute 1, its route (2,1) to (6,1) runs through (4,1).
        try world.advance(ticks: 3)
        XCTAssertEqual(world.clock.now.minutes, 3)
        XCTAssertEqual(world.train(id: one)?.execution, .waitingAtStop(0, cycle: 0))
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(1, 1), heading: .east))

        try world.unplaceTrain(blocker)
        try world.advance(ticks: 1)
        XCTAssertEqual(world.train(id: one)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(world.train(id: one)?.position, .atNode(p(2, 1), heading: .east))
        XCTAssertEqual(world.train(id: one)?.movement.continuation, [p(2, 1), p(3, 1), p(4, 1), p(5, 1), p(6, 1)])
    }

    /// Traffic control is saved only when on; an explicit null, and trains
    /// sharing track under it, are refused.
    func testSavesKeepTrafficControl() throws {
        var (world, _, _) = try makeWorld()
        _ = try buy(&world, at: .atNode(p(2, 1), heading: .east))
        let second = try buy(&world, at: .atNode(p(5, 1), heading: .east))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(world)) as? [String: Any])
        XCTAssertNil(json["trafficControl"])

        try world.setTrafficControl(true)
        let data = try encoder.encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["trafficControl"] as? Bool, true)

        var null = json
        null["trafficControl"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: null)))

        // The second train moved onto the first one's node.
        var shared = json
        var trains = try XCTUnwrap(shared["trains"] as? [[String: Any]])
        XCTAssertEqual(trains[1]["id"] as? Int, second.rawValue)
        trains[1]["position"] = trains[0]["position"]
        shared["trains"] = trains
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: shared)))
        shared["trafficControl"] = false
        XCTAssertNoThrow(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: shared)))
    }
}
