import Foundation
@testable import GameCore
import XCTest

final class SingleTrackCapacityTests: XCTestCase {
    func testIntegerUtilizationDoesNotDoubleChargeTripsCrossingMidnight() {
        for (work, gap, expected): (Int64, Int64, Int64) in [(0, 3, 0), (1, 3, 480), (660, 11, 86400), (281, 5, 80928), (300, 7, 61715)] {
            XCTAssertEqual(ServiceCapacityProfile.usage(work, headway: gap), expected)
            XCTAssertEqual(ReferenceWorld.Capacity.occupied(work, gap: gap), expected)
        }
        XCTAssertEqual(ServiceCapacityProfile.usage(.max, headway: .max), 1440)
        XCTAssertEqual(ServiceCapacityProfile.usage(.max, headway: 1), .max)
        XCTAssertEqual(ReferenceWorld.Capacity.occupied(.max, gap: .max), 1440)
    }

    func testAWholeSingleBlockIsSharedEvenByDisjointPartialPatterns() throws {
        var world = try SingleTrackMeet.world()
        let id = try world.createLine(named: "Capacity", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        let a = try world.addLinePattern(id, calling: [0, 1])
        let b = try world.addLinePattern(id, calling: [1, 2])
        let two = TrainsInService(peak: 2, offPeak: 2, low: 2)
        try world.setLineTrainsInService(id, to: two, pattern: a)
        try world.setLineTrainsInService(id, to: two, pattern: b)
        let line = try XCTUnwrap(world.line(id: id))
        let profile = ServiceCapacityProfile(work: [300, 300], minimumHeadway: 5, hasSingleTrack: true)
        let plan = line.services(at: .peak, roundTrips: [nil, 10, 10], capacities: [nil, profile, profile])
        XCTAssertNil(plan.plans[0])
        XCTAssertEqual(plan.plans[1]?.trains, 2)
        XCTAssertEqual(plan.plans[1]?.headway, 5)
        XCTAssertNil(plan.plans[2], "both partial patterns consume the same unsplittable resource")
        XCTAssertEqual(plan.loads, [288, 0])
    }

    /// Decision 61's independently hand-timed short track: 3072/3584 units,
    /// 20/21 running seconds, plus two 120 s terminals = 281 s = 5 min.
    /// No passing edge: the whole trip is one resource, 281 s, ceil=5 min.
    /// Legacy double-track maximum floor(5/2)=2, controlled single maximum1.
    static func short() throws -> (GameWorld, LineID) {
        var world = try GameWorld(bounds: .init(width: 8192, height: 8192), economy: .init(balance: 1_000_000, costs: .init(track: 0, station: 0, train: 0, car: 0)), clock: .init(speed: .normal))
        for x: Int64 in [1024, 3072, 5120] { try world.buildTrackNode(at: .init(x: x, y: 4096)) }
        try world.buildTrackEdge(from: .node(1), to: .node(2)); try world.buildTrackEdge(from: .node(2), to: .node(3))
        let west = try world.buildStation(named: "W", at: .init(x: 2048, y: 6144)).id
        let east = try world.buildStation(named: "E", at: .init(x: 4096, y: 6144)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 512, to: 1024)
        try world.addTrackPlatform(east, on: .edge(2), from: 512, to: 1024)
        try world.addTrackPlatform(east, on: .edge(2), from: 1536, to: 2048)
        let id = try world.createLine(named: "Single", stops: [west, east]).id
        let route = LineRoutePreference(from: 0, to: 1, tracks: [1, 2].map(SingleTrackMeet.forward), platform: world.trackPlatforms(of: east).last!)
        try world.setLineRoutePreferences(id, to: [route])
        try world.setLineTrainsInService(id, to: .init(peak: 4, offPeak: 4, low: 4))
        return (world, id)
    }

    func testHandTimedSingleTrackRetainsOneTrainAndTheDisabledLegacyPlan() throws {
        var (world, id) = try Self.short()
        let line = try XCTUnwrap(world.line(id: id)), journey = try XCTUnwrap(world.lineJourney(id))
        XCTAssertEqual(journey.legs.map(\.seconds), [20, 21])
        XCTAssertEqual(journey.roundTripSeconds, 281)
        XCTAssertEqual(world.lineMaximumTrains(id), 2)
        XCTAssertEqual(world.lineTrainsInService(id, at: .peak), 2)
        XCTAssertEqual(world.lineHeadway(id, at: .peak), 3)
        XCTAssertEqual(world.lineSegmentLoads(id, at: .peak), [480])
        try world.setTrafficControl(true)
        let layout = world.capacityLayout(of: line)
        XCTAssertEqual(layout.blocks, [[0]])
        XCTAssertEqual(layout.passing, [], "two stops on the same edge are not a meet")
        let capacity = world.capacityProfile(of: line, service: 0, journey: journey, layout: layout)
        XCTAssertEqual(capacity.work, [281])
        XCTAssertEqual(capacity.minimumHeadway, 5)
        XCTAssertEqual(world.lineMaximumTrains(id), 1)
        XCTAssertEqual(world.lineTrainsInService(id, at: .peak), 1)
        XCTAssertEqual(world.lineHeadway(id, at: .peak), 5)
        XCTAssertEqual(world.lineSegmentLoads(id, at: .peak), [288])
        XCTAssertEqual(world.line(id: id)?.trainsInService.peak, 4, "the player's requested count is preserved")
        let save = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: save).world, world)
        XCTAssertGreaterThanOrEqual(SavedGame.currentVersion, 10, "capacity uses the shared physical preferences of v10")
    }

    func testAnActualPassingLoopSplitsTheResourceAndRemovingItJoinsIt() throws {
        var (world, model, id, _) = try LineRoutePreferenceTests.setup()
        let line = try XCTUnwrap(world.line(id: id))
        let layout = world.capacityLayout(of: line)
        XCTAssertEqual(layout.blocks, [[0], [1]])
        XCTAssertEqual(layout.passing, [1])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        let platform = world.trackPlatforms(of: SingleTrackMeet.middle).first { $0.edge == .edge(5) }!
        try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
        XCTAssertNil(model.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start))
        XCTAssertEqual(world.capacityLayout(of: line).blocks, [[0, 1]])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    func testActualDoubleTrackKeepsTheLegacyPlanWithControlEnabled() throws {
        var world = try DoubleTrackCrossover.world(), model = DoubleTrackCrossover.model()
        let stops = [DoubleTrackCrossover.west, DoubleTrackCrossover.middle, DoubleTrackCrossover.east]
        let id = try world.createLine(named: "Double", stops: stops).id
        XCTAssertNil(model.createLine(named: "Double", stops: stops))
        let four = TrainsInService(peak: 4, offPeak: 4, low: 4)
        try world.setLineTrainsInService(id, to: four); XCTAssertNil(model.setLineTrains(id, four))
        let maximum = world.lineMaximumTrains(id), count = world.lineTrainsInService(id, at: .peak), gap = world.lineHeadway(id, at: .peak)
        try world.setTrafficControl(true); XCTAssertNil(model.setTrafficControl(true))
        XCTAssertEqual(world.lineTrackCounts(id), [2, 2])
        XCTAssertEqual(world.lineMaximumTrains(id), maximum)
        XCTAssertEqual(world.lineTrainsInService(id, at: .peak), count)
        XCTAssertEqual(world.lineHeadway(id, at: .peak), gap)
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    func testASingleRingWithoutAMeetCannotForceAnOpposingPair() throws {
        // Read only the existing ring geometry, stopping before trains are
        // placed. Its hand calculation is four 182 s legs + four 60 s dwells.
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GoldenScenarios/ring-line.json")
        let scenario = try GoldenScenario.decode(Data(contentsOf: path))
        var world = try scenario.initialState.makeWorld()
        let initial = scenario.initialState
        var model = ReferenceWorld(width: initial.worldWidth, height: initial.worldHeight, balance: initial.balance,
                                   costs: initial.costs.constructionCosts, seconds: initial.seconds, speed: initial.speed.speed)
        for step in scenario.steps {
            guard case .command(let command, let expect) = step else { continue }
            if case .purchaseTrain = command { break }
            XCTAssertEqual(command.apply(to: &world), expect)
            XCTAssertEqual(ReferenceWorldGoldenTests.apply(command, to: &model), expect)
        }
        let id = LineID(rawValue: 1)
        XCTAssertEqual(world.lineJourney(id)?.roundTripSeconds, 968)
        XCTAssertEqual(world.lineMaximumTrains(id), 16)
        try world.setTrafficControl(true)
        XCTAssertNil(model.setTrafficControl(true))
        let line = try XCTUnwrap(world.line(id: id)), layout = world.capacityLayout(of: line)
        XCTAssertEqual(layout.blocks, [[0, 1, 2, 3]])
        XCTAssertEqual(layout.passing, [])
        // Both laps occupy the same resource: 2*968=1936 s, G=33 min.
        // floor(17/33)=0 each way, rather than an unsafe forced pair.
        let inner = try XCTUnwrap(world.lineJourney(id))
        let outer = try XCTUnwrap(world.journey(of: line, service: 0, direction: .outer))
        XCTAssertEqual(outer.roundTripSeconds, 968)
        XCTAssertEqual(world.capacityProfile(of: line, service: 0, journey: inner, layout: layout, outer: outer).work, Array(repeating: 1936, count: 4))
        XCTAssertEqual(world.lineMaximumTrains(id), 0)
        XCTAssertEqual(world.lineTrainsInService(id, at: .peak), 0)
        XCTAssertNil(world.lineHeadway(id, at: .peak))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }
}

final class SingleTrackCapacityPropertyTests: XCTestCase {
    func testCapacityAndDispatchMatchTheModelWithAndWithoutAPassingLoop() throws {
        var steps = 0, digest = Digest()
        try runCampaign("line.singleTrackCapacity", cases: 6) { c in
            let pattern: Int? = c.index >= 4 ? 0 : nil
            // Build both terminal bodies before acquiring traffic authorities.
            var (world, model, line, _) = try LineRoutePreferenceTests.setup(traffic: false, patterns: pattern != nil)
            let route = LineRoutePreferenceTests.loop(world, pattern: pattern != nil)
            if (2...3).contains(c.index) {
                try world.removeTrackPlatform(route.platform.station, on: route.platform.edge, from: route.platform.start)
                XCTAssertNil(model.removeTrackPlatform(route.platform.station, on: route.platform.edge, from: route.platform.start))
            }
            let id = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(3), offset: 7168, cars: 1)
            XCTAssertNil(model.purchaseTrain(named: "T"))
            XCTAssertNil(model.placeTrain(id, at: .onEdge(SingleTrackMeet.forward(3), offset: 7168)))
            XCTAssertNil(model.setContinuation(id, along: [], stoppingAt: 7168))
            XCTAssertNil(model.setRate(id, 1024))
            try world.assignTrain(id, to: line, pattern: pattern); XCTAssertNil(model.assign(id, to: line, pattern: pattern))
            try world.setTrafficControl(c.index % 2 == 1)
            XCTAssertNil(model.setTrafficControl(c.index % 2 == 1))
            for step in 0..<24 {
                if step % 6 == 0 {
                    let count = 1 + Int(c.random.below(8))
                    let counts = TrainsInService(peak: count, offPeak: count, low: count)
                    try world.setLineTrainsInService(line, to: counts, pattern: pattern)
                    XCTAssertNil(model.setLineTrains(line, counts, pattern: pattern))
                } else if step % 7 == 0 {
                    let routes = step % 14 == 0 ? [] : [route]
                    try world.setLineRoutePreferences(line, to: routes, pattern: pattern)
                    XCTAssertNil(model.setLineRoutes(line, routes, pattern: pattern))
                } else if step % 5 == 0 {
                    let enabled = !world.isTrafficControlEnabled, before = world
                    var error: GameError?
                    do throws(GameError) { try world.setTrafficControl(enabled) } catch let caught { error = caught }
                    XCTAssertEqual(error, model.setTrafficControl(enabled))
                    if error != nil { XCTAssertEqual(before, world, "refused control change is atomic") }
                } else {
                    let seconds = 20 + c.random.below(91)
                    var single = world
                    try world.advance(ticks: seconds * 10)
                    XCTAssertNil(model.advance(ticks: Int(seconds * 10)))
                    for _ in 0..<seconds { try single.advance(ticks: 10) }
                    XCTAssertEqual(world, single, "capacity dispatch must be batch=seconds")
                }
                let differences = KernelDifferentialTests.differences(world, model)
                guard differences.isEmpty else { c.fail("step \(step): \(differences.joined(separator: "\n"))"); return }
                XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
                XCTAssertEqual(WorldInvariants.violations(in: world), [])
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let save = try encoder.encode(SavedGame(world: world))
                XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: save).world, world)
                digest.add(String(decoding: save, as: UTF8.self))
                steps += 1
            }
        }
        XCTAssertEqual(steps, 576)
        print("[digest] line.singleTrackCapacity \(digest.hex) (steps \(steps))")
    }
}
