@testable import GameCore
import XCTest

/// Decision 570: a line's train a run would send out is not in a deadlock
/// while the run may only be sent out early (up to
/// ``LineRun/earliestDispatch`` before it leaves), as a service standing
/// before its departure time is not; once the run is due to leave, a
/// train that cannot go is reported as before.
final class RunSendOutDeadlockTests: XCTestCase {
    /// The single track W–M–E (`SingleTrackMeet`), each end one platform,
    /// with block sections and traffic control: a line W–E whose run
    /// W→E leaves at 06:05 and whose run E→W leaves at 06:10. Its train
    /// at W stands ready for the first, its train at E for the second:
    /// each run's way ends at the platform the other train stands at.
    func facingRuns() throws -> (world: GameWorld, west: TrainID, east: TrainID) {
        var world = try SingleTrackMeet.world()
        world.setBlockSections(true)
        let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.east]).id
        try world.setLineRuns(line, to: [
            LineRun(from: 0, to: 1, times: [LineRunTime(arrival: 21_900, departure: 21_900), LineRunTime(arrival: 22_500, departure: 22_500)]),
            LineRun(from: 1, to: 0, times: [LineRunTime(arrival: 22_200, departure: 22_200), LineRunTime(arrival: 22_800, departure: 22_800)]),
        ])
        let west = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        let east = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.backward(3), offset: 3_072)
        for id in [west, east] { try world.assignTrain(id, to: line) }
        try world.setTrafficControl(true)
        return (world, west, east)
    }

    func testATrainThatMayBeSentOutEarlyIsNotDeadlockedButOneDueToLeaveIs() throws {
        var (world, west, east) = try facingRuns()
        while world.clock.now < GameTime(minutes: 6 * 60) { try world.advance(ticks: 1) }
        // 06:00–06:09: W's run may be sent out from 06:00 and is due to
        // leave at 06:05, E's from 06:05 and at 06:10. Before decision 570
        // W's train was reported stuck from 06:00, kept by E's train,
        // a spare between runs (decision 212).
        while world.clock.now < GameTime(minutes: 6 * 60 + 10) {
            XCTAssertEqual(world.deadlockedTrains(), [], "\(world.clock.now.minuteOfDay)")
            try world.advance(ticks: 1)
        }
        // From 06:10 both runs are due to leave and each waits for the
        // platform the other stands at: a deadlock, reported, and with no
        // passing place or spare it stays.
        for _ in 0..<5 {
            XCTAssertEqual(world.deadlockedTrains(), [west, east].sorted(), "\(world.clock.now.minuteOfDay)")
            try world.advance(ticks: 1)
        }
        XCTAssertNil(world.train(id: west)?.execution)
        XCTAssertNil(world.train(id: east)?.execution)
        XCTAssertEqual(WorldInvariants.violations(in: world), [])
    }
}
