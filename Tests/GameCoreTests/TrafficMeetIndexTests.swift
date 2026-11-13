import Foundation
import XCTest
@testable import GameCore

/// TICK-2 (`docs/research/TICK_2_2026-11-13.md`): the meets no longer scan
/// every point of every other service for the ones calling at a station
/// from (or toward) the next one; an index hands them over, in the order
/// the scan found them. Here every lookup is checked against that scan
/// (the game never pays for the check), over the recorded command streams
/// and over worlds of many trains; every property campaign runs under the
/// same check (see `runCampaign`).
final class TrafficMeetIndexTests: XCTestCase {
    /// Runs `body` with every lookup checked, and returns how many there were.
    static func audited<Result>(_ body: () throws -> Result) rethrows -> (result: Result, lookups: Int) {
        let audit = GameWorld.TrafficMeetAudit()
        let result = try GameWorld.$trafficMeetAudit.withValue(audit, operation: body)
        return (result, audit.lookups)
    }

    func testEveryRecordedStreamReplaysWithTheMeetsTheScanFinds() throws {
        var lookups = 0
        for url in try ReplayFixture.urls() {
            let name = url.lastPathComponent
            let fixture = try JSONDecoder().decode(ReplayFixture.self, from: Data(contentsOf: url))
            let operations = try fixture.commands.map { try XCTUnwrap($0.operation, name) }
            let start = try fixture.startWorld()
            let (replayed, count) = Self.audited {
                ReplayFixture.checksums(from: start, applying: operations, every: fixture.interval) { index, problem in
                    XCTFail("\(name): command \(index): \(problem)")
                }
            }
            XCTAssertEqual(replayed, fixture.checksums, name)
            lookups += count
        }
        XCTAssertGreaterThan(lookups, 0, "no stream ever looked up a meet, so nothing was checked")
    }

    func testManyTrainsFindTheMeetsTheScanFinds() throws {
        for (layout, trains) in [(TickScaleReportTests.Layout.meet, 12), (.ring, 8)] {
            for blocks in [false, true] {
                var world = try TickScaleReportTests.world(trains: trains, layout: layout, blocks: blocks, budget: 900)
                let unchecked: GameWorld = try {
                    var world = world
                    for _ in 0..<240 { try world.advance(ticks: 1) }
                    return world
                }()
                let (_, lookups) = try Self.audited {
                    for _ in 0..<240 { try world.advance(ticks: 1) }
                }
                XCTAssertEqual(world, unchecked, "\(layout) with \(trains) trains, block sections \(blocks): the check changed the world")
                XCTAssertGreaterThan(lookups, 0, "\(layout) with \(trains) trains, block sections \(blocks): no meet was ever looked up")
            }
        }
    }
}
