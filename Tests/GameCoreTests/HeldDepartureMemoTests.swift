import Foundation
import XCTest
@testable import GameCore

/// Decision 980 (TICK-HELD-ASK-ONCE): a departure kept from its way is
/// asked again every second, and its way round the trains in its way is
/// not searched for again while every step the last search was kept from
/// is kept from it still (``GameWorld/stillHasNoDetour(_:to:memo:)``).
///
/// Here a memo carried from second to second, as an advance carries its
/// own, answers every due departure as a memo that knows nothing does, on
/// a single track between two fans of berths (trains waiting at both
/// ends) and on the long-leg replay's ring (following, head-on meets and
/// a deadlock), and each search left out is checked against the search
/// itself (``GameWorld/AnswerAudit``, as `AnswerAuditTests` checks the
/// recorded streams and `SavedWorldTickReportTests` a saved game).
final class HeldDepartureMemoTests: XCTestCase {
    private static func text(_ reserving: GameWorld.Reserving) -> String {
        switch reserving {
        case .granted(let train): "granted \(train)"
        case .held(let id): "held by \(id.rawValue)"
        }
    }

    /// Asks every train's due departure of `world` with `carried` and
    /// with a memo of its own; returns how many were held, or fails.
    private func compare(_ world: GameWorld, carried: inout GameWorld.DirectionMemo, _ label: String) -> Int {
        var held = 0
        for train in world.trains {
            var fresh = GameWorld.DirectionMemo()
            guard let request = world.departureRequest(of: train, memo: &fresh) else { continue }
            let expected = world.takingDeparture(request, memo: &fresh)
            let answered = world.takingDeparture(request, memo: &carried)
            XCTAssertEqual(Self.text(answered), Self.text(expected), "\(label): train \(train.id.rawValue)")
            if case .held = expected { held += 1 }
        }
        return held
    }

    func testAKeptMemoAnswersHeldDeparturesAsOneThatKnowsNothing() throws {
        var fan = try FairSingleTrackTests.stream(east: [60, 61, 62], west: 63)
        fan.setSpeed(.x1)
        var ring = try LongLegReplayTests.world()
        ring.setSpeed(.x1)
        for (name, start, seconds) in [("fan", fan, 480), ("ring", ring, 600)] {
            var held = 0
            let (_, audit) = try AnswerAuditTests.audited {
                var world = start
                var carried = GameWorld.DirectionMemo()
                for second in 0..<seconds {
                    held += compare(world, carried: &carried, "\(name) second \(second)")
                    // A world tried ahead with the same memo in between,
                    // as `secondsUntilARouteFrees` tries one.
                    if second % 7 == 0, let train = world.trains.first(where: { $0.position != nil && $0.movement.rate > 0 }) {
                        var moved = train
                        moved.position = world.travelling(train, distance: 1_024).position
                        _ = compare(world.replacing(moved), carried: &carried, "\(name) second \(second), one train moved")
                    }
                    try world.advance(ticks: 10)
                }
            }
            XCTAssertGreaterThan(held, 500, "\(name): departures are held")
            XCTAssertGreaterThan(audit.detoursNotSearched, 200, "\(name): a held departure's way round is not searched for every second")
        }
    }
}
