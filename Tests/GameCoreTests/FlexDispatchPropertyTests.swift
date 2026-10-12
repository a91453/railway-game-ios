import Foundation
@testable import GameCore
import XCTest

/// Flexible dispatch (decision 172) under the generated command sequences of
/// the dispatch campaign, with the world's switch on: lines edited, removed,
/// made rings, trains unassigned, held, moved and sent about while trains
/// run empty to an end of their line.
///
/// The reference world knows nothing of the switch, so this campaign has no
/// reference; what it checks is what must hold anyway.
///
/// - **Batches.** Every advance is also run as single ticks.
/// - **Invariants.** Every world reached keeps them
///   (``WorldInvariants/violations(in:)``), a train running empty carries no
///   riders and no cargo, and one that is not on a line has no empty run.
/// - **Saves.** The world each case ends in loads back equal and saves to
///   the same bytes.
///
/// `PROPERTY_REPLAY=flex.dispatch@<seed>@<case>` runs one case.
final class FlexDispatchPropertyTests: XCTestCase {
    func testGeneratedCommandsKeepTheInvariantsWithFlexibleDispatch() throws {
        var counts: [String: Int] = [:]
        var digest = Digest()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let ran = try runCampaign("flex.dispatch", cases: 16) { c in
            let (setup, operations) = try LineDispatchPropertyTests.generate(&c, operations: 70)
            c.note("setup: \(setup.summary), second \(setup.seconds), \(setup.speed)")
            var world = try setup.build().0
            world.setFlexDispatch(true)
            for (index, operation) in operations.enumerated() {
                let before = world
                let error = KernelDifferentialTests.apply(operation, to: &world)
                let at = "step \(index) \(operation)"
                if case .advance(let ticks) = operation, error == nil {
                    if let problem = ServicePropertyTests.batchProblem(ticks: ticks, from: before, batch: world) {
                        c.fail("\(at): \(problem)")
                        return
                    }
                }
                let problems = WorldInvariants.violations(in: world)
                c.expect(problems.isEmpty, "\(at): \(problems)")
                for train in world.trains where train.isDeadheading {
                    counts["train running empty", default: 0] += 1
                    c.expect(world.riders(of: train.id).isEmpty, "\(at): train \(train.id) runs empty with riders")
                    c.expect(world.cargoOnBoard(of: train.id) == 0, "\(at): train \(train.id) runs empty with cargo")
                    c.expect(world.assignedLine(of: train.id) != nil, "\(at): train \(train.id) runs empty off its line")
                }
            }
            let data = try encoder.encode(world)
            let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
            c.expect(loaded == world, "the world did not load back equal")
            let resaved = try encoder.encode(loaded)
            c.expect(resaved == data, "the same world saved to different bytes")
            digest.add(String(decoding: data, as: UTF8.self))
        }
        let summary = counts.keys.sorted().map { "\($0) \(counts[$0]!)" }.joined(separator: ", ")
        print("[digest] flex.dispatch \(digest.hex) (\(summary))")
        assertVolume(ran == 16 * PropertySeeds.active.count, "every case should run")
    }
}
