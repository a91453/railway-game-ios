import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 614 (PERF-115): what one build command costs on a late-game
/// network, from the press to the ticks after it. Run on request.
///
/// Make the save (not committed; a generated game, kept in a scratch
/// directory):
///
///     PERF_MAKE_SAVE=/tmp/big.json swift test -c release -Xswiftc -enable-testing \
///       --skip-build --filter BuildCommandCostReportTests/testMakingALateGameSave
@MainActor
final class BuildCommandCostReportTests: XCTestCase {
    static func ms(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Taipei with every line on sale bought that its money allows, played
    /// a few game hours so the trains are out.
    func testMakingALateGameSave() throws {
        guard let path = ProcessInfo.processInfo.environment["PERF_MAKE_SAVE"] else {
            throw XCTSkip("set PERF_MAKE_SAVE=<file> to make the save")
        }
        let session = try RealLineAcquisitionTests.game(round: "trtc:BL", side: 1 << 22, heights: true)
        let lines = Int(ProcessInfo.processInfo.environment["PERF_LINES"] ?? "") ?? 40
        print("PERF115 on sale: \(session.buyableRealLines.map(\.id).joined(separator: " "))")
        var bought = 0
        for _ in 0..<lines {
            guard let line = session.buyableRealLines.first(where: { session.realLineOffer(for: $0).problem == nil }) else { break }
            let offer = session.realLineOffer(for: line)
            if session.acquireRealLine(offer) { bought += 1; print("PERF115 bought \(line.id)") } else { break }
        }
        print("PERF115 bought \(bought): stations \(session.world.stations.count), lines \(session.world.lines.count), trains \(session.world.trains.count), edges \(session.world.network.edges.count)")
        var world = session.world
        world.setSpeed(.normal)
        try world.advance(ticks: Int(ProcessInfo.processInfo.environment["PERF_HOURS"] ?? "").map { $0 * 60 } ?? 180)
        print("PERF115 at \(world.clock.now.clockText): trains \(world.trains.count)")
        try SaveLibrary.encode(world, at: Date()).write(to: URL(fileURLWithPath: path))
    }
}
