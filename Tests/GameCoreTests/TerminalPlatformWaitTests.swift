import Foundation
@testable import GameCore
import XCTest

/// Decision 805's second case, and decision 808's mending of it: with
/// traffic control on, ten trains of the Taoyuan Airport MRT used to wait
/// for each other around the two airport terminals.
///
/// `SaveFixtures/v107-terminal-platform-wait.json` is the line bought as
/// it was before decision 605 under the simple rules, traffic control on,
/// at 16:40 of its first day. At 16:43 train 31 leaves Terminal 1 for the
/// platform of Terminal 2 an empty run (train 22) is already heading for,
/// both behind train 14, which calls there. Before decision 808 the empty
/// run, having the lower ID, took the platform first when train 14 left
/// it; its timetable ended there at 16:47, and its only way on was the
/// track train 31 stood on. Eight more trains queued behind the two until
/// 16:58. Now the empty run, whose timetable ends on train 31's route,
/// waits short of where the two routes meet, train 31 calls and goes on,
/// and the empty run takes the platform after it.
final class TerminalPlatformWaitTests: XCTestCase {
    private static func world() throws -> GameWorld {
        let data = try Data(contentsOf: SavedGameTests.fixtures.appendingPathComponent("v107-terminal-platform-wait.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        world.setSpeed(.normal)
        return world
    }

    private static func minute(_ world: GameWorld) -> Int64 {
        world.clock.now.seconds % GameTime.secondsPerDay / 60
    }

    /// The service calls at Terminal 2 and goes on before the empty run
    /// reaches the platform, and neither waits for the other.
    func testTheEmptyRunLetsTheServiceCallFirst() throws {
        var world = try Self.world()
        XCTAssertTrue(world.isTrafficControlEnabled)
        let (emptyRun, service) = (TrainID(rawValue: 22), TrainID(rawValue: 31))
        try world.advance(ticks: 3)
        // 16:43: both on their way to Terminal 2, the empty run to end there.
        let ending = try XCTUnwrap(world.train(id: emptyRun))
        XCTAssertTrue(ending.isDeadheading)
        XCTAssertEqual(ending.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(ending.timetable.count, 2)
        XCTAssertEqual(world.train(id: service)?.execution, .travellingToStop(1, cycle: 0))
        XCTAssertEqual(ending.timetable[1].station, world.train(id: service)?.timetable[1].station)
        try world.advance(ticks: 4)
        // 16:47: the service has called and left; the empty run is not in yet.
        XCTAssertEqual(Self.minute(world), 16 * 60 + 47)
        XCTAssertEqual(world.train(id: service)?.execution, .travellingToStop(2, cycle: 0))
        XCTAssertEqual(world.train(id: emptyRun)?.execution, .travellingToStop(1, cycle: 0))
        try world.advance(ticks: 3)
        // 16:50, when the two used to hold each other.
        XCTAssertEqual(world.routeWaits().filter(\.isDeadlocked).map(\.train), [])
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.train(id: emptyRun)?.execution, nil)
        XCTAssertEqual(world.stationsStoppedAt(by: emptyRun), [ending.timetable[1].station])
    }

    /// Nothing waits for another train round the terminals in the hour
    /// that used to hold ten of them for eleven minutes.
    func testNoTrainWaitsForAnotherForAnHour() throws {
        var world = try Self.world()
        for _ in 0..<60 {
            try world.advance(ticks: 1)
            XCTAssertEqual(world.deadlockedTrains(), [], "at \(Self.minute(world) / 60):\(Self.minute(world) % 60)")
        }
    }
}
