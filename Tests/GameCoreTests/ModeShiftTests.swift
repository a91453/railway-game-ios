import Foundation
@testable import GameCore
import XCTest

/// Riders switching to scooters and cars (decision 332): the road's
/// minutes, the share, where the step comes, the command and the save.
/// Every expectation is worked out by hand from the rules.
final class ModeShiftTests: XCTestCase {
    private static let track = TestLine(tiles: 140)
    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let near = StationID(rawValue: 3)

    // MARK: - The rule

    func testTheRoadTakesTheFasterOfAScooterAndACar() {
        // 2 km: 2,600 m of road, a scooter 5.2 → 5 + 4 = 9, a car 3.9 → 4 + 8 = 12.
        XCTAssertEqual(ModeShift.roadMinutes(metres: 2_000), 9)
        // 5 km: 6,500 m, a scooter 13 + 4 = 17, a car 9.75 → 10 + 8 = 18.
        XCTAssertEqual(ModeShift.roadMinutes(metres: 5_000), 17)
        // 10 km: 13,000 m, a scooter 26 + 4 = 30, a car 19.5 → 20 + 8 = 28.
        XCTAssertEqual(ModeShift.roadMinutes(metres: 10_000), 28)
        // 7,500 m: 9,750 m, a scooter 19.5 → 20 + 4 = 24, a car 14.6 → 15 + 8 = 23.
        XCTAssertEqual(ModeShift.roadMinutes(metres: 7_500), 23)
    }

    func testTheShareGrowsWithTheSlowdownUpToItsCap() throws {
        let simple = ModeShift.simple
        let realistic = try XCTUnwrap(ModeShift.realistic())
        XCTAssertEqual(realistic.cap, 720)
        // No slower: nobody switches.
        XCTAssertEqual(simple.share(railMinutes: 20, roadMinutes: 20), 0)
        XCTAssertEqual(realistic.share(railMinutes: 19, roadMinutes: 20), 0)
        // 21 / 20 = 1050‰: the simple rule half of 50, the realistic all.
        XCTAssertEqual(simple.share(railMinutes: 21, roadMinutes: 20), 25)
        XCTAssertEqual(realistic.share(railMinutes: 21, roadMinutes: 20), 50)
        // 13 / 10 = 1300‰.
        XCTAssertEqual(simple.share(railMinutes: 13, roadMinutes: 10), 150)
        XCTAssertEqual(realistic.share(railMinutes: 13, roadMinutes: 10), 300)
        // 18 / 11 = 1636‰, truncated: the simple rule stops at 200.
        XCTAssertEqual(simple.share(railMinutes: 18, roadMinutes: 11), 200)
        XCTAssertEqual(realistic.share(railMinutes: 18, roadMinutes: 11), 636)
        // Twice as slow: the realistic rule stops at its cap.
        XCTAssertEqual(realistic.share(railMinutes: 40, roadMinutes: 20), 720)
        XCTAssertEqual(try XCTUnwrap(ModeShift.realistic(cap: 370)).share(railMinutes: 40, roadMinutes: 20), 370)
        // Rounded half up.
        XCTAssertEqual(ModeShift.lost(1_000, share: 25), 25)
        XCTAssertEqual(ModeShift.lost(3, share: 250), 1, "0.75")
        XCTAssertEqual(ModeShift.lost(1, share: 499), 0)
        XCTAssertEqual(ModeShift.lost(1, share: 500), 1)
        XCTAssertEqual(ModeShift.lost(0, share: 720), 0)
    }

    // MARK: - In the demand

    /// A at column 1, B at column 135 (134 tiles, 137,216 units: 2,144 m
    /// in a straight line, 2,787 m of road, a scooter 6 + 4 = 10 minutes,
    /// a car 4 + 8 = 12) and Near at column 10, 147 m from A; one line
    /// A–Near–B with a train every `headway` minutes, network routing.
    private func corridor(headway: Int64) throws -> GameWorld {
        var world = try makeWorld(width: 143 * TestLine.tile, height: 4 * TestLine.tile, balance: 100_000_000)
        try Self.track.build(in: &world)
        try Self.track.buildStation(named: "A", beside: 1, at: 2, in: &world)
        try Self.track.buildStation(named: "B", beside: 135, at: 2, in: &world)
        try Self.track.buildStation(named: "Near", beside: 10, at: 2, in: &world)
        let line = try world.createLine(named: "Main", stops: [a, near, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: headway, offPeak: headway, low: headway))
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 10_000))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 10_000))
        try world.setStationDemand(near, to: StationDemand(kind: .office, dailyTrips: 10_000))
        world.setPassengerRoutingMode(.network)
        world.setSpeed(.normal)
        return world
    }

    private func railMinutes(_ world: GameWorld, to destination: StationID) throws -> Int64 {
        try XCTUnwrap(world.passengerRoutes(from: a, to: destination).map(\.totalMinutes).min()) + ModeShift.accessMinutes
    }

    /// A train every 10 minutes: A to B rides 4 minutes and waits 5, so
    /// 4 + 5 + 6 = 15 minutes against the scooter's 10, 1500‰. A's 10,000
    /// trips go 5,000 to each.
    func testAPairSlowerThanTheRoadLosesItsShare() throws {
        var world = try corridor(headway: 10)
        XCTAssertNil(world.modeShift)
        XCTAssertEqual(try railMinutes(world, to: b), 15)
        XCTAssertEqual(world.dailyDemands(from: a), [b: 5_000, near: 5_000])

        // Simple: half of 500‰ is 250‰, at most 200‰: 1,000 switch.
        try world.setModeShift(.simple)
        XCTAssertEqual(world.modeShiftShare(from: a, to: b, minutes: 9), 200)
        // Near, 147 m away, is left to decision 137.
        XCTAssertEqual(world.modeShiftShare(from: a, to: near, minutes: 60), 0)
        XCTAssertEqual(world.dailyDemands(from: a), [b: 4_000, near: 5_000])

        // Realistic: all 500‰: 2,500 switch.
        try world.setModeShift(ModeShift.realistic())
        XCTAssertEqual(world.dailyDemands(from: a), [b: 2_500, near: 5_000])

        try world.setModeShift(nil)
        XCTAssertEqual(world.dailyDemands(from: a), [b: 5_000, near: 5_000])
    }

    /// More trains bring them back: a train every 30 minutes waits 15, so
    /// 4 + 15 + 6 = 25 minutes, 2500‰: the realistic rule's cap, 720‰,
    /// and 3,600 of the 5,000 switch; every 10 minutes only 2,500 do.
    func testMoreTrainsBringThemBack() throws {
        var often = try corridor(headway: 10)
        var seldom = try corridor(headway: 30)
        try often.setModeShift(ModeShift.realistic())
        try seldom.setModeShift(ModeShift.realistic())
        XCTAssertEqual(try railMinutes(seldom, to: b), 25)
        XCTAssertEqual(seldom.dailyDemands(from: a)[b], 1_400)
        XCTAssertEqual(often.dailyDemands(from: a)[b], 2_500)
    }

    func testThePlanReleasesWhatTheQueriesGive() throws {
        var world = try corridor(headway: 10)
        try world.setModeShift(.simple)
        try world.advance(ticks: 1)
        let plan = try XCTUnwrap(world.passengerPlan.plan.flatMap { $0 })
        XCTAssertFalse(plan.flows.isEmpty)
        for (index, flow) in plan.flows.enumerated() {
            XCTAssertEqual(plan.hourly[(24 * index)..<(24 * index + 24)].reduce(0, +),
                           world.dailyDemand(from: flow.origin, to: flow.destination))
        }
    }

    func testBatchesStepsAndSavesAgree() throws {
        var batched = try corridor(headway: 10)
        try batched.setModeShift(ModeShift.realistic())
        var stepped = batched
        try batched.advance(ticks: 30)
        for _ in 0..<30 { try stepped.advance(ticks: 1) }
        XCTAssertEqual(batched, stepped)
        let loaded = try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(batched))
        XCTAssertEqual(loaded, batched)
    }

    // MARK: - The command

    func testACapOutsideZeroToAThousandIsRefused() throws {
        var world = try corridor(headway: 10)
        try world.setModeShift(.simple)
        XCTAssertNil(ModeShift.realistic(cap: 1_001))
        XCTAssertNil(ModeShift.realistic(cap: -1))
        let unchanged = world
        XCTAssertThrowsGameError(try world.setModeShift(ModeShift(rule: .realistic, cap: 1_001)), .invalidModeShift)
        XCTAssertEqual(world, unchanged)
        for cap in [-1, 1_001] {
            let bad = Data(#"{"rule":"realistic","cap":\#(cap)}"#.utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(ModeShift.self, from: bad))
        }
        XCTAssertEqual(try JSONDecoder().decode(ModeShift.self, from: Data(#"{"rule":"simple","cap":200}"#.utf8)), .simple)
    }

    // MARK: - Saves

    /// SaveFixtures/v70-mode-shift.json.
    func testVersionSeventyKeepsTheModeShift() throws {
        var world = try corridor(headway: 10)
        try world.setModeShift(ModeShift.realistic(cap: 548))
        try world.advance(ticks: 10)

        let url = SavedGameTests.fixtures.appendingPathComponent("v70-mode-shift.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["MODE_SHIFT_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 70)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.modeShift, ModeShift(rule: .realistic, cap: 548))
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 70,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        // Without the key nobody switches.
        var plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var saved = try XCTUnwrap(plain["world"] as? [String: Any])
        saved["modeShift"] = nil
        plain["world"] = saved
        let off = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain)).world
        XCTAssertNil(off.modeShift)
    }
}
