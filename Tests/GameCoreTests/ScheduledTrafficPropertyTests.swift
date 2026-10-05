import Foundation
@testable import GameCore
import XCTest

/// traffic.scheduledMeets: source thresholds, two-way meets, overtakes,
/// delayed peer movement, traffic toggles, saves and exact batched time.
/// Every step compares the whole world and the independent V3 plan.
final class ScheduledTrafficPropertyTests: XCTestCase {
    func testScheduledTrafficMatchesTheIndependentModel() throws {
        var digest = Digest(), tally: [String: Int] = [:]
        let ran = try runCampaign("traffic.scheduledMeets", cases: 12) { testCase in
            let overtake = testCase.index % 2 == 1
            var world = overtake
                ? try ScheduledTrafficTests.overtake(fastDeparture: 180 + Int64(testCase.random.below(40)), fastArrival: 600 + Int64(testCase.random.below(90)))
                : try ScheduledTrafficTests.meet()
            var model = ScheduledTrafficTests.model(for: world)
            func compare() -> [String] {
                var problems = KernelDifferentialTests.differences(world, model, lineAnswers: false)
                if world.scheduledTrafficWaits() != model.scheduledPlan().waits { problems.append("scheduled plan") }
                for train in world.trains {
                    let expected = model.waitingScheduled(model.trains.first { $0.id == train.id.rawValue }!, plan: model.scheduledPlan())
                    if world.scheduledTrafficWait(of: train.id) != expected { problems.append("scheduled wait \(train.id)") }
                    if world.reservedResources(of: train.id) != model.reservedResources(of: train.id) { problems.append("reservation \(train.id)") }
                    if world.heldResources(of: train.id) != model.heldResources(of: train.id) { problems.append("held \(train.id)") }
                    if world.trainHoldingRoute(of: train.id) != model.trainHoldingRoute(of: train.id) { problems.append("holder \(train.id)") }
                }
                if world.deadlockedTrains() != model.deadlockedTrains() { problems.append("deadlock") }
                problems += WorldInvariants.violations(in: world)
                if let problem = WorldInvariants.roundTripProblem(of: world) { problems.append(problem) }
                return problems
            }
            for step in 0..<36 {
                testCase.note("\(step) at \(world.clock.now.seconds)")
                let operation: KernelDifferentialTests.Operation
                if step == 2 || step == 6 {
                    operation = .setRate(TrainID(rawValue: 2), step == 2 ? 0 : 1_024)
                    tally["delayChanges", default: 0] += 1
                } else if step == 12 && testCase.index % 3 == 0 {
                    try world.setTrafficControl(false)
                    XCTAssertNil(model.setTrafficControl(false))
                    operation = .saveAndLoad
                    tally["saves", default: 0] += 1
                    tally["trafficOff", default: 0] += 1
                } else if step % 9 == 0 {
                    operation = .saveAndLoad
                    tally["saves", default: 0] += 1
                } else {
                    operation = .advance(1 + testCase.random.below(3))
                }
                let before = world
                let actual = KernelDifferentialTests.apply(operation, to: &world), expected = KernelDifferentialTests.apply(operation, to: &model)
                guard actual == expected else { testCase.fail("outcomes \(String(describing: actual)) vs \(String(describing: expected))"); return }
                if case .advance(let ticks) = operation {
                    var seconds = before
                    seconds.setSpeed(.x1)
                    for _ in 0..<(ticks * 60) { try seconds.advance(ticks: 10) }
                    seconds.setSpeed(world.clock.speed)
                    guard seconds == world else { testCase.fail("batch differs from seconds"); return }
                }
                let problems = compare()
                guard problems.isEmpty else { testCase.fail(problems.joined(separator: "\n")); return }
                tally["operations", default: 0] += 1
                tally["waits", default: 0] += world.trains.filter { world.scheduledTrafficWait(of: $0.id) != nil }.count
                tally["visits", default: 0] += world.trains.reduce(0) { $0 + $1.trafficVisits.count }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] traffic.scheduledMeets \(digest.hex) (\(tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")))")
        XCTAssertEqual(ran, 48)
        XCTAssertGreaterThan(tally["waits", default: 0], 40)
        XCTAssertGreaterThan(tally["visits", default: 0], 40)
        XCTAssertEqual(tally["operations"], 1_728)
        XCTAssertEqual(tally["saves"], 208)
    }
}
