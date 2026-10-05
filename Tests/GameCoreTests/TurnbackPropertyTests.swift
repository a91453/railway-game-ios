import Foundation
import GameCore
import XCTest

/// Decision 63: full-state differential checks after every command and
/// every randomly sized batch, with a separate one-second execution.
final class TurnbackPropertyTests: XCTestCase {
    func testTurnbacksAndReverseSidingsMatchAcrossCommandsBatchesAndSaves() throws {
        var steps = 0, reversed = 0, waiting = 0, completed = 0
        var digest = Digest()
        let cases = 6
        let ran = try runCampaign("traffic.turnbacks", cases: cases) { testCase in
            let kind = testCase.index
            var world: GameWorld
            var model: ReferenceWorld
            let train: TrainID
            if kind == 0 || kind == 4 {
                let setup = try TurnbackTests.switchback(control: kind != 4)
                (world, model, train) = (setup.0, setup.1, setup.3)
            } else {
                let setup = try TurnbackTests.reverseSiding(shortSiding: kind == 2, shortStart: kind == 3)
                (world, model, train) = (setup.0, setup.1, setup.2)
            }
            func compare() -> Bool {
                var problems = KernelDifferentialTests.differences(world, model)
                if world.scheduledTrafficWaits() != model.scheduledPlan().waits { problems.append("scheduled waits") }
                if world.deadlockedTrains() != model.deadlockedTrains() { problems.append("deadlock") }
                for unit in world.trains {
                    if world.reservedResources(of: unit.id) != model.reservedResources(of: unit.id) { problems.append("reservation") }
                    if world.heldResources(of: unit.id) != model.heldResources(of: unit.id) { problems.append("held") }
                    if world.trainHoldingRoute(of: unit.id) != model.trainHoldingRoute(of: unit.id) { problems.append("holder") }
                }
                problems += WorldInvariants.violations(in: world)
                if let problem = WorldInvariants.roundTripProblem(of: world) { problems.append(problem) }
                if !problems.isEmpty { testCase.fail(problems.joined(separator: "\n")) }
                return problems.isEmpty
            }
            guard compare() else { return }
            for step in 0..<32 {
                if kind == 4, step == 2 {
                    try world.setTrafficControl(true)
                    XCTAssertNil(model.setTrafficControl(true))
                    guard compare() else { return }
                }
                if kind == 5, step == 3 || step == 5 {
                    let rate: Int64 = step == 3 ? 0 : 1_024
                    try world.setTrainMovementRate(train, to: rate)
                    XCTAssertNil(model.setRate(train, rate))
                    guard compare() else { return }
                }
                let seconds = 20 + testCase.random.below(16)
                testCase.note("\(world.clock.now.seconds): advance \(seconds)s")
                var singles = world
                for _ in 0..<seconds { try singles.advance(ticks: 10) }
                let old = world.train(id: train)
                try world.advance(ticks: seconds * 10)
                XCTAssertNil(model.advance(ticks: seconds * 10))
                guard singles == world else { testCase.fail("batch differs from single seconds"); return }
                guard compare() else { return }
                if case .onEdge(let a, _)? = old?.position, case .onEdge(let b, _)? = world.train(id: train)?.position,
                   a.direction != b.direction { reversed += 1 }
                if !world.deadlockedTrains().isEmpty { waiting += 1 }
                if old?.execution != nil, world.train(id: train)?.execution == nil { completed += 1 }
                // Replace the running world by the actual decoded save, then
                // continue the same operations against the independent model.
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(SavedGame(world: world))
                world = try JSONDecoder().decode(SavedGame.self, from: data).world
                digest.add(String(decoding: data, as: UTF8.self))
                steps += 1
            }
        }
        print("[digest] traffic.turnbacks \(digest.hex) (steps \(steps), reversed \(reversed), waiting \(waiting), completed \(completed))")
        assertVolume(ran == cases * PropertySeeds.active.count, "all cases ran")
        assertVolume(steps == cases * PropertySeeds.active.count * 32, "all operations ran")
        assertVolume(reversed >= 16, "both intermediate and siding reversals executed")
        assertVolume(waiting >= 32, "unsafe siding requests stayed waiting")
        assertVolume(completed >= 12, "services completed after reversing")
    }
}
