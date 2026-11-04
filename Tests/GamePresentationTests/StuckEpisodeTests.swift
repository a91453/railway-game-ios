import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 570: HEALTH-110 found two real lines whose trains the map
/// showed as stuck for a minute or two at a time though every run left:
/// the Xinbeitou branch under simple rules with traffic control (the
/// new game's default), at each end a train whose run's own way ends at
/// the platform the train at the other end stands at, while the way its
/// line names was free once the train between them arrived; and the
/// Liujia line under realistic rules, a train kept at Zhuzhong in its
/// run's early send-out window by the train at Liujia, whose own run
/// leaves a minute later. Neither is a deadlock: each clears by itself.
@MainActor
final class StuckEpisodeTests: XCTestCase {
    /// The minutes from `from` to `to` (minutes of day 0) at which any
    /// train of `world` is deadlocked.
    private func stuckMinutes(_ world: GameWorld, from: Int64, to: Int64) throws -> [Int64] {
        var world = world
        world.setSpeed(.normal)
        var stuck: [Int64] = []
        while world.clock.now < GameTime(minutes: to) {
            try world.advance(ticks: 1)
            if world.clock.now >= GameTime(minutes: from), !world.deadlockedTrains().isEmpty {
                stuck.append(world.clock.now.seconds / 60)
            }
        }
        return stuck
    }

    /// Before decision 570: deadlocked at 06:31–06:32, 06:45–06:46 and
    /// every 14 minutes after.
    func testTheXinbeitouBranchAtTheMorningPeakIsNeverDeadlocked() throws {
        let world = try DepotReturnReportTests.bought("trtc:R_XBT", rules: .simple)
        XCTAssertTrue(world.isTrafficControlEnabled)
        XCTAssertEqual(try stuckMinutes(world, from: 6 * 60, to: 7 * 60 + 30), [])
    }

    /// Before decision 570: deadlocked at 16:54.
    func testTheLiujiaLineInTheEveningIsNeverDeadlocked() throws {
        let world = try DepotReturnReportTests.bought("tra:LIUJIA", rules: .realistic)
        XCTAssertEqual(try stuckMinutes(world, from: 16 * 60 + 30, to: 17 * 60 + 10), [])
    }
}
