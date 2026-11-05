import Foundation
import XCTest
@testable import GameCore
@testable import GamePresentation

/// CRASH114 (decision 590, continued): copies of one world advanced at
/// once on several threads, as the game loop's tick (`LoopTick.work`) and
/// the night skip (`NightSkip.firstMove`) do off the main actor while the
/// session keeps its own copy. 114.1's Debug app crashed there while the
/// world kept its state in a shared heap box; this Linux build never did
/// (with -O, -Onone and the thread sanitizer), so the macOS website
/// screenshots are what showed it. Kept as the guard that copies stay
/// independent across threads.
@MainActor
final class WorldSharedAcrossTasksTests: XCTestCase {
    func testCopiesOfOneWorldAdvanceOnManyThreadsAtOnce() async throws {
        let session = try MapFrameCostReportTests.highSpeedSession()
        let world = session.world
        try await withThrowingTaskGroup(of: Void.self) { group in
            for task in 0..<4 {
                group.addTask {
                    if task % 2 == 0 {
                        _ = NightSkip.firstMove(after: world)
                    } else {
                        let step = try GameSession.advanced(world, by: 1, listening: false)
                        XCTAssertGreaterThan(step.world.clock.now, world.clock.now)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}
