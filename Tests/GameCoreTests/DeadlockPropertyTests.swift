import Foundation
import GameCore
import XCTest

/// Decision 58 (Stage V2): a bounded campaign of deadlocks on the single
/// track with a passing loop at M. Expresses and stopping services set off
/// towards each other from W, E and M, some with a train parked on the loop
/// so that no passing place helps; idle trains are sent back the other way.
/// ReferenceWorld advances every second and finds deadlocks in rounds;
/// GameCore batches seconds and takes trains away one at a time. Every step
/// compares the whole state, the holds, the waits and the deadlocked trains.
final class DeadlockPropertyTests: XCTestCase {
    typealias Operation = OccupiedRoutingPropertyTests.Operation

    func testDeadlocksResolveAtPassingPlacesAndMatchTheReferenceAtEveryStep() throws {
        var tally: [String: Int] = [:]
        var digest = Digest()
        let cases = 8
        let ran = try runCampaign("traffic.deadlock", cases: cases) { testCase in
            var world = try SingleTrackMeet.world()
            var model = SingleTrackMeet.model()
            func compare() -> [String] {
                var problems = KernelDifferentialTests.differences(world, model, lineAnswers: false)
                for train in world.trains {
                    if world.reservedResources(of: train.id) != model.reservedResources(of: train.id) { problems.append("reservation \(train.id)") }
                    if world.heldResources(of: train.id) != model.heldResources(of: train.id) { problems.append("held \(train.id)") }
                    if world.trainHoldingRoute(of: train.id) != model.trainHoldingRoute(of: train.id) { problems.append("holder \(train.id)") }
                    if world.contestedResources(of: train.id) != model.contestedResources(of: train.id) { problems.append("contested \(train.id)") }
                }
                if world.deadlockedTrains() != model.deadlockedTrains() {
                    problems.append("deadlocked \(world.deadlockedTrains()) vs \(model.deadlockedTrains())")
                }
                if world.routeWaits() != WorldInvariants.routeWaitsOneByOne(in: world) { problems.append("route waits") }
                problems += WorldInvariants.violations(in: world)
                if let problem = WorldInvariants.roundTripProblem(of: world) { problems.append(problem) }
                return problems
            }
            func perform(_ operation: Operation) -> Bool {
                testCase.note("\(world.clock.now.seconds): \(operation)")
                let outcome = operation.apply(to: &world)
                let expected = operation.apply(to: &model)
                guard outcome == expected else { testCase.fail("outcomes \(String(describing: outcome)) vs \(String(describing: expected))"); return false }
                let problems = compare()
                guard problems.isEmpty else { testCase.fail(problems.joined(separator: "\n")); return false }
                tally["operations", default: 0] += 1
                return true
            }
            func place(_ traversal: TrackTraversal, at offset: Int64, cars: Int) throws -> TrainID {
                let id = try SingleTrackMeet.stand(&world, edge: traversal, offset: offset, cars: cars)
                XCTAssertNil(model.purchaseTrain(named: "T"))
                XCTAssertNil(model.setCars(id, cars))
                XCTAssertNil(model.placeTrain(id, at: .onEdge(traversal, offset: offset)))
                XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: offset))
                XCTAssertNil(model.setRate(id, 1_024))
                return id
            }
            func calls(_ stations: [StationID], from start: Int64, reverses: Bool = false) -> [ScheduledStop] {
                stations.enumerated().map { index, station in
                    let time = GameTime(seconds: start + Int64(index) * 120 * (stations.count == 2 ? 2 : 1))
                    return ScheduledStop(station: station, arrival: time, departure: time, reverses: index == 0 && reverses)
                }
            }
            let (w, m, e) = (SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east)
            let kind = testCase.index % 4
            let east = try place(SingleTrackMeet.forward(1), at: 3_072, cars: 1 + testCase.random.below(3))
            let west = try place(SingleTrackMeet.backward(3), at: 3_072, cars: 1 + testCase.random.below(3))
            var parked: TrainID?
            if kind == 1 {
                parked = try place(SingleTrackMeet.forward(5), at: 5_120, cars: 2)
            } else if kind == 3 {
                _ = try place(SingleTrackMeet.forward(2), at: 9_216, cars: 1 + testCase.random.below(3))
            }
            try world.setTrafficControl(true)
            XCTAssertNil(model.setTrafficControl(true))
            let express = kind != 2 || testCase.random.chance(1, in: 2)
            guard perform(.run(east, calls(express ? [w, e] : [w, m, e], from: Int64(testCase.random.below(31))))),
                  perform(.run(west, calls(kind == 2 && express ? [e, m, w] : [e, w], from: Int64(testCase.random.below(31))))) else { return }
            if kind == 3 {
                guard perform(.run(TrainID(rawValue: 3), calls([m, e], from: 30 + Int64(testCase.random.below(60))))) else { return }
            }
            for step in 0..<40 {
                let before = world
                let operation: Operation
                if let lot = parked, step == 20, testCase.random.chance(1, in: 2) {
                    // The parked train leaves the loop: the deadlock opens.
                    let now = world.clock.now.seconds
                    operation = .run(lot, [ScheduledStop(station: m, arrival: .init(seconds: now), departure: .init(seconds: now)),
                                           ScheduledStop(station: e, arrival: .init(seconds: now + 240), departure: .init(seconds: now + 240))])
                    parked = nil
                } else if step > 4, testCase.random.chance(1, in: 10) {
                    operation = .rate(testCase.random.element(of: world.trains).id, testCase.random.element(of: [0, 1_024, 2_048]))
                } else if step > 8, let idle = world.trains.first(where: { $0.execution == nil && $0.id != parked }),
                          let here = world.stationsStoppedAt(by: idle.id).first, here == w || here == e {
                    let toEast = here == w
                    guard case .onEdge(let traversal, _) = idle.position! else { preconditionFailure() }
                    let reverse = (traversal.direction == .forward) != toEast
                    let stations = testCase.random.chance(1, in: 2) ? [here, toEast ? e : w] : [here, m, toEast ? e : w]
                    operation = .run(idle.id, calls(stations, from: world.clock.now.seconds, reverses: reverse))
                } else {
                    operation = .advance(1)
                }
                guard perform(operation) else { return }
                if !world.deadlockedTrains().isEmpty { tally["deadlocked steps", default: 0] += 1 }
                for (old, new) in zip(before.trains, world.trains) {
                    if world.passingPlace(of: new.id) != nil, before.passingPlace(of: old.id) == nil {
                        tally["passing places", default: 0] += 1
                    }
                    if old.execution != nil, new.execution == nil { tally["services completed", default: 0] += 1 }
                }
            }
            if !world.deadlockedTrains().isEmpty { tally["deadlocks left", default: 0] += 1 }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] traffic.deadlock \(digest.hex) (\(tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")))")
        assertVolume(ran == cases * PropertySeeds.active.count, "all cases ran")
        assertVolume(tally["deadlocked steps", default: 0] >= 16, "deadlocks were found")
        assertVolume(tally["passing places", default: 0] >= 8, "services stood aside at passing places")
        assertVolume(tally["services completed", default: 0] >= 16, "services completed")
        assertVolume(tally["deadlocks left", default: 0] >= 1, "a deadlock with no way out stayed")
    }
}
