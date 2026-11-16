import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 805: with traffic control off, the trains that wait for each
/// other in a ring show on the map as deadlocked trains do under traffic
/// control: a mark round each, a bubble that goes to the train, and its
/// card saying which train it is stuck with. The ring is
/// `SaveFixtures/v107-depot-ladder-ring.json`'s, by the rule before
/// decision 801 (``GameWorld/passesHeldTrains``).
final class SpacingRingAlertTests: XCTestCase {
    /// The world in the minute the three trains stand in their ring.
    private static func ring() throws -> GameWorld {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("SaveFixtures/v107-depot-ladder-ring.json"))
        var world = try JSONDecoder().decode(SavedGame.self, from: data).world
        world.passesHeldTrains = true
        world.setSpeed(.normal)
        for _ in 0..<12 where world.deadlockedTrains().isEmpty { try world.advance(ticks: 1) }
        return world
    }

    func testTheMapMarksTheTrainsOfARingAsDeadlocked() throws {
        let world = try Self.ring()
        XCTAssertFalse(world.isTrafficControlEnabled)
        let stuck = world.deadlockedTrains()
        XCTAssertEqual(stuck.map(\.rawValue), [6, 12, 13])
        let overlay = world.trafficOverlay()
        XCTAssertEqual(overlay.waits.map(\.train), stuck)
        XCTAssertTrue(overlay.waits.allSatisfy { $0.isDeadlocked && $0.reason == .deadlock })
        XCTAssertEqual(overlay.authorities.count, 0)
        XCTAssertEqual(overlay.summary(in: .english), "3 deadlocked")
        // A bubble over each, which goes to the train.
        let bubbles = world.situationAlerts().compactMap { alert -> TrainID? in
            if case .trainStuck(let train) = alert.kind { return train }
            return nil
        }
        XCTAssertEqual(bubbles.sorted(), stuck)
    }

    func testATrainsCardNamesTheTrainItIsStuckWith() throws {
        let world = try Self.ring()
        let name = { (id: Int) in world.train(id: TrainID(rawValue: id))?.name ?? "?" }
        XCTAssertEqual(world.routeWaitText(of: TrainID(rawValue: 6), in: .english), "Deadlocked with \(name(13))")
        XCTAssertEqual(world.routeWaitText(of: TrainID(rawValue: 13), in: .traditionalChinese), "與 \(name(12)) 互相卡住（死結）")
        // The reading the game loop takes says the same, and nothing of
        // a train that is not held.
        var reading = TrafficReading(world: world, in: .english)
        XCTAssertEqual(reading.overlay.waits.count, 3)
        XCTAssertEqual(reading.waitText(of: TrainID(rawValue: 12), in: world, language: .english), "Deadlocked with \(name(6))")
        let free = try XCTUnwrap(world.trains.first { $0.position != nil && !world.deadlockedTrains().contains($0.id) })
        XCTAssertEqual(reading.waitText(of: free.id, in: world, language: .english), world.routeWaitText(of: free.id, in: .english))
    }

    /// A minute on one of them has gone first, and the marks are gone.
    func testTheMarksGoWhenOneHasGoneFirst() throws {
        var world = try Self.ring()
        try world.advance(ticks: 1)
        XCTAssertEqual(world.deadlockedTrains(), [])
        XCTAssertEqual(world.trafficOverlay().waits.count, 0)
    }
}
