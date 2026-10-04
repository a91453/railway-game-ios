import Foundation
import GameCore
import XCTest

/// Decision 57: a bounded campaign on a single track with a passing loop.
/// ReferenceWorld advances every second and relaxes distances to berths;
/// GameCore batches seconds and uses its ordered shortest-path search.
final class OccupiedRoutingPropertyTests: XCTestCase {
    enum Operation {
        case rate(TrainID, Int64)
        case run(TrainID, [ScheduledStop])
        case advance(Int)
        case line(TrainID)

        func apply(to world: inout GameWorld) -> GameError? {
            do throws(GameError) {
                switch self {
                case .rate(let id, let rate): try world.setTrainMovementRate(id, to: rate)
                case .run(let id, let stops):
                    try world.setTrainTimetable(id, to: stops)
                    try world.startTrainService(id)
                case .advance(let ticks): try world.advance(ticks: ticks)
                case .line(let id):
                    let line = try world.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
                    try world.setLineServiceWindow(line, to: .allDay)
                    try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
                    try world.assignTrain(id, to: line)
                }
                return nil
            } catch { return error }
        }

        func apply(to model: inout ReferenceWorld) -> GameError? {
            switch self {
            case .rate(let id, let rate): return model.setRate(id, rate)
            case .run(let id, let stops): return model.setTimetable(id, stops, period: nil) ?? model.startService(id)
            case .advance(let ticks): return model.advance(ticks: ticks)
            case .line(let id):
                return model.createLine(named: "L", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east])
                    ?? model.setLineWindow(.init(rawValue: 1), .allDay)
                    ?? model.setLineTrains(.init(rawValue: 1), TrainsInService(peak: 1, offPeak: 1, low: 1))
                    ?? model.assign(id, to: .init(rawValue: 1))
            }
        }
    }

    func testServicesChooseUnblockedBerthsAndMatchTheReferenceAtEveryStep() throws {
        var tally: [String: Int] = [:]
        var digest = Digest()
        let cases = 8
        let ran = try runCampaign("traffic.occupiedRouting", cases: cases) { testCase in
            let doubleTrack = testCase.index >= 6
            var world = try doubleTrack ? DoubleTrackCrossover.world() : SingleTrackMeet.world()
            var model = doubleTrack ? DoubleTrackCrossover.model() : SingleTrackMeet.model()
            func compare() -> [String] {
                var problems = KernelDifferentialTests.differences(world, model, lineAnswers: false)
                if world.isTrafficControlEnabled != model.trafficControl { problems.append("traffic control") }
                for train in world.trains {
                    if world.reservedResources(of: train.id) != model.reservedResources(of: train.id) { problems.append("reservation \(train.id)") }
                    if world.heldResources(of: train.id) != model.heldResources(of: train.id) { problems.append("held \(train.id)") }
                    if world.trainHoldingRoute(of: train.id) != model.trainHoldingRoute(of: train.id) { problems.append("holder \(train.id)") }
                }
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
            // Alternate opposing services with a train already at M heading
            // east and one behind it. Vary cars, departure delay, running
            // times and whether W is sent by a line.
            if doubleTrack {
                tally["double track cases", default: 0] += 1
                for (number, place) in [(SingleTrackMeet.forward(2), Int64(13_312)), (SingleTrackMeet.forward(1), 3_072), (SingleTrackMeet.backward(4), 4_096)].enumerated() {
                    let cars = 1 + testCase.random.below(3)
                    let id = try SingleTrackMeet.stand(&world, edge: place.0, offset: place.1, cars: cars)
                    XCTAssertEqual(id.rawValue, number + 1)
                    XCTAssertNil(model.purchaseTrain(named: "T"))
                    XCTAssertNil(model.setCars(id, cars))
                    XCTAssertNil(model.placeTrain(id, at: .onEdge(place.0, offset: place.1)))
                    XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: place.1))
                    XCTAssertNil(model.setRate(id, 1_024))
                }
                try world.setTrafficControl(true)
                XCTAssertNil(model.setTrafficControl(true))
                let delay = Int64(testCase.random.below(31))
                guard perform(.run(.init(rawValue: 1), DoubleTrackCrossover.calls([(SingleTrackMeet.middle, 180 + delay), (SingleTrackMeet.east, 420 + delay)]))),
                      perform(.run(.init(rawValue: 3), DoubleTrackCrossover.calls([(SingleTrackMeet.east, 60), (SingleTrackMeet.middle, 300), (SingleTrackMeet.west, 540)]))) else { return }
                let follower: Operation = testCase.index == 7 ? .line(.init(rawValue: 2))
                    : .run(.init(rawValue: 2), DoubleTrackCrossover.calls([(SingleTrackMeet.west, 0), (SingleTrackMeet.middle, 180), (SingleTrackMeet.east, 420)]))
                guard perform(follower) else { return }
            } else {
                let opposing = testCase.index % 2 == 0
                for number in 1...2 {
                    let run = number == 1 ? SingleTrackMeet.forward(1) : opposing ? SingleTrackMeet.backward(3) : SingleTrackMeet.forward(2)
                    let offset: Int64 = number == 2 && !opposing ? 9_216 : 3_072
                    let cars = 1 + testCase.random.below(3)
                    let id = try SingleTrackMeet.stand(&world, edge: run, offset: offset, cars: cars)
                    XCTAssertNil(model.purchaseTrain(named: "T"))
                    XCTAssertNil(model.setCars(id, cars))
                    XCTAssertNil(model.placeTrain(id, at: .onEdge(run, offset: offset)))
                    XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: offset))
                    XCTAssertNil(model.setRate(id, 1_024))
                }
                try world.setTrafficControl(true)
                XCTAssertNil(model.setTrafficControl(true))
                for number in 1...2 {
                    let id = TrainID(rawValue: number)
                    if number == 1, testCase.index % 3 == 2 {
                        guard perform(.line(id)) else { return }
                        continue
                    }
                    var stops = SingleTrackMeet.timetable(eastbound: number == 1 || !opposing, delay: Int64(testCase.random.below(16)))
                    if number == 2, !opposing { stops.removeFirst() }
                    // Keep first departure close enough for simultaneous route
                    // requests, but vary the second leg and M's dwell.
                    if number == 2, !opposing { stops[0] = ScheduledStop(station: SingleTrackMeet.middle, arrival: .init(seconds: 0), departure: .init(seconds: 60)) }
                    guard perform(.run(id, stops)) else { return }
                }
            }
            for step in 0..<36 {
                let before = world
                let operation: Operation
                if step > 4, testCase.random.chance(1, in: 8) {
                    operation = .rate(testCase.random.element(of: world.trains).id, testCase.random.element(of: doubleTrack ? [1_024, 2_048] : [0, 1_024, 2_048]))
                } else if !doubleTrack, step > 8, let idle = world.trains.first(where: { $0.execution == nil && world.assignedLine(of: $0.id) == nil }),
                          let here = world.stationsStoppedAt(by: idle.id).first,
                          here == SingleTrackMeet.west || here == SingleTrackMeet.east {
                    let east = here == SingleTrackMeet.west
                    guard case .onEdge(let traversal, _) = idle.position! else { preconditionFailure() }
                    let reverse = (traversal.direction == .forward) != east
                    let now = world.clock.now.seconds
                    var stops = SingleTrackMeet.timetable(eastbound: east, delay: now)
                    stops[0] = ScheduledStop(station: here, arrival: .init(seconds: now), departure: .init(seconds: now), reverses: reverse)
                    operation = .run(idle.id, stops)
                } else {
                    operation = .advance(1)
                }
                guard perform(operation) else { return }
                for (old, new) in zip(before.trains, world.trains) {
                    if !doubleTrack, new.times?.departure != nil, new.times?.departure != old.times?.departure, new.movement.edges.contains(.edge(5)) {
                        tally["alternative platform departures", default: 0] += 1
                    }
                    if doubleTrack, new.id.rawValue == 2, old.times?.departure == nil, new.times?.departure != nil {
                        guard !new.movement.edges.contains(.edge(5)), !new.movement.edges.contains(.edge(4)) else {
                            testCase.fail("eastbound departure borrowed the opposing track"); return
                        }
                        tally["protected default departures", default: 0] += 1
                    }
                    if doubleTrack, new.id.rawValue == 3, old.execution != nil, new.execution == nil {
                        tally["opposing services completed", default: 0] += 1
                    }
                    if !world.stationsStoppedAt(by: new.id).isEmpty, world.stationsStoppedAt(by: new.id) != before.stationsStoppedAt(by: old.id) {
                        tally["arrivals", default: 0] += 1
                    }
                    if case .waitingAtStop? = new.execution, world.trainHoldingRoute(of: new.id) != nil { tally["waiting", default: 0] += 1 }
                }
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        print("[digest] traffic.occupiedRouting \(digest.hex) (\(tally.keys.sorted().map { "\($0) \(tally[$0]!)" }.joined(separator: ", ")))")
        assertVolume(ran == cases * PropertySeeds.active.count, "all cases ran")
        assertVolume(tally["alternative platform departures", default: 0] >= 16, "services used the alternative platform")
        assertVolume(tally["arrivals", default: 0] >= 40, "services reached stations")
        assertVolume(tally["waiting", default: 0] >= 4, "unavailable routes waited")
        assertVolume(tally["double track cases", default: 0] == 2 * PropertySeeds.active.count, "both double-track cases ran for every seed")
        assertVolume(tally["protected default departures", default: 0] >= 8, "eastbound trains stayed on their default track")
        assertVolume(tally["opposing services completed", default: 0] >= 8, "opposing trains completed without a circular wait")
    }
}
