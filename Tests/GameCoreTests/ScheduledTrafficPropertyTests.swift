import Foundation
@testable import GameCore
import XCTest

/// traffic.scheduledMeets: source thresholds, two-way meets, overtakes,
/// repeating out-and-back services, delayed peer movement, traffic
/// toggles, saves and exact batched time, short and long. Every step
/// compares the whole world and the independent V3 plan; a repeating case
/// that ends with a service still in its first cycle must show it in a
/// deadlock, never wait in silence.
///
/// The campaign has 24 cases a seed. V4a adds three-train cases 18 to 23
/// across ScheduledOvertakeTrackPropertyTests, its Middle, Last and Final classes
/// on campaigns-15 to 18; the original
/// cases and their generators are unchanged. This class runs cases 0 to 8 of every
/// seed and ``ScheduledTrafficSecondHalfPropertyTests`` cases 9 to 17, on a
/// shard of their own (the whole campaign no longer fitted one job). A case
/// is the same case whichever class runs it: its generator comes from its
/// seed and index alone.
final class ScheduledTrafficPropertyTests: XCTestCase {
    func testScheduledTrafficMatchesTheIndependentModel() throws {
        try Self.checkHalf(Self.campaign(cases: 0..<9))
    }

    /// What either half (12 cases of each kind) must have done.
    static func checkHalf(_ tally: [String: Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tally["ran"], 36, file: file, line: line)
        XCTAssertEqual(tally["repeatingCases"], 12, file: file, line: line)
        XCTAssertGreaterThan(tally["waits", default: 0], 40, file: file, line: line)
        XCTAssertGreaterThan(tally["visits", default: 0], 40, file: file, line: line)
        XCTAssertEqual(tally["operations"], 1_296, file: file, line: line)
        XCTAssertEqual(tally["saves"], 156, file: file, line: line)
        XCTAssertEqual(tally["longAdvances"], 180, file: file, line: line)
    }

    /// Cases `cases` of every seed of traffic.scheduledMeets; prints their
    /// digest and returns the tally, with `ran` the cases run.
    static func campaign(cases: Range<Int>) throws -> [String: Int] {
        var digest = Digest(), tally: [String: Int] = [:]
        try runCampaign("traffic.scheduledMeets", cases: 24) { testCase in
            guard cases.contains(testCase.index) else { return }
            tally["ran", default: 0] += 1
            let trackCase = testCase.index >= 18
            let kind = trackCase ? 1 : testCase.index % 3
            var world = trackCase ? try ScheduledOvertakeTrackTests.threeTrains(departure: 300 + Int64(testCase.random.below(180))) : kind == 1
                ? try ScheduledTrafficTests.overtake(fastDeparture: 180 + Int64(testCase.random.below(40)), fastArrival: 600 + Int64(testCase.random.below(90)))
                : kind == 2 ? try ScheduledTrafficTests.repeatingMeet() : try ScheduledTrafficTests.meet()
            if kind == 2 { tally["repeatingCases", default: 0] += 1 }
            if trackCase {
                tally["trackCases", default: 0] += 1
                if !world.scheduledTrafficWaits().contains(where: { $0.kind == .overtake && $0.train.rawValue == 1 }) {
                    tally["deniedOvertakes", default: 0] += 1
                }
            }
            var model = ScheduledTrafficTests.model(for: world)
            func compare() -> [String] {
                var problems = KernelDifferentialTests.differences(world, model, lineAnswers: false)
                let plan = model.scheduledPlan()
                if world.scheduledTrafficWaits() != plan.waits { problems.append("scheduled plan") }
                for train in world.trains {
                    let expected = model.waitingScheduled(model.trains.first { $0.id == train.id.rawValue }!, plan: plan)
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
                } else if step % 7 == 3 {
                    // One long call: the plan must follow the trains
                    // within it as it does second by second.
                    operation = .advance(15 + testCase.random.below(15))
                    tally["longAdvances", default: 0] += 1
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
            if kind == 2 {
                let stuck = world.deadlockedTrains()
                for train in world.trains where (train.execution?.cycle ?? 1) < 1 && !stuck.contains(train.id) {
                    testCase.fail("train \(train.id.rawValue) is still in its first cycle at \(world.clock.now.seconds) with no deadlock shown")
                    return
                }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] traffic.scheduledMeets cases \(cases.lowerBound)-\(cases.upperBound - 1) \(digest.hex) (\(tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")))")
        return tally
    }
}

/// Cases 9 to 17 of traffic.scheduledMeets (see
/// ``ScheduledTrafficPropertyTests``).
final class ScheduledTrafficSecondHalfPropertyTests: XCTestCase {
    func testScheduledTrafficMatchesTheIndependentModel() throws {
        try ScheduledTrafficPropertyTests.checkHalf(ScheduledTrafficPropertyTests.campaign(cases: 9..<18))
    }
}

/// Additional cases of the same campaign; no original case was reduced.
final class ScheduledOvertakeTrackPropertyTests: XCTestCase {
    static func check(_ cases: Range<Int>, saves: Int, runs: Int = 8) throws {
        let tally = try ScheduledTrafficPropertyTests.campaign(cases: cases)
        XCTAssertEqual(tally["ran"], runs)
        XCTAssertEqual(tally["trackCases"], runs)
        XCTAssertEqual(tally["deniedOvertakes"], runs)
        XCTAssertEqual(tally["operations"], runs * 36)
        XCTAssertEqual(tally["saves"], saves)
        XCTAssertEqual(tally["longAdvances"], runs * 5)
    }

    func testScheduledTrafficWithAThirdStationMovement() throws {
        try Self.check(18..<20, saves: 36)
    }
}

final class ScheduledOvertakeTrackMiddlePropertyTests: XCTestCase {
    func testScheduledTrafficWithAThirdStationMovement() throws {
        try ScheduledOvertakeTrackPropertyTests.check(20..<22, saves: 36)
    }
}

final class ScheduledOvertakeTrackLastPropertyTests: XCTestCase {
    func testScheduledTrafficWithAThirdStationMovement() throws {
        try ScheduledOvertakeTrackPropertyTests.check(22..<23, saves: 16, runs: 4)
    }
}

final class ScheduledOvertakeTrackFinalPropertyTests: XCTestCase {
    func testScheduledTrafficWithAThirdStationMovement() throws {
        try ScheduledOvertakeTrackPropertyTests.check(23..<24, saves: 16, runs: 4)
    }
}
