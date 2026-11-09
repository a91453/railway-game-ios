import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// TYMC-AFTERNOON (docs/research/TYMC_AFTERNOON_2026-11-08.md), red until
/// it is fixed: the Taoyuan Airport MRT under a new game's rules (simple,
/// traffic control on). The evening shuttles between Huanbei and Airport
/// Terminal 1 come out of Qingpu, but the last ones end at Terminal 1
/// (decision 652's turn back) and go into Luzhu, the depot it reaches
/// soonest. By the second afternoon Qingpu stood empty, the run out of
/// Luzhu to Huanbei never found its way past the services along the line,
/// and six of the shuttles went without a train. Some twelve minutes (two
/// days of the line): `TYMC_AFTERNOON=1`.
@MainActor
final class AirportShuttleDepotTests: XCTestCase {
    func testTheSecondAfternoonsShuttlesAllGo() throws {
        guard ProcessInfo.processInfo.environment["TYMC_AFTERNOON"] != nil else {
            throw XCTSkip("Set TYMC_AFTERNOON=1 (two days of the line, some twelve minutes).")
        }
        var world = try DepotReturnReportTests.bought("tymc:A", rules: .simple, side: 1 << 22)
        XCTAssertTrue(world.isTrafficControlEnabled)
        world.setSpeed(.fast)
        // The second day, until the last evening shuttle's last chance.
        let day: Int64 = 1
        while world.clock.now.seconds < day * GameTime.secondsPerDay + 21 * 3_600 {
            try world.advance(ticks: 1)
        }
        let line = try XCTUnwrap(world.lines.first { $0.hasRuns && !$0.depots.isEmpty })
        let shuttle = Set(["環北站", "機場第一航廈站"])
        let missed = RunsNotSent.on(day, of: line, at: world.clock.now).compactMap { index -> String? in
            let run = line.runs[index]
            let names = [run.from, run.to].map { world.station(id: line.stops[$0])?.name ?? "?" }
            let leaves = run.start(onDay: day) % GameTime.secondsPerDay
            guard Set(names) == shuttle, leaves >= 15 * 3_600 else { return nil }
            return String(format: "%@ to %@ at %02d:%02d", names[0], names[1], leaves / 3_600, leaves % 3_600 / 60)
        }
        XCTAssertEqual(missed, [])
    }
}
