import Foundation
@testable import GameCore
import XCTest

final class LineRoutePreferenceTests: XCTestCase {
    static func setup(traffic: Bool = true, patterns: Bool = false) throws -> (GameWorld, ReferenceWorld, LineID, TrainID) {
        var world = try SingleTrackMeet.world(), model = SingleTrackMeet.model()
        let line = try world.createLine(named: "Route", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        XCTAssertNil(model.createLine(named: "Route", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]))
        let pattern: Int? = patterns ? try world.addLinePattern(line, calling: [0, 2]) : nil
        if patterns { XCTAssertNil(model.addPattern(line, [0, 2])) }
        try world.setLineServiceWindow(line, to: .allDay); XCTAssertNil(model.setLineWindow(line, .allDay))
        let count = TrainsInService(peak: 1, offPeak: 1, low: 1)
        try world.setLineTrainsInService(line, to: count, pattern: pattern); XCTAssertNil(model.setLineTrains(line, count, pattern: pattern))
        let train = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(1), offset: 3_072)
        XCTAssertNil(model.purchaseTrain(named: "T")); XCTAssertNil(model.setCars(train, 2))
        XCTAssertNil(model.placeTrain(train, at: world.train(id: train)!.position!))
        XCTAssertNil(model.setContinuation(train, along: [], stoppingAt: 3_072)); XCTAssertNil(model.setRate(train, 1_024))
        try world.assignTrain(train, to: line, pattern: pattern); XCTAssertNil(model.assign(train, to: line, pattern: pattern))
        try world.setTrafficControl(traffic); XCTAssertNil(model.setTrafficControl(traffic))
        world.setSpeed(.x1); model.setSpeed(.x1)
        return (world, model, line, train)
    }

    static func loop(_ world: GameWorld, pattern: Bool = false) -> LineRoutePreference {
        let station = pattern ? SingleTrackMeet.east : SingleTrackMeet.middle
        let platform = world.trackPlatforms(of: station).first { $0.edge == .edge(pattern ? 3 : 5) }!
        return .init(from: 0, to: pattern ? 2 : 1,
                     tracks: (pattern ? [1, 4, 5, 6, 3] : [1, 4, 5]).map(SingleTrackMeet.forward), platform: platform)
    }

    /// New schema-32 short golden: two 2048-unit straight edges. The
    /// preferred far platform gives 3072 out and 3584 back, 20+21+240=281 s.
    func testNewShortGoldenPinsTheFartherPhysicalPlatform() throws {
        var world = try GameWorld(bounds: .init(width: 8_192, height: 8_192), economy: .init(balance: 1_000_000, costs: .init(track: 0, station: 0, train: 0, car: 0)), clock: .init(speed: .normal))
        for x: Int64 in [1_024, 3_072, 5_120] { try world.buildTrackNode(at: .init(x: x, y: 4_096)) }
        try world.buildTrackEdge(from: .node(1), to: .node(2))
        try world.buildTrackEdge(from: .node(2), to: .node(3))
        let west = try world.buildStation(named: "W", at: .init(x: 2_048, y: 6_144)).id
        let east = try world.buildStation(named: "E", at: .init(x: 4_096, y: 6_144)).id
        try world.addTrackPlatform(west, on: .edge(1), from: 512, to: 1_024)
        try world.addTrackPlatform(east, on: .edge(2), from: 512, to: 1_024)
        try world.addTrackPlatform(east, on: .edge(2), from: 1_536, to: 2_048)
        let line = try world.createLine(named: "Selected", stops: [west, east]).id
        let platform = world.trackPlatforms(of: east).last!
        let route = LineRoutePreference(from: 0, to: 1, tracks: [1, 2].map(SingleTrackMeet.forward), platform: platform)
        try world.setLineRoutePreferences(line, to: [route])
        let journey = try XCTUnwrap(world.lineJourney(line))
        XCTAssertEqual(journey.legs.map(\.path.distance), [3_072, 3_584])
        XCTAssertEqual(journey.legs.map(\.seconds), [20, 21])
        XCTAssertEqual(journey.roundTripSeconds, 281)
        XCTAssertEqual(journey.roundTripMinutes, 5)
        let committed = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("GoldenScenarios/line-route-preference.json")
        XCTAssertEqual(try GoldenScenario.decode(Data(contentsOf: committed)).differences(), [])
        if let destination = ProcessInfo.processInfo.environment["V4B_GOLDEN_NEW"] {
            let data = try Data(contentsOf: URL(fileURLWithPath: destination))
            var fresh = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(fresh["expectedFinalState"], "only complete a new fixture, never replace expectations")
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            fresh["expectedFinalState"] = try JSONSerialization.jsonObject(with: encoder.encode(WorldSummary(world)))
            let final = try JSONSerialization.data(withJSONObject: fresh, options: [.sortedKeys, .prettyPrinted])
            try final.write(to: URL(fileURLWithPath: destination))
        }
    }

    func testNewReplayIncludesSharedRoutesInItsChecksums() throws {
        let (start, _, line, _) = try Self.setup()
        let route = Self.loop(start)
        let commands: [KernelDifferentialTests.Operation] = [
            .setLineRoutes(line, [route], nil), .advance(610), .saveAndLoad,
            .advance(900), .setLineRoutes(line, [], nil), .saveAndLoad,
            .advance(600), .setLineRoutes(line, [route], nil), .advance(600),
        ]
        let checks = ReplayFixture.checksums(from: start, applying: commands, every: 1) { index, problem in XCTFail("\(index): \(problem)") }
        var changed = start
        try changed.setLineRoutePreferences(line, to: [route])
        XCTAssertNotEqual(ReplayState.checksum(of: start), ReplayState.checksum(of: changed))
        let fixture = try ReplayFixture(schemaVersion: 1, description: "Decision 61: shared physical path, actual dispatch, save and load, automatic fallback and rebinding.", source: "traffic.lineRoutes hand case", start: start, interval: 1, commands: commands.map(ReplayCommand.init), checksums: checks)
        XCTAssertEqual(fixture.commands.compactMap(\.operation).count, commands.count)
        if let destination = ProcessInfo.processInfo.environment["V4B_REPLAY_NEW"] {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            try encoder.encode(fixture).write(to: URL(fileURLWithPath: destination), options: .withoutOverwriting)
        }
    }

    func testAnExactPhysicalWalkAndPlatformOverrideTheShorterMain() throws {
        var (world, model, line, train) = try Self.setup()
        let preference = Self.loop(world)
        try world.setLineRoutePreferences(line, to: [preference]); XCTAssertNil(model.setLineRoutes(line, [preference]))
        let start = world.train(id: train)!.position!
        let path = try XCTUnwrap(world.preferredPath(from: start, preference: preference, length: 1_024))
        XCTAssertEqual(path.traversals, [4, 5].map(SingleTrackMeet.forward))
        XCTAssertEqual(path.end, 5_120)
        XCTAssertEqual(path.distance, 8_192 - 3_072 + world.network.edge(.edge(4))!.length + 5_120)
        XCTAssertGreaterThan(path.distance, world.path(from: start, toStation: SingleTrackMeet.middle, length: 1_024)!.distance)
        XCTAssertEqual(path, model.preferenceRoute(from: start, preference, length: 1_024))
        XCTAssertEqual(world.lineJourney(line)?.legs.first?.path, path)
        try world.advance(ticks: 610); XCTAssertNil(model.advance(ticks: 610))
        XCTAssertEqual(Array(world.train(id: train)!.movement.remainingEdges), path.traversals.map(\.edge))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    static func assignedOvertake() throws -> (GameWorld, ReferenceWorld, LineID, TrainID) {
        var world = try ScheduledTrafficTests.overtake()
        let slowLine = try world.createLine(named: "Slow", stops: [SingleTrackMeet.west, SingleTrackMeet.middle, SingleTrackMeet.east]).id
        let fastLine = try world.createLine(named: "Fast", stops: [SingleTrackMeet.west, world.stations[3].id]).id
        let preferred = Self.loop(world)
        try world.setLineRoutePreferences(slowLine, to: [preferred])
        // A saved running trip retains its own times when line settings
        // change. Bind synthetic running round trips through validated Codable.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        var lines = try XCTUnwrap(json["lines"] as? [[String: Any]])
        lines[0]["trains"] = [1]; lines[1]["trains"] = [2]; json["lines"] = lines
        var trains = try XCTUnwrap(json["trains"] as? [[String: Any]])
        for i in trains.indices {
            var calls = world.trains[i].timetable
            let terminal = calls.removeLast()
            calls.append(.init(station: terminal.station, arrival: terminal.arrival, departure: i == 0 ? terminal.departure : .init(seconds: 1_800), reverses: true))
            if i == 0 { calls.append(.init(station: SingleTrackMeet.middle, arrival: .init(seconds: 1_080), departure: .init(seconds: 1_080))) }
            calls.append(.init(station: SingleTrackMeet.west, arrival: .init(seconds: i == 0 ? 1_260 : 2_600), departure: .init(seconds: i == 0 ? 1_320 : 2_660), reverses: true))
            trains[i]["timetable"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(calls))
        }
        json["trains"] = trains
        world = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        var model = ScheduledTrafficTests.model(for: world)
        XCTAssertNil(model.createLine(named: "Slow", stops: world.lines[0].stops)); XCTAssertNil(model.createLine(named: "Fast", stops: world.lines[1].stops))
        model.lines[0].roster = [1]; model.lines[1].roster = [2]
        XCTAssertNil(model.setLineRoutes(slowLine, [preferred]))
        XCTAssertEqual(world.lines[1].id, fastLine)
        world.setSpeed(.x1); model.setSpeed(.x1)
        return (world, model, slowLine, .init(rawValue: 1))
    }

    func testAnAssignedLoopRemainsAnOvertakePlaceAndClearsTheExpress() throws {
        var (world, model, _, _) = try Self.assignedOvertake()
        XCTAssertTrue(world.scheduledTrafficWaits().contains { $0.train.rawValue == 1 && $0.kind == .overtake })
        XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
        // W→F: (8192−1024)+16384+8192+1536 = 33280 units,
        // departing at 180 and arriving at 600. For a=1500, b=2500,
        // L=v*T−v²*(1/a+1/b)/2 gives v≈79.69172 units/s. Edge 3
        // begins at distance 23552, reached at second 477.033…: the
        // first whole-second observation is 478, beyond the old 450 window.
        var seen = false, slowContinued = false
        var fastEnteredEastAt: Int64?
        for _ in 0..<61 {
            var single = world
            try world.advance(ticks: 100); XCTAssertNil(model.advance(ticks: 100))
            for _ in 0..<10 {
                try single.advance(ticks: 10)
                if fastEnteredEastAt == nil, case .onEdge(let track, _)? = single.trains[1].position, track.edge == .edge(3) {
                    fastEnteredEastAt = single.clock.now.seconds
                }
            }
            XCTAssertEqual(world, single)
            XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
            XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
            XCTAssertEqual(world.occupancyConflicts(), [])
            let slow = world.trains[0]
            if world.stationsStoppedAt(by: slow.id).contains(SingleTrackMeet.middle), case .onEdge(let track, _)? = slow.position {
                XCTAssertEqual(track.edge, .edge(5)); seen = true
            }
            if case .travellingToStop(2, _)? = slow.execution { slowContinued = true }
            if world.clock.now.seconds == 190 {
                XCTAssertEqual(world.trains[1].times?.run?.start.seconds, 180)
                XCTAssertEqual(world.trains[1].times?.run?.length, 33_280)
                XCTAssertEqual(world.trains[1].times?.run?.seconds, 420)
            }
        }
        XCTAssertTrue(seen)
        XCTAssertEqual(fastEnteredEastAt, 478)
        XCTAssertTrue(slowContinued)
        XCTAssertEqual(world.trains[1].execution, .waitingAtStop(1, cycle: 0))
        XCTAssertEqual(world.trains[1].times?.arrival.seconds, 600)
        XCTAssertTrue(world.stationsStoppedAt(by: world.trains[1].id).contains(world.stations[3].id))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world, world)
    }

    func testBlockedPreferenceFallsBackAtomicallyToV1() throws {
        var (world, model, line, train) = try Self.setup()
        let preference = Self.loop(world)
        try world.setLineRoutePreferences(line, to: [preference]); XCTAssertNil(model.setLineRoutes(line, [preference]))
        let blocker = try SingleTrackMeet.stand(&world, edge: SingleTrackMeet.forward(5), offset: 5_120)
        XCTAssertNil(model.purchaseTrain(named: "T")); XCTAssertNil(model.setCars(blocker, 2))
        XCTAssertNil(model.placeTrain(blocker, at: world.train(id: blocker)!.position!)); XCTAssertNil(model.setContinuation(blocker, along: [], stoppingAt: 5_120)); XCTAssertNil(model.setRate(blocker, 1_024))
        try world.advance(ticks: 610); XCTAssertNil(model.advance(ticks: 610))
        XCTAssertEqual(world.train(id: train)!.movement.remainingEdges.first, .edge(2))
        XCTAssertFalse(world.reservedResources(of: train).contains { if case .span(let s) = $0 { s.edge == .edge(5) } else { false } })
        XCTAssertEqual(world.occupancyConflicts(), [])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    func testMissingPlatformAndBrokenWalkFallBackWithoutLosingThePlan() throws {
        var (world, model, line, _) = try Self.setup()
        let preference = Self.loop(world)
        try world.setLineRoutePreferences(line, to: [preference]); XCTAssertNil(model.setLineRoutes(line, [preference]))
        try world.removeTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072)
        XCTAssertNil(model.removeTrackPlatform(SingleTrackMeet.middle, on: .edge(5), from: 3_072))
        XCTAssertNil(world.preferredPath(from: world.trains[0].position!, preference: preference, length: 1_024))
        XCTAssertEqual(world.lineJourney(line)?.legs.first?.path.traversals.first?.edge, .edge(2))
        XCTAssertEqual(world.lines[0].routePreferences, [preference])
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        let broken = LineRoutePreference(from: 0, to: 1, tracks: [SingleTrackMeet.forward(1), SingleTrackMeet.forward(5)], platform: preference.platform)
        try world.setLineRoutePreferences(line, to: [broken])
        XCTAssertNil(world.preferredPath(from: world.trains[0].position!, preference: broken, length: 1_024))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world, world)
    }

    func testPatternPreferencesAreSharedAndIsolatedFromTheBaseService() throws {
        var (world, model, line, _) = try Self.setup(patterns: true)
        let preference = Self.loop(world, pattern: true)
        try world.setLineRoutePreferences(line, to: [preference], pattern: 0); XCTAssertNil(model.setLineRoutes(line, [preference], pattern: 0))
        XCTAssertTrue(world.lines[0].routePreferences.isEmpty)
        XCTAssertEqual(world.lines[0].patterns[0].routePreferences, [preference])
        XCTAssertEqual(world.lineJourney(line, pattern: 0)?.legs.first?.path.traversals.map(\.edge), [4, 5, 6, 3].map(TrackEdgeID.edge))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    func testChoicesPreserveDirectionAndOldTripsDoNotAcquireNewLegs() throws {
        var (world, model, line, train) = try Self.setup()
        let choices = world.lineRouteChoices(line, from: 0, to: 1)
        XCTAssertEqual(choices.first?.tracks, [])
        XCTAssertTrue(choices.contains(Self.loop(world)))
        for choice in choices { XCTAssertEqual(choice.platform.station, SingleTrackMeet.middle) }
        XCTAssertEqual(world.lineRouteChoices(line, from: 0, to: 2), [])
        let good = Self.loop(world)
        try world.setLineRoutePreferences(line, to: [good]); XCTAssertNil(model.setLineRoutes(line, [good]))
        try world.advance(ticks: 10); XCTAssertNil(model.advance(ticks: 10))
        XCTAssertEqual(world.routePreference(for: world.train(id: train)!, from: 0, to: 1), good)
        try world.setLineRoutePreferences(line, to: []); XCTAssertNil(model.setLineRoutes(line, []))
        try world.setLineStops(line, to: [SingleTrackMeet.west, SingleTrackMeet.east]); XCTAssertNil(model.setLineStops(line, [SingleTrackMeet.west, SingleTrackMeet.east]))
        let newRoute = LineRoutePreference(from: 0, to: 1, platform: world.trackPlatforms(of: SingleTrackMeet.east)[0])
        try world.setLineRoutePreferences(line, to: [newRoute]); XCTAssertNil(model.setLineRoutes(line, [newRoute]))
        XCTAssertNil(world.routePreference(for: world.train(id: train)!, from: 0, to: 1))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
    }

    func testInvalidPreferencesAndExplicitNullAreRejectedAtomically() throws {
        var (world, model, line, _) = try Self.setup()
        let good = Self.loop(world)
        for routes in [[good, good], [.init(from: 0, to: 2, platform: good.platform)], [.init(from: -1, to: 1, platform: good.platform)]] {
            let before = world, oracle = model
            XCTAssertThrowsError(try world.setLineRoutePreferences(line, to: routes)) { XCTAssertEqual($0 as? GameError, .invalidLineRoutePreference) }
            XCTAssertEqual(model.setLineRoutes(line, routes), .invalidLineRoutePreference)
            XCTAssertEqual(before, world); XCTAssertEqual(oracle, model)
        }
        let data = try JSONEncoder().encode(world.lines[0])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["routePreferences"] = NSNull()
        XCTAssertThrowsError(try JSONDecoder().decode(ServiceLine.self, from: JSONSerialization.data(withJSONObject: json)))
        try world.setLineRoutePreferences(line, to: [good])
        let before = world
        XCTAssertThrowsError(try world.setLineStops(line, to: [SingleTrackMeet.west, SingleTrackMeet.east]))
        XCTAssertEqual(world, before)
    }

    func testTrafficOffAndVersionNineMigrationAndNewSaveRoundTrip() throws {
        var (world, model, line, _) = try Self.setup(traffic: false)
        var automatic = world
        let good = Self.loop(world)
        try world.setLineRoutePreferences(line, to: [good]); XCTAssertNil(model.setLineRoutes(line, [good]))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let save = try encoder.encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: save).world, world)
        XCTAssertGreaterThanOrEqual(SavedGame.currentVersion, 10, "physical preferences require v10 or later")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(SavedGame(world: automatic))) as? [String: Any]); old["saveVersion"] = 9
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: old)).world, automatic)
        try automatic.advance(ticks: 610)
        try world.advance(ticks: 610); XCTAssertNil(model.advance(ticks: 610))
        XCTAssertEqual(world.reservedResources(of: world.trains[0].id), [])
        XCTAssertEqual(world.train(id: world.trains[0].id)?.movement.remainingEdges.first, .edge(4))
        XCTAssertEqual(automatic.train(id: automatic.trains[0].id)?.movement.remainingEdges.first, .edge(2))
        XCTAssertEqual(KernelDifferentialTests.differences(world, model), [])
        if let destination = ProcessInfo.processInfo.environment["V4B_SAVE_NEW"] {
            let url = URL(fileURLWithPath: destination)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "only add a new fixture")
            try save.write(to: url, options: .withoutOverwriting)
        }
    }
}

final class LineRoutePreferencePropertyTests: XCTestCase {
    func testSharedPathsMatchTheIndependentModelAndEverySecond() throws {
        var tally = 0, digest = Digest()
        try runCampaign("traffic.lineRoutes", cases: 6) { c in
            var (world, model, line, _) = try c.index >= 4 ? LineRoutePreferenceTests.assignedOvertake() : LineRoutePreferenceTests.setup(traffic: c.index % 2 == 0, patterns: c.index >= 2)
            if c.index >= 4 { try world.setTrafficControl(c.index % 2 == 0); XCTAssertNil(model.setTrafficControl(c.index % 2 == 0)) }
            let pattern: Int? = (2...3).contains(c.index) ? 0 : nil
            let route = LineRoutePreferenceTests.loop(world, pattern: pattern != nil)
            for step in 0..<(c.index >= 4 ? 45 : 20) {
                let before = world
                if step % 5 == 0 {
                    let routes = step % 10 == 0 ? [route] : []
                    try world.setLineRoutePreferences(line, to: routes, pattern: pattern)
                    XCTAssertNil(model.setLineRoutes(line, routes, pattern: pattern))
                } else if step % 7 == 0 {
                    world = try JSONDecoder().decode(SavedGame.self, from: JSONEncoder().encode(SavedGame(world: world))).world
                    XCTAssertEqual(before, world)
                } else {
                    let seconds = 1 + c.random.below(25)
                    var single = world
                    try world.advance(ticks: seconds * 10); XCTAssertNil(model.advance(ticks: Int(seconds * 10)))
                    for _ in 0..<seconds { try single.advance(ticks: 10) }
                    XCTAssertEqual(single, world, "batch=seconds")
                }
                let differences = KernelDifferentialTests.differences(world, model)
                guard differences.isEmpty else { c.fail("step \(step): \(differences.joined(separator: "\n"))"); return }
                XCTAssertEqual(world.scheduledTrafficWaits(), model.scheduledPlan().waits)
                XCTAssertEqual(WorldInvariants.violations(in: world), [])
                tally += 1
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            digest.add(String(decoding: try encoder.encode(world), as: UTF8.self))
        }
        XCTAssertEqual(tally, 680)
        print("[digest] traffic.lineRoutes \(digest.hex) (steps \(tally))")
    }
}
