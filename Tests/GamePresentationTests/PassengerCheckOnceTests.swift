import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 275's one edit for two commands made of many GameCore steps
/// (派工單 perf-real-map-600x). 0.5.0 (96.1), the author's real map of 64 stations, 15 lines and 68
/// trains: buying the Danhai light rail stopped the screen for 54 s. Each
/// step of laying a line bought (a track, a platform, its runs, a train)
/// was a command of its own for the passengers, and after each GameCore
/// looked again at every group waiting on the map, each line's journey
/// worked out afresh (``GameWorld/abandonUnservedPassengers()``): 24 s to
/// buy it on Linux, and as long again to lay its offer. A purchase is now
/// one edit for them (decision 275's ``GameWorld/editTrackAsOne(_:)``),
/// and so is removing a line and selling its trains (0.3–0.6 s each on
/// that map).
@MainActor
final class PassengerCheckOnceTests: XCTestCase {
    /// A game round the Neiwan Line with the Liujia Line bought and run
    /// eight hours, so groups wait at its stations and Zhuzhong,
    /// the station the Neiwan Line shares, with the Neiwan Line's offer.
    private func gameWithRidersWaiting() throws -> (GameSession, RealLineAcquisition) {
        let session = try RealLineAcquisitionTests.game(round: "NEIWAN", side: 1 << 21, heights: true, rules: .realistic)
        let liujia = try XCTUnwrap(session.buyableRealLines.first { $0.network == "LIUJIA" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: liujia)), session.message?.text ?? "")
        if session.world.clock.isPaused { session.togglePause() }
        session.advance(ticks: 8 * 60)
        let neiwan = try XCTUnwrap(session.buyableRealLines.first { $0.network == "NEIWAN" })
        let acquisition = try XCTUnwrap(session.realLineOffer(for: neiwan).acquisition, "the Neiwan Line's offer")
        let waiting = session.world.passengers.reduce(Int64(0)) { $0 + $1.waiting.reduce(0) { $0 + $1.count } }
        XCTAssertGreaterThan(waiting, 0, "groups wait when the line is bought")
        return (session, acquisition)
    }

    /// The world a purchase made as one edit leaves, and its price, are
    /// those it left a step at a time: nothing in a purchase takes a
    /// service away, so no group a later step serves again was sent away.
    func testOneEditBuysWhatTheStepsDid() throws {
        let (session, acquisition) = try gameWithRidersWaiting()
        var stepped = session.world, asOne = session.world
        let steppedPrice = try session.buildStepByStep(acquisition, in: &stepped)
        let oneEditPrice = try session.build(acquisition, in: &asOne)
        XCTAssertEqual(oneEditPrice, steppedPrice)
        XCTAssertEqual(asOne.passengers, stepped.passengers)
        XCTAssertEqual(asOne.riders, stepped.riders)
        XCTAssertEqual(asOne, stepped)
        XCTAssertNotEqual(asOne, session.world, "the line was built")

        // A day on, the two worlds are still one.
        try stepped.advance(ticks: 24 * 60)
        try asOne.advance(ticks: 24 * 60)
        XCTAssertEqual(asOne, stepped)
    }

    /// The purchase looks at the waiting groups once, not after every
    /// step: on the same machine, with groups waiting, laying it as one
    /// edit takes well under half what the steps one at a time took (a
    /// quarter on Linux in debug; the steps' own track work is the rest).
    func testOneEditLooksAtTheWaitingGroupsOnce() throws {
        let (session, acquisition) = try gameWithRidersWaiting()
        let clock = ContinuousClock()
        func fastest(_ build: () throws -> Void) rethrows -> Duration {
            var best = Duration.seconds(3_600)
            for _ in 0..<3 { best = min(best, try clock.measure(build)) }
            return best
        }
        let stepped = try fastest {
            var world = session.world
            _ = try session.buildStepByStep(acquisition, in: &world)
        }
        let asOne = try fastest {
            var world = session.world
            _ = try session.build(acquisition, in: &world)
        }
        print("Neiwan Line bought with groups waiting: step by step \(stepped), as one edit \(asOne)")
        XCTAssertLessThan(asOne * 2, stepped, "step by step \(stepped), as one edit \(asOne)")
    }

    /// Removing a line and selling its trains as one edit leaves the world
    /// the steps one at a time left: riders aboard its trains, groups
    /// waiting for it and for the line it meets at Zhuzhong.
    func testOneEditRemovesWhatTheStepsDid() throws {
        let (session, acquisition) = try gameWithRidersWaiting()
        var world = session.world
        _ = try session.build(acquisition, in: &world)
        try world.advance(ticks: 3 * 60)
        let riding = world.riders.reduce(Int64(0)) { $0 + $1.groups.reduce(0) { $0 + $1.count } }
        XCTAssertGreaterThan(riding, 0, "riders aboard when the line is removed")
        for realLine in ["tra:LIUJIA", "tra:NEIWAN"] {
            let line = try XCTUnwrap(world.acquisition(of: realLine)?.line)
            XCTAssertFalse(try XCTUnwrap(world.line(id: line)).assignedTrains.isEmpty, realLine)
            var stepped = world, asOne = world
            let steppedSold = try GameSession.removeLineSellingTrainsStepByStep(line, in: &stepped)
            let oneEditSold = try GameSession.removeLineSellingTrains(line, in: &asOne)
            XCTAssertEqual(oneEditSold, steppedSold, realLine)
            XCTAssertEqual(asOne.passengers, stepped.passengers, realLine)
            XCTAssertEqual(asOne.riders, stepped.riders, realLine)
            XCTAssertEqual(asOne, stepped, realLine)
            try stepped.advance(ticks: 12 * 60)
            try asOne.advance(ticks: 12 * 60)
            XCTAssertEqual(asOne, stepped, "\(realLine), half a day on")
        }
    }
}
