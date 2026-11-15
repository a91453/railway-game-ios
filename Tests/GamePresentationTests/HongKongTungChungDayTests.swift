import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// The Tung Chung Line bought and run on Hong Kong's map
/// (`HongKongMapTests`); a class of its own so the CI shards can deal it
/// apart from the other Hong Kong tests.
@MainActor
final class HongKongTungChungDayTests: XCTestCase {
    private func hongKong(demo: Bool = false) throws -> GameSession {
        try HongKongMapTests.hongKong(demo: demo)
    }

    /// The Tung Chung Line bought and run for two days on the map: all
    /// but the last run of each peak was sent out the second day, and
    /// people rode.
    func testTheTungChungLineRunsOnTheMap() throws {
        let session = try hongKong()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "hkmtr:TCL" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        var played = session.world
        let bought = try XCTUnwrap(played.acquisition(of: "hkmtr:TCL"))
        for _ in 0..<51 { try played.advance(ticks: 60) }
        let ran = try XCTUnwrap(played.line(id: try XCTUnwrap(bought.line)))
        let today = played.clock.now.seconds / GameTime.secondsPerDay
        let missed = zip(ran.runs, ran.runDays).filter { run, day in
            run.days & (1 << StationDemand.weekday(ofDay: today - 1)) != 0 && (day ?? -1) < today - 1
        }
        // The last run of each six-minute peak, each way, is still dropped
        // (4 of 282): one train holds the whole stretch from Sunny Bay to
        // Tung Chung, seven minutes, so the peak falls behind until its
        // last runs are too late to send. A rule of GameCore, left as it
        // is (docs/handoff/AIR-UNLOCK.md); before the trains standing
        // overnight were moved out of the way it was 22.
        XCTAssertLessThanOrEqual(missed.count, 4, "runs not sent out yesterday: \(missed.count) of \(ran.runs.count)")
        XCTAssertGreaterThan(played.accounts.days.last?.fareRevenue ?? .zero, .zero, "people rode")
    }
}
