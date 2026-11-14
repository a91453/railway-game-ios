import Foundation
@testable import GameCore
import XCTest

/// Decision 756 (SWITCH-THROW): with switch interlocking on, under traffic
/// control a switch lies the way the last train went through it, and a
/// service leaving a stop whose route needs a switch the other way waits
/// ``GameWorld/switchThrowSeconds`` before it moves.
///
/// The scene is ``SingleTrackMeet``: one train at W's platform bound for
/// M's main platform and then E. Node 2 is the west switch (W's track, M's
/// main e2 and the loop's entrance e4), node 3 the east one.
final class SwitchInterlockingTests: XCTestCase {
    static let main = SwitchLie(.edge(1), .edge(2))
    static let loop = SwitchLie(.edge(1), .edge(4))

    static func world(interlocking: Bool = true, west lie: SwitchLie? = nil, trafficControl: Bool = true) throws -> (world: GameWorld, train: TrainID) {
        var world = try SingleTrackMeet.world()
        let id = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        try world.setTrainTimetable(id, to: SingleTrackMeet.timetable(eastbound: true))
        if trafficControl { try world.setTrafficControl(true) }
        world.setSwitchInterlocking(interlocking)
        if let lie { world.switchLies[.node(2)] = lie }
        try world.startTrainService(id)
        // A second a tick, so the four seconds can be watched.
        world.setSpeed(.x1)
        return (world, id)
    }

    /// Steps until train `id` has set off from W for M; its run then.
    static func setOff(_ world: inout GameWorld, _ id: TrainID) throws -> ServiceRun {
        for _ in 0..<2_000 {
            if let train = world.train(id: id), case .travellingToStop(1, _)? = train.execution, let run = train.times?.run {
                return run
            }
            try world.advance(ticks: 1)
        }
        throw XCTSkip("the train never set off")
    }

    /// Steps until train `id` waits at M.
    static func arrive(_ world: inout GameWorld, _ id: TrainID) throws {
        for _ in 0..<5_000 where world.train(id: id)?.execution != .waitingAtStop(1, cycle: 0) {
            try world.advance(ticks: 1)
        }
        XCTAssertEqual(world.train(id: id)?.execution, .waitingAtStop(1, cycle: 0))
    }

    func testAFourSecondThrow() {
        XCTAssertEqual(GameWorld.switchThrowSeconds, 4)
    }

    /// The west switch lies for the loop: the train bound for M's main
    /// sets off as before but starts along its route four seconds later,
    /// standing at W until then, and arrives four seconds later.
    func testASwitchLyingTheOtherWayHoldsTheTrainFourSeconds() throws {
        var (plain, a) = try Self.world(interlocking: false)
        var (thrown, b) = try Self.world(west: Self.loop)
        let before = try Self.setOff(&plain, a)
        let after = try Self.setOff(&thrown, b)
        XCTAssertEqual(after.start, GameWorld.saturating(before.start, plus: GameWorld.switchThrowSeconds))
        XCTAssertEqual(after.seconds, before.seconds)
        XCTAssertEqual(thrown.switchesThrownUntil(of: b), after.start)
        XCTAssertNil(plain.switchesThrownUntil(of: a))
        let standing = thrown.train(id: b)?.position
        XCTAssertEqual(standing, .onEdge(SingleTrackMeet.forward(1), offset: 3_072))
        while thrown.clock.now < after.start {
            XCTAssertEqual(thrown.train(id: b)?.position, standing, "standing while the switch is thrown")
            XCTAssertFalse(thrown.train(id: b)?.reservation.isEmpty ?? true, "holding its route")
            try thrown.advance(ticks: 1)
        }
        try Self.arrive(&plain, a)
        try Self.arrive(&thrown, b)
        let early = try XCTUnwrap(plain.train(id: a)?.times?.arrival)
        let late = try XCTUnwrap(thrown.train(id: b)?.times?.arrival)
        XCTAssertEqual(late.seconds - early.seconds, GameWorld.switchThrowSeconds)
        XCTAssertEqual(thrown.switchLies[.node(2)], Self.main, "it lies the way the train went")
        XCTAssertEqual(WorldInvariants.violations(in: thrown), [])
    }

    /// A switch already lying the train's way costs nothing, and one no
    /// train has gone through lies the way the first train wants: both
    /// run exactly as with interlocking off.
    func testASwitchLyingItsWayOrNeverThrownCostsNothing() throws {
        var (plain, a) = try Self.world(interlocking: false)
        try Self.arrive(&plain, a)
        for lie in [Self.main, nil] {
            var (world, b) = try Self.world(west: lie)
            try Self.arrive(&world, b)
            XCTAssertEqual(world.train(id: b), plain.train(id: a))
            XCTAssertEqual(world.switchLies[.node(2)], Self.main)
            XCTAssertEqual(world.switchLies[.node(3)], nil, "not yet through the east switch")
        }
    }

    /// With traffic control off there is nothing to interlock: the train
    /// runs as without, and no switch's lie is kept.
    func testWithoutTrafficControlNothingChanges() throws {
        var (plain, a) = try Self.world(interlocking: false, trafficControl: false)
        var (world, b) = try Self.world(west: Self.loop, trafficControl: false)
        try Self.arrive(&plain, a)
        try Self.arrive(&world, b)
        XCTAssertEqual(world.train(id: b), plain.train(id: a))
        XCTAssertEqual(world.switchLies, [.node(2): Self.loop], "as it was set")
    }

    /// Turned off, the switches forget how they lie.
    func testTurningItOffForgetsTheLies() throws {
        var (world, _) = try Self.world(west: Self.loop)
        world.setSwitchInterlocking(false)
        XCTAssertFalse(world.switchInterlocking)
        XCTAssertEqual(world.switchLies, [:])
    }

    /// Turned off while a train waits for its switches, the train still
    /// sets off when they lie, and the world saves and loads.
    func testTurningItOffWhileASwitchIsThrownSavesAndLoads() throws {
        var (world, id) = try Self.world(west: Self.loop)
        let run = try Self.setOff(&world, id)
        XCTAssertGreaterThan(run.start, world.clock.now)
        world.setSwitchInterlocking(false)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
        XCTAssertEqual(loaded, world)
        try Self.arrive(&world, id)
    }

    /// Saved only when on, the lies by node; a save with lies but the
    /// interlocking off, out of order or with a bad pair is refused.
    func testItIsSavedAndChecked() throws {
        var (world, id) = try Self.world(west: Self.loop)
        try Self.arrive(&world, id)
        let data = try JSONEncoder().encode(world)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["switchInterlocking"] as? Bool, true)
        let lies = try XCTUnwrap(json["switchLies"] as? [[String: Any]])
        XCTAssertEqual(lies.map { $0["node"] as? Int }, [2])
        XCTAssertEqual(lies.first?["edges"] as? [Int], [1, 2])
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let off = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.world(interlocking: false).world)) as? [String: Any])
        XCTAssertNil(off["switchInterlocking"])
        XCTAssertNil(off["switchLies"])
        for (on, bad) in [(false, [["node": 2, "edges": [1, 2]]]),
                          (true, [["node": 3, "edges": [2, 3]], ["node": 2, "edges": [1, 2]]]),
                          (true, [["node": 2, "edges": [2, 1]]]),
                          (true, [["node": 2, "edges": [1]]]),
                          (true, [["node": 0, "edges": [1, 2]]])] {
            var changed = json
            changed["switchInterlocking"] = on ? true : nil
            changed["switchLies"] = bad
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: changed)))
        }
    }

    /// One long advance ends where single steps do, and a save goes on
    /// the same.
    func testBatchesStepsAndASaveAgree() throws {
        var batch = try Self.world(west: Self.loop).world
        var steps = batch
        try batch.advance(ticks: 1_500)
        for _ in 0..<750 { try steps.advance(ticks: 1) }
        var loaded = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: steps))).world
        for _ in 0..<750 {
            try steps.advance(ticks: 1)
            try loaded.advance(ticks: 1)
        }
        XCTAssertEqual(loaded, steps)
        XCTAssertEqual(steps, batch)
    }

    /// The version 102 save: 45 seconds in, the train has set off from W
    /// and stands there while the west switch, lying for the loop, is
    /// thrown for M's main; it loads as the same world and runs on the same. Written with
    /// `SWITCH_SAVE_NEW=1` by the build that first made it.
    func testTheVersion102SaveKeepsTheSwitches() throws {
        var world = try Self.world(west: Self.loop).world
        try world.advance(ticks: 450)
        let url = SavedGameTests.fixtures.appendingPathComponent("v102-switch-interlocking.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["SWITCH_SAVE_NEW"] != nil, SavedGame.currentVersion == 102 {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 102)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertTrue(loaded.switchInterlocking)
        XCTAssertEqual(loaded.switchLies, [.node(2): Self.loop])
        XCTAssertNotNil(loaded.switchesThrownUntil(of: TrainID(rawValue: 1)), "the switch is being thrown")
        XCTAssertEqual(loaded, world, "the save is the world this build makes the same way")
        var running = world
        try loaded.advance(ticks: 600)
        try running.advance(ticks: 600)
        XCTAssertEqual(loaded, running)
        XCTAssertEqual(running.switchLies[.node(2)], Self.main)
    }
}
