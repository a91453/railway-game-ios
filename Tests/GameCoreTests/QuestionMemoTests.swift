import Foundation
@testable import GameCore
import XCTest

/// Decision 138 (continued, TRAFFIC-READ): the questions a map and the
/// train panel ask of traffic control (``GameWorld/routeWaits()`` and the
/// single queries) are lent what the advances kept
/// (``GameWorld/RouteMemo/lend(toQuestion:of:)``), and answer as a world
/// that kept nothing does, at every second of a meet and an overtake.
final class QuestionMemoTests: XCTestCase {
    private func assertAnswersAsANewMemo(_ start: GameWorld, file: StaticString = #filePath, line: UInt = #line) throws {
        var world = start
        world.setSpeed(.x10)
        var lent = 0
        for second in 0..<1_000 {
            try world.advance(ticks: 1)
            var emptied = world
            emptied.routeMemo = GameWorld.RouteMemo()
            if !world.questionMemo().trafficParts.points.isEmpty { lent += 1 }
            XCTAssertTrue(emptied.questionMemo().trafficParts.points.isEmpty)
            XCTAssertEqual(world.routeWaits(), emptied.routeWaits(), "at \(second) s", file: file, line: line)
            XCTAssertEqual(world.deadlockedTrains(), emptied.deadlockedTrains(), "at \(second) s", file: file, line: line)
            XCTAssertEqual(world.scheduledTrafficWaits(), emptied.scheduledTrafficWaits(), "at \(second) s", file: file, line: line)
            XCTAssertEqual(world.heldDepartures(), emptied.heldDepartures(), "at \(second) s", file: file, line: line)
            for train in world.trains {
                XCTAssertEqual(world.scheduledTrafficWait(of: train.id), emptied.scheduledTrafficWait(of: train.id), "at \(second) s", file: file, line: line)
                XCTAssertEqual(world.trainHoldingRoute(of: train.id), emptied.trainHoldingRoute(of: train.id), "at \(second) s", file: file, line: line)
                XCTAssertEqual(world.contestedResources(of: train.id), emptied.contestedResources(of: train.id), "at \(second) s", file: file, line: line)
                XCTAssertEqual(world.heldDeparture(of: train.id), emptied.heldDeparture(of: train.id), "at \(second) s", file: file, line: line)
            }
            if world.trains.allSatisfy({ $0.execution == nil }) { break }
        }
        XCTAssertGreaterThan(lent, 100, "the questions were lent the plan's parts", file: file, line: line)
    }

    func testAMeetsQuestionsAnswerAsANewMemo() throws {
        try assertAnswersAsANewMemo(ScheduledTrafficTests.meet())
    }

    func testAnOvertakesQuestionsAnswerAsANewMemo() throws {
        try assertAnswersAsANewMemo(ScheduledTrafficTests.overtake())
    }

    /// Track built after the advances: nothing they kept for the network
    /// as it was is lent.
    func testNothingIsLentOnceTheNetworkChanges() throws {
        var world = try ScheduledTrafficTests.meet()
        world.setSpeed(.x10)
        try world.advance(ticks: 30)
        XCTAssertFalse(world.questionMemo().trafficParts.points.isEmpty)
        _ = try world.buildTrackNode(at: WorldCoordinate(x: 35_840, y: 4_096))
        let memo = world.questionMemo()
        XCTAssertTrue(memo.trafficParts.points.isEmpty)
        XCTAssertTrue(memo.paths.found.isEmpty)
        XCTAssertTrue(memo.curves.isEmpty)
    }
}
