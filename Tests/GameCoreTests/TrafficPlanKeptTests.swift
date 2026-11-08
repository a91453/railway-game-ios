@testable import GameCore
import XCTest

/// Decision 637: what a traffic plan keeps for the next one (each train's
/// tracks, directions and straight berths at its points, by the shape of
/// its run, and each service's opposite directions within a plan) changes
/// no plan. Every plan worked out with what earlier plans kept is the plan
/// worked out with nothing kept, on decision 366's line of
/// ``LocalPassTests``, where the stopping trains stand aside for the
/// express and go back and forth all day.
final class TrafficPlanKeptTests: XCTestCase {
    func testAPlanWithWhatEarlierPlansKeptIsThePlanWorkedOutAfresh() throws {
        for loopBetween in [false, true] {
            var world = try LocalPassTests.running(loopBetween: loopBetween).world
            var parts = GameWorld.TrafficParts(), paths = GameWorld.PathMemo()
            var runs: [TrainID: Set<GameWorld.TrafficParts.Run>] = [:]
            var planned = 0
            for step in 0..<3_600 {
                try world.advance(ticks: 10)
                let kept = world.trafficPlan(parts: &parts, paths: &paths)
                var freshParts = GameWorld.TrafficParts(), freshPaths = GameWorld.PathMemo()
                let fresh = world.trafficPlan(parts: &freshParts, paths: &freshPaths)
                XCTAssertEqual(kept.waits, fresh.waits, "loop between \(loopBetween), step \(step), \(world.clock.now.seconds) s")
                planned += kept.waits.filter { $0.kind == .overtake }.count
                for (id, list) in parts.kept {
                    XCTAssertLessThanOrEqual(list.count, GameWorld.TrafficParts.keptShapes)
                    if let run = list.first?.run { runs[id, default: []].insert(run) }
                }
            }
            // The stopping trains stood aside, and ran more runs than ways
            // kept for them: a way kept was found again for a later run.
            XCTAssertGreaterThan(planned, 0, "loop between \(loopBetween)")
            XCTAssertTrue(runs.contains { id, seen in seen.count > (parts.kept[id]?.count ?? 0) }, "loop between \(loopBetween): \(runs.mapValues(\.count))")
        }
    }
}
