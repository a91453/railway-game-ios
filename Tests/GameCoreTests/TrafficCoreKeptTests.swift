@testable import GameCore
import XCTest

/// Decision 1039 (TICK-PLAN-KEEP): a traffic plan whose meets and
/// overtakes are those the last plan worked out, because its services
/// read the same of their trains (``GameWorld/TrafficCoreKey``), is the
/// plan worked out afresh. Asked every second on decision 366's line of
/// ``LocalPassTests``, where the stopping trains stand aside for the
/// express and go back and forth all day, so most seconds keep the meets
/// and overtakes and some work them out again.
final class TrafficCoreKeptTests: XCTestCase {
    func testAPlanWithTheMeetsAndOvertakesKeptIsThePlanWorkedOutAfresh() throws {
        for loopBetween in [false, true] {
            var world = try LocalPassTests.running(loopBetween: loopBetween).world
            var parts = GameWorld.TrafficParts(), paths = GameWorld.PathMemo()
            var core: GameWorld.TrafficCore?
            var kept = 0, worked = 0, planned = 0
            for step in 0..<7_200 {
                try world.advance(ticks: 1)
                let before = core?.key
                let plan = world.trafficPlan(parts: &parts, paths: &paths, core: &core)
                if before != nil, before == core?.key { kept += 1 } else { worked += 1 }
                var freshParts = GameWorld.TrafficParts(), freshPaths = GameWorld.PathMemo()
                let fresh = world.trafficPlan(parts: &freshParts, paths: &freshPaths)
                XCTAssertEqual(plan.waits, fresh.waits, "loop between \(loopBetween), step \(step), \(world.clock.now.seconds) s")
                XCTAssertEqual(plan.services.map(\.points), fresh.services.map(\.points), "loop between \(loopBetween), step \(step)")
                planned += plan.waits.filter { $0.kind == .overtake }.count
            }
            XCTAssertGreaterThan(planned, 0, "loop between \(loopBetween)")
            XCTAssertGreaterThan(kept, 0, "loop between \(loopBetween)")
            XCTAssertGreaterThan(worked, 1, "loop between \(loopBetween)")
        }
    }
}
