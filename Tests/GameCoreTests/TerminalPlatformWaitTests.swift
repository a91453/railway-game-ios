import Foundation
@testable import GameCore
import XCTest

/// Decision 805's second case, kept so the next decision has it to mend:
/// with traffic control on, ten trains of the Taoyuan Airport MRT waiting
/// for each other around the two airport terminals.
///
/// `SaveFixtures/v107-terminal-platform-wait.json` is the line bought as
/// it was before decision 605 under the simple rules, traffic control on,
/// at 16:40 of its first day. At 16:43 train 31 leaves Terminal 1 for the
/// platform of Terminal 2 an empty run (train 22) is already heading for;
/// at 16:47 that run ends there, and its only way on is the track train
/// 31 stands on. Eight more trains queue behind the two until 16:58, when
/// the train idle at Terminal 2's other platform has left for the depot.
///
/// Nothing here is this decision's to change (it acts with traffic
/// control off): these are the measures as they are. A decision that
/// keeps the two from meeting turns `testTwoTrainsMeetHeadOn…` around and
/// lowers the bounds of the other.
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

    /// The two that wait for each other, and how each is told to the map:
    /// both deadlocked, each held by the other.
    func testTwoTrainsMeetHeadOnBetweenTheTerminals() throws {
        var world = try Self.world()
        XCTAssertTrue(world.isTrafficControlEnabled)
        try world.advance(ticks: 10)
        XCTAssertEqual(Self.minute(world), 16 * 60 + 50)
        let waits = Dictionary(uniqueKeysWithValues: world.routeWaits().filter(\.isDeadlocked).map { ($0.train, $0.holder) })
        XCTAssertEqual(waits[TrainID(rawValue: 22)], TrainID(rawValue: 31))
        XCTAssertEqual(waits[TrainID(rawValue: 31)], TrainID(rawValue: 22))
        XCTAssertEqual(world.deadlockedTrains().map(\.rawValue), [12, 22, 31])
    }

    /// How bad it gets, so it cannot quietly get worse: at most ten trains
    /// at once, over within eleven minutes, and nothing left an hour on.
    func testTheWaitEndsWithinElevenMinutes() throws {
        var world = try Self.world()
        var most = 0
        var longest = 0
        var running = 0
        var first: Int64?
        for _ in 0..<40 {
            try world.advance(ticks: 1)
            let stuck = world.deadlockedTrains()
            if !stuck.isEmpty, first == nil { first = Self.minute(world) }
            most = max(most, stuck.count)
            running = stuck.isEmpty ? 0 : running + 1
            longest = max(longest, running)
        }
        XCTAssertEqual(first, 16 * 60 + 47)
        XCTAssertLessThanOrEqual(most, 10)
        XCTAssertLessThanOrEqual(longest, 11)
        try world.advance(ticks: 20)
        XCTAssertEqual(world.deadlockedTrains(), [])
    }
}
