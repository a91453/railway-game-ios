import Foundation
import XCTest
@testable import GameCore

/// TICK-L1 (`docs/research/TICK_L1_2026-11-13.md`): the track the trains hold is no longer worked out from
/// every train each time one of them changes; what the changed trains held
/// is taken out and what they hold now put in. Here every such answer is
/// checked against the holders worked out from every train (the game never
/// pays for the check), over the recorded command streams and over worlds
/// of many trains; every property campaign runs under the same check (see
/// `runCampaign`).
final class HolderUpdateTests: XCTestCase {
    /// Runs `body` with every answer changed in place checked, and returns
    /// how the answers were come by.
    static func audited<Result>(_ body: () throws -> Result) rethrows -> (result: Result, audit: GameWorld.HolderAudit) {
        let audit = GameWorld.HolderAudit()
        let result = try GameWorld.$holderAudit.withValue(audit, operation: body)
        return (result, audit)
    }

    func testEveryRecordedStreamReplaysWithTheHoldersItWouldWorkOut() throws {
        var updates = 0
        for url in try ReplayFixture.urls() {
            let name = url.lastPathComponent
            let fixture = try JSONDecoder().decode(ReplayFixture.self, from: Data(contentsOf: url))
            let operations = try fixture.commands.map { try XCTUnwrap($0.operation, name) }
            let start = try fixture.startWorld()
            let (replayed, audit) = Self.audited {
                ReplayFixture.checksums(from: start, applying: operations, every: fixture.interval) { index, problem in
                    XCTFail("\(name): command \(index): \(problem)")
                }
            }
            XCTAssertEqual(replayed, fixture.checksums, name)
            updates += audit.updates
        }
        XCTAssertGreaterThan(updates, 0, "no stream ever changed the holders in place, so nothing was checked")
    }

    func testManyTrainsKeepTheHoldersTheyWouldWorkOut() throws {
        for (layout, trains) in [(TickScaleReportTests.Layout.meet, 12), (.ring, 8)] {
            for blocks in [false, true] {
                var world = try TickScaleReportTests.world(trains: trains, layout: layout, blocks: blocks, budget: 900)
                let unchecked: GameWorld = try {
                    var world = world
                    for _ in 0..<240 { try world.advance(ticks: 1) }
                    return world
                }()
                let (_, audit) = try Self.audited {
                    for _ in 0..<240 { try world.advance(ticks: 1) }
                }
                XCTAssertEqual(world, unchecked, "\(layout) with \(trains) trains, block sections \(blocks): the check changed the world")
                XCTAssertGreaterThan(audit.updates, 240, "\(layout) with \(trains) trains, block sections \(blocks): the holders were hardly ever changed in place")
            }
        }
    }
}
