import Foundation
@testable import GameCore
import XCTest

/// High-speed rail (ARCHITECTURE decision 168): the high-speed line, the fare,
/// the hinterland and the intercity trips. Every expectation is worked out by
/// hand from the rules.
final class HighSpeedTests: XCTestCase {
    // MARK: - The fare

    /// `Math.round(km × .45)` dollars, the reference's legacy fare without
    /// its floor of 20, for the straight-line distance in units of 1/64 m.
    func testTheFareIsFortyFiveCentsAKilometre() {
        func fare(_ units: Int64) -> Int64 { HighSpeed.fare(squaredDistance: units * units).amount }
        XCTAssertEqual(fare(0), 0)
        XCTAssertEqual(fare(64_000), 0, "1 km is $0.45")
        XCTAssertEqual(fare(128_000), 100, "2 km is $0.90")
        XCTAssertEqual(fare(640_000), 500, "10 km is $4.50, which Math.round takes up")
        XCTAssertEqual(fare(2_842_000), 2_000, "44.4 km is $19.98")
        XCTAssertEqual(fare(2_880_000), 2_000, "45 km is $20.25")
        XCTAssertEqual(fare(3_200_000), 2_300, "50 km is $22.50, which Math.round takes up")
        XCTAssertEqual(fare(3_199_999), 2_200, "and a unit less is $22.499993")
        // The 340.037 km from Taipei to Zuoying along the track: $153, as the
        // reference's formula gives (and NT$1,490 is what the real ticket is).
        XCTAssertEqual(fare(21_762_368), 15_300)
        // The whole line, 352.6 km: $158.67.
        XCTAssertEqual(fare(22_566_400), 15_900)
    }

    // MARK: - Intercity trips

    func testNoIntercityTripsUpToTenKilometresAndAllFromEighty() {
        func share(_ units: Int64) -> Int64 { HighSpeed.share(squaredDistance: units * units) }
        XCTAssertEqual(share(0), 0)
        XCTAssertEqual(share(640_000), 0, "10 km")
        XCTAssertEqual(share(644_479), 0, "1000 × 4,479 / 4,480,000 rounds down")
        XCTAssertEqual(share(644_480), 1)
        XCTAssertEqual(share(2_880_000), 500, "45 km, half way")
        XCTAssertEqual(share(5_119_999), 999)
        XCTAssertEqual(share(5_120_000), 1_000, "80 km")
        XCTAssertEqual(share(30_000_000), 1_000)
        // The distance is the square root rounded down.
        XCTAssertEqual(HighSpeed.share(squaredDistance: 2_880_000 * 2_880_000 - 1), 499)
    }

    func testTwoHinterlandsMakeTheirGravityOfTrips() {
        // K for a million people and a million: 2,400 a day one way.
        XCTAssertEqual(HighSpeed.tripsPerMillionSquared, 2_400)
        XCTAssertEqual(HighSpeed.pairTrips(1_000_000, 1_000_000), HighSpeed.tripsPerMillionSquared)
        // 2.5 million and 1.1: 2.5 × 1.1 × 2,400 = 6,600.
        XCTAssertEqual(HighSpeed.pairTrips(2_500_000, 1_100_000), 6_600)
        XCTAssertEqual(HighSpeed.pairTrips(1_100_000, 2_500_000), 6_600, "the same both ways")
        XCTAssertEqual(HighSpeed.pairTrips(0, 5_000_000), 0)
        // Rounded down, a step at a time: 1,234,567 × 765,432 / 10^6 =
        // 944,977 (round down), × 2,400 / 10^6 = 2,267.
        XCTAssertEqual(HighSpeed.pairTrips(1_234_567, 765_432), 2_267)
        // The most a hinterland holds, twice, does not overflow: 100 × 100
        // × 2,400.
        XCTAssertEqual(HighSpeed.pairTrips(StationDemand.maximumHinterland, StationDemand.maximumHinterland), 24_000_000)
    }

    // MARK: - The line

    private let a = StationID(rawValue: 1)
    private let b = StationID(rawValue: 2)
    private let n = StationID(rawValue: 3)

    /// What makes a line high-speed is how it is planned: at `PERF_HSR`,
    /// whatever top speed. There is no switch.
    func testAHighSpeedPerformanceIsOneThatRunsAsPERFHSR() {
        XCTAssertTrue(TrainPerformance.highSpeed.isHighSpeed)
        let slower = TrainPerformance(
            acceleration: 1_400, braking: 1_500, topSpeed: 200, alternativeAcceleration: 2_000, alternativeBraking: 2_700,
            coast: TrainPerformance.Coast(deceleration: 450, speedRatio: 450)
        )
        XCTAssertTrue(slower.isHighSpeed, "a design speed changes only the top speed")
        let other = TrainPerformance(
            acceleration: 1_400, braking: 1_500, topSpeed: 300, alternativeAcceleration: 2_000, alternativeBraking: 2_700,
            coast: TrainPerformance.Coast(deceleration: 400, speedRatio: 450)
        )
        XCTAssertFalse(other.isHighSpeed, "it coasts differently")
        for performance in [TrainPerformance.standard, .metro, .local, .express, .semiExpress, .ordinary, .emu3000, .pushPull,
                            .tiltingTaroko, .tiltingPuyuma, .dieselExpress, .dieselRailcar, .forestRailway, .steam] {
            XCTAssertFalse(performance.isHighSpeed)
        }
    }

    func testALineIsHighSpeedWhenItIsPlannedAtHighSpeed() throws {
        var world = try makeWorld(width: 40_960, height: 4_096, balance: 100_000)
        for (index, name) in ["A", "B", "N"].enumerated() {
            try world.buildStation(named: name, at: PlanPoint(x: 2_048 + 8_192 * Int64(index), y: 2_048))
        }
        let line = try world.createLine(named: "Fast", stops: [a, b]).id
        let other = try world.createLine(named: "Slow", stops: [b, n]).id
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [false, false])
        XCTAssertEqual(world.highSpeedStations, [])

        try world.setLinePerformance(line, to: .highSpeed)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [true, false])
        XCTAssertEqual(world.highSpeedStations, [a, b])
        XCTAssertTrue(world.isHighSpeedStation(b))
        XCTAssertFalse(world.isHighSpeedStation(n))
        let before = world
        try world.setLinePerformance(line, to: .highSpeed)
        XCTAssertEqual(world, before, "again changes nothing")

        // The stops of a high-speed line are high-speed stations.
        try world.setLineStops(line, to: [a, n])
        XCTAssertEqual(world.highSpeedStations, [a, n])
        // A station on a second high-speed line stays one when the first goes.
        try world.setLinePerformance(other, to: .highSpeed)
        XCTAssertEqual(world.highSpeedStations, [a, b, n])
        try world.removeLine(line)
        XCTAssertEqual(world.highSpeedStations, [b, n])

        // Another performance, and it is an ordinary line again.
        try world.setLinePerformance(other, to: .express)
        XCTAssertEqual(world.highSpeedStations, [])
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [false])
    }

    func testAFreightLineIsNeverAHighSpeedLine() throws {
        var world = try landWorld()
        let line = LineID(rawValue: 1)
        world.enableFreight()
        try world.setLinePerformance(line, to: .highSpeed)
        XCTAssertEqual(world.stationDemand(of: a)?.hinterland, 1_860)

        // Freight is carried by the ton: the stations lose their hinterlands.
        try world.setLineFreight(line, to: true)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [false])
        XCTAssertEqual(world.highSpeedStations, [])
        XCTAssertEqual(world.stationDemand(of: a)?.hinterland, 0)
        XCTAssertFalse(world.isHighSpeedStation(a))
        // And a passenger line again, planned as it was, has them back.
        try world.setLineFreight(line, to: false)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [true])
        XCTAssertEqual(world.stationDemand(of: a)?.hinterland, 1_860)
    }

    func testAHighSpeedLineIsCopiedAndSaved() throws {
        var world = try makeWorld(width: 40_960, height: 4_096, balance: 100_000)
        for index in 0..<2 {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 2_048 + 8_192 * Int64(index), y: 2_048))
        }
        let line = try world.createLine(named: "Fast", stops: [a, b]).id
        // An ordinary world saves nothing of it: saves from before it read as they did.
        let plain = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertFalse(plain.contains("hinterland"))
        XCTAssertFalse(plain.contains("HSR"))

        try world.setLinePerformance(line, to: .highSpeed)
        let copy = try world.duplicateLine(line, named: "Fast 2")
        XCTAssertTrue(copy.isHighSpeed, "the copy is planned as the line is")
        try world.setStationDemand(a, to: StationDemand(kind: .office, dailyTrips: 100, hinterland: 654_321))
        let train = try world.purchaseTrain(named: "N700").id
        try world.setTrainType(train, to: .highSpeed)

        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(#""highSpeed""#), "a line is high-speed by its performance, which is all it saves")
        XCTAssertTrue(text.contains(#""hinterland":654321"#))
        XCTAssertTrue(text.contains(#""type":"HSR""#))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(loaded.lines.map(\.isHighSpeed), [true, true])

        // A hinterland is bounded.
        let huge = text.replacingOccurrences(of: #""hinterland":654321"#, with: #""hinterland":100000001"#)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(huge.utf8)))
        let negative = text.replacingOccurrences(of: #""hinterland":654321"#, with: #""hinterland":-1"#)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(negative.utf8)))
    }

    // MARK: - The save

    /// Version 43 (decision 168): the high-speed line A–N–B with the stations'
    /// hinterlands and a train of high-speed cars, managed, run five minutes
    /// so that passengers are waiting for it. It saves byte for byte and is
    /// the world this build makes.
    func testVersionFortyThreeKeepsAHighSpeedLine() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v43-high-speed.json")
        var made = try corridor()
        made.setEconomyMode(.management)
        made.setSpeed(.normal)
        try made.advance(ticks: 5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["HIGH_SPEED_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 43)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [true])
        XCTAssertEqual(world.highSpeedStations, [a, n, b])
        XCTAssertEqual(world.trains.map(\.type), [.highSpeed])
        XCTAssertEqual(world.trains.first?.capacity, 640, "eight cars of 80, not overloaded")
        XCTAssertEqual([a, n, b].map { world.stationDemand(of: $0)?.hinterland }, [2_000_000, 500_000, 1_000_000])
        XCTAssertTrue(world.passengers.contains { !$0.waiting.isEmpty }, "passengers wait for it")
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 43,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    // MARK: - The hinterland

    /// Station S1 in the middle of cell (50, 50) and S2 in that of
    /// (50, 200), 9.6 km apart; a cell's middle is `4,096 × index + 2,048`,
    /// the hinterland's radius 512,000 units (125 cells).
    ///
    /// - P (50, 50): 1,000 residents on S1; S2 is 150 cells away.
    /// - Q (50, 150): 100 residents and 1,100 jobs, 100 cells from S1 and 50
    ///   from S2: weights 1000 − 1000 × 100² / 125² = 360 and
    ///   1000 − 1000 × 50² / 125² = 840 of their 1,200, so S1 has 30 + 330
    ///   and S2 70 + 770.
    /// - R (50, 176): 500 residents, 126 cells from S1, outside (516,096 ≥
    ///   512,000), and 24 from S2.
    /// - U (50, 175): 400 residents, exactly 125 cells from S1, which is
    ///   not within the radius, and 25 from S2.
    /// - T (80, 50): 200 residents and 300 jobs, 30 cells south of S1.
    /// - V (180, 120): 700 residents, too far from both.
    private func landWorld() throws -> GameWorld {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        try world.setLand([
            LandCell(row: 50, column: 50, use: .residential, residents: 1_000, jobs: 0),
            LandCell(row: 50, column: 150, use: .office, residents: 100, jobs: 1_100),
            LandCell(row: 50, column: 175, use: .residential, residents: 400, jobs: 0),
            LandCell(row: 50, column: 176, use: .residential, residents: 500, jobs: 0),
            LandCell(row: 80, column: 50, use: .commercial, residents: 200, jobs: 300),
            LandCell(row: 180, column: 120, use: .residential, residents: 700, jobs: 0),
        ])
        world.setLandDemand(true)
        try world.buildStation(named: "S1", at: PlanPoint(x: 50 * 4_096 + 2_048, y: 50 * 4_096 + 2_048))
        try world.buildStation(named: "S2", at: PlanPoint(x: 200 * 4_096 + 2_048, y: 50 * 4_096 + 2_048))
        try world.createLine(named: "Fast", stops: [a, b])
        return world
    }

    func testAHighSpeedStationsHinterlandIsThePeopleRoundIt() throws {
        var world = try landWorld()
        let line = LineID(rawValue: 1)
        // An ordinary line: S1's 800 m catchment has P's 1,000 people (400
        // trips) and S2's nobody.
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 400))
        XCTAssertNil(world.stationDemand(of: b))

        try world.setLinePerformance(line, to: .highSpeed)
        // S1: P 1,000 + Q 30 + 330 + T 500 = 1,860. S2: Q 70 + 770 + R 500 +
        // U 400 = 1,740, with no trips of its own.
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 400, hinterland: 1_860))
        XCTAssertEqual(world.stationDemand(of: b), StationDemand(kind: .residential, dailyTrips: 0, hinterland: 1_740))

        // A closed station shares nothing: S1 has all of Q.
        try world.setStationOperationMode(b, to: .closed)
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 400, hinterland: 2_700))
        XCTAssertNil(world.stationDemand(of: b))
        try world.setStationOperationMode(b, to: .normalFlow)
        XCTAssertEqual(world.stationDemand(of: a)?.hinterland, 1_860)

        // Land that grows, or is set, is read again.
        try world.setLand([
            LandCell(row: 50, column: 50, use: .residential, residents: 1_500, jobs: 0),
            LandCell(row: 50, column: 150, use: .office, residents: 100, jobs: 1_100),
            LandCell(row: 50, column: 175, use: .residential, residents: 400, jobs: 0),
            LandCell(row: 50, column: 176, use: .residential, residents: 500, jobs: 0),
            LandCell(row: 80, column: 50, use: .commercial, residents: 200, jobs: 300),
            LandCell(row: 180, column: 120, use: .residential, residents: 700, jobs: 0),
        ])
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 600, hinterland: 2_360))

        // Not a high-speed line any more: the hinterlands go.
        try world.setLinePerformance(line, to: .standard)
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 600))
        XCTAssertNil(world.stationDemand(of: b))
    }

    /// A save from before this build has lines already planned at high speed
    /// (the line menu always had "High-speed rail"): they are high-speed lines
    /// when it reads them, and their stations have their hinterlands the next
    /// time the land demand is read again.
    func testASaveFromBeforeReadsALinePlannedAtHighSpeedAsOne() throws {
        var world = try landWorld()
        try world.setLinePerformance(LineID(rawValue: 1), to: .highSpeed)
        // Sorted keys, so that the key follows "dailyTrips" in every run.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(SavedGame(world: world)), as: UTF8.self)
        let older = text.replacingOccurrences(of: #","hinterland":1860"#, with: "").replacingOccurrences(of: #","hinterland":1740"#, with: "")
        XCTAssertFalse(older.contains("hinterland"), "what an older build saved")
        var loaded = try JSONDecoder().decode(SavedGame.self, from: Data(older.utf8)).world
        XCTAssertEqual(loaded.lines.map(\.isHighSpeed), [true])
        XCTAssertEqual(loaded.stationDemand(of: a)?.hinterland, 0)

        try loaded.setLand(loaded.land.cells)
        XCTAssertEqual(loaded.stationDemand(of: a)?.hinterland, 1_860)
        XCTAssertEqual(loaded.stationDemand(of: b)?.hinterland, 1_740)
    }

    func testAFreeCompanysStationsKeepTheirRidershipAndHaveNoHinterland() throws {
        // The land sets the ridership of a managed company only (Phase 6b).
        var world = try landWorld()
        world.setEconomyMode(.free)
        try world.setLinePerformance(LineID(rawValue: 1), to: .highSpeed)
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 400))
        XCTAssertNil(world.stationDemand(of: b))
    }

    // MARK: - Intercity trips in a network game

    private let corridorY: Int64 = 100_000

    /// A straight track with stations A, N and B 0, 5 and 61 km along it (A,
    /// B and N in the order they are numbered), one high-speed line A–N–B
    /// planned at `PERF_HSR` with a train of eight high-speed cars, in
    /// network routing. The hinterlands are 2,000,000, 500,000 and
    /// 1,000,000 people, none with trips of its own.
    private func corridor(hinterlands: [Int64] = [2_000_000, 500_000, 1_000_000], placesTrain: Bool = false) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 5_000_000, height: 200_000), economy: GameEconomy(balance: 1_000_000_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        // Along the track: A, N, B. Numbered A, B, N.
        let along: [(station: StationID, metres: Int64)] = [(a, 0), (n, 5_000), (b, 61_000)]
        let x = along.map { 100_000 + $0.metres * WorldCoordinate.unitsPerMetre }
        let nodes = try x.map { try world.buildTrackNode(at: WorldCoordinate(x: $0, y: corridorY)) }
        var edges: [TrackEdgeID] = []
        for index in 1..<nodes.count {
            edges.append(try world.buildTrackEdge(from: nodes[index - 1], to: nodes[index]))
        }
        let position: [StationID: Int64] = Dictionary(uniqueKeysWithValues: zip(along.map(\.station), x))
        for (id, name) in [(a, "A"), (b, "B"), (n, "N")] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: position[id]!, y: corridorY)).id
            XCTAssertEqual(station, id)
        }
        for (index, entry) in along.enumerated() {
            // Platforms of 128 m either side of the station, as long as the
            // train needs.
            if index >= 1 {
                let length = x[index] - x[index - 1]
                try world.addTrackPlatform(entry.station, on: edges[index - 1], from: length - 8_192, to: length)
            }
            if index + 1 < nodes.count {
                try world.addTrackPlatform(entry.station, on: edges[index], from: 0, to: 8_192)
            }
        }
        let line = try world.createLine(named: "Fast", stops: [a, n, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTargetHeadways(line, to: TargetHeadways(peak: 10, offPeak: 10, low: 10))
        try world.setLinePerformance(line, to: .highSpeed)
        let train = try world.purchaseTrain(named: "N700").id
        try world.setTrainType(train, to: .highSpeed)
        try world.setTrainCars(train, to: 8)
        try world.setTrainPerformance(train, to: .highSpeed)
        if placesTrain {
            // Its head at the end of A's platform, its body along the track behind.
            try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edges[0], direction: .forward), offset: 8_192))
            try world.setTrainContinuation(train, along: [], stoppingAt: 8_192)
            try world.setTrainMovementRate(train, to: 1024)
        }
        try world.assignTrain(train, to: line)
        world.setPassengerRoutingMode(.network)
        for (station, people) in zip([a, n, b], hinterlands) {
            try world.setStationDemand(station, to: StationDemand(kind: .residential, dailyTrips: 0, hinterland: people))
        }
        return world
    }

    /// The minutes of the fastest route from `origin` to `destination`.
    private func minutes(_ world: GameWorld, _ origin: StationID, _ destination: StationID) throws -> Int64 {
        let graph = PassengerRouteGraph(world: world)
        let choices = world.passengerRouteChoices(from: origin, to: destination, graph: graph)
        return try XCTUnwrap(choices.map(\.route.totalMinutes).min())
    }

    func testIntercityTripsRunBetweenHighSpeedStationsFarEnoughApart() throws {
        let world = try corridor()
        let ab = try minutes(world, a, b), ba = try minutes(world, b, a)
        let nb = try minutes(world, n, b), bn = try minutes(world, b, n)
        // 61 km at 300 km/h and the waiting and stops make some minutes;
        // the trips fall inversely beyond half an hour.
        XCTAssertGreaterThan(ab, 0, "\(ab) minutes")
        // A–B, 61 km: 2 million and 1 million people, 2 × 1 × 2,400 = 4,800,
        // 728 thousandths of them at that distance ((61 − 10) / 70 = 0.7286).
        XCTAssertEqual(world.dailyDemand(from: a, to: b), PassengerCrowding.decayed(3_494, minutes: ab))
        XCTAssertEqual(world.dailyDemand(from: b, to: a), PassengerCrowding.decayed(3_494, minutes: ba))
        // N–B, 56 km: 0.5 × 1 × 2,400 = 1,200, 657 thousandths of them.
        XCTAssertEqual(world.dailyDemand(from: n, to: b), PassengerCrowding.decayed(788, minutes: nb))
        XCTAssertEqual(world.dailyDemand(from: b, to: n), PassengerCrowding.decayed(788, minutes: bn))
        // A and N are 5 km apart: the metro's.
        XCTAssertEqual(world.dailyDemand(from: a, to: n), 0)
        XCTAssertEqual(world.dailyDemand(from: n, to: a), 0)
        XCTAssertEqual(world.dailyDemand(from: a, to: a), 0)
        XCTAssertEqual(world.dailyDemands(from: a), [b: world.dailyDemand(from: a, to: b)])
    }

    func testThePlanReleasesWhatTheQueriesGive() throws {
        let world = try corridor()
        let plan = try XCTUnwrap(world.makePassengerPlan())
        XCTAssertEqual(plan.flows.map { [$0.origin, $0.destination] }, [[a, b], [b, a], [b, n], [n, b]], "by origin and then destination; A and N too near")
        for (index, flow) in plan.flows.enumerated() {
            let day = plan.hourly[index * 24..<(index + 1) * 24].reduce(0, +)
            XCTAssertEqual(day, world.dailyDemand(from: flow.origin, to: flow.destination), "\(flow.origin) to \(flow.destination)")
            XCTAssertGreaterThan(day, 0)
        }
    }

    func testAnOrdinaryPairKeepsItsOwnTripsBesideTheIntercityOnes() throws {
        // A and N have 1,000 trips a day of their own each, and a hinterland.
        var world = try corridor()
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000, hinterland: 2_000_000))
        try world.setStationDemand(n, to: StationDemand(kind: .office, dailyTrips: 1_000, hinterland: 500_000))
        var plain = world
        try plain.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try plain.setStationDemand(n, to: StationDemand(kind: .office, dailyTrips: 1_000))
        try plain.setStationDemand(b, to: StationDemand(kind: .residential, dailyTrips: 0))

        // The pair A–N is 5 km apart, the metro's: its trips are the
        // ordinary ones, whatever the hinterlands.
        XCTAssertEqual(world.dailyDemand(from: a, to: n), plain.dailyDemand(from: a, to: n))
        XCTAssertGreaterThan(plain.dailyDemand(from: a, to: n), 0)
        // A–B: B draws none of A's ordinary trips (it has none of its own),
        // so only the intercity ones are there.
        XCTAssertEqual(plain.dailyDemand(from: a, to: b), 0)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), PassengerCrowding.decayed(3_494, minutes: try minutes(world, a, b)))
        XCTAssertEqual(world.dailyDemand(from: n, to: b), PassengerCrowding.decayed(788, minutes: try minutes(world, n, b)))
    }

    func testTheDaysFactorsApplyToIntercityTripsToo() throws {
        var world = try corridor()
        let plain = world.dailyDemand(from: a, to: b)
        // Day 0 is a Monday: 1.04 of the week's mean, of the pair's 3,494.
        world.setWeeklyDemand(true)
        let minutes = try minutes(world, a, b)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), PassengerCrowding.decayed(3_634, minutes: minutes))
        XCTAssertGreaterThan(world.dailyDemand(from: a, to: b), plain)
    }

    func testDirectTripsKeepToTheStationsOwnCatchment() throws {
        var world = try corridor()
        world.setPassengerRoutingMode(.direct)
        XCTAssertEqual(world.dailyDemand(from: a, to: b), 0, "intercity trips are the network game's")
        XCTAssertNil(world.makePassengerPlan())
    }

    // MARK: - Fares at boarding

    /// Three passengers waiting at A for B, 61 km along the track, and the
    /// first train standing at A: they pay as they board, at the first
    /// departure.
    private func boardingWorld(highSpeed: Bool) throws -> GameWorld {
        var world = try corridor(hinterlands: [0, 0, 0], placesTrain: true)
        if !highSpeed {
            // Planned as a Tze-Chiang express instead: the same train at the same stop.
            try world.setLinePerformance(LineID(rawValue: 1), to: .express)
        }
        world.setEconomyMode(.management)
        world.setSpeed(.normal)
        world.passengers[world.passengers.firstIndex { $0.station == a }!].release(
            3, to: b, along: PassengerTrip(line: LineID(rawValue: 1), direction: .outbound), at: .zero
        )
        return world
    }

    func testAHighSpeedTripPaysTheHighSpeedFare() throws {
        var ordinary = try boardingWorld(highSpeed: false)
        try ordinary.advance(ticks: 5)
        XCTAssertEqual(ordinary.accounts.pending.fareTrips, 3)
        XCTAssertEqual(ordinary.accounts.pending.fareRevenue, 1_500, "three trips at the metro's $5")

        var fast = try boardingWorld(highSpeed: true)
        try fast.advance(ticks: 5)
        // 61 km is 27.45: $27 each.
        XCTAssertEqual(fast.accounts.pending.fareTrips, 3)
        XCTAssertEqual(fast.accounts.pending.fareRevenue, 8_100)
    }

    func testAHighSpeedFareIsNeverLessThanTheNetworks() throws {
        var world = try corridor()
        // A and N are 5 km apart ($2.25 by the kilometres), A and B 61 km.
        XCTAssertEqual(world.tripFare(from: a, to: n), 500)
        XCTAssertEqual(world.tripFare(from: a, to: n, highSpeed: true), 500, "the network's $5 is more")
        XCTAssertEqual(world.tripFare(from: a, to: b), 500)
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 2_700)
        XCTAssertEqual(world.tripFare(from: n, to: b, highSpeed: true), 2_500, "56 km is $25.20")
        // A fare the company set above the kilometres' is the one asked.
        try world.setFareRules(.flat(3_000))
        XCTAssertEqual(world.tripFare(from: a, to: n, highSpeed: true), 3_000)
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 3_000)
        try world.setFareRules(.flat(2_000))
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 2_700)
        XCTAssertNil(world.tripFare(from: a, to: a, highSpeed: true))
    }

    // MARK: - The real fare table (decision 325)

    func testAPairOfTheFareTablePaysItsFare() throws {
        var world = try corridor()
        try world.setHighSpeedFares([HighSpeedFare(between: b, and: a, fare: 4_900), HighSpeedFare(between: a, and: n, fare: 400)])
        XCTAssertEqual(world.accounts.highSpeedFares, [HighSpeedFare(between: a, and: b, fare: 4_900), HighSpeedFare(between: a, and: n, fare: 400)])
        XCTAssertEqual(world.accounts.highSpeedFares.map(\.from), [a, a], "kept with the lower station first, in pair order")
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 4_900, "the table's, not the kilometres' $27")
        XCTAssertEqual(world.tripFare(from: b, to: a, highSpeed: true), 4_900, "either way")
        XCTAssertEqual(world.tripFare(from: a, to: n, highSpeed: true), 400, "even below the network's $5, as the real line asks")
        XCTAssertEqual(world.tripFare(from: n, to: b, highSpeed: true), 2_500, "a pair not in the table pays by the kilometre")
        XCTAssertEqual(world.tripFare(from: a, to: b), 500, "a trip that does not ride the high-speed line pays the network's")
        // The company's fare rules do not change the table's fares.
        try world.setFareRules(.flat(6_000))
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 4_900)
        XCTAssertEqual(world.tripFare(from: n, to: b, highSpeed: true), 6_000)
        // An empty table goes back to the kilometres.
        try world.setHighSpeedFares([])
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 6_000)
        try world.setFareRules(.flat(500))
        XCTAssertEqual(world.tripFare(from: a, to: b, highSpeed: true), 2_700)
    }

    func testTheFareTableIsChecked() throws {
        var world = try corridor()
        try world.setHighSpeedFares([HighSpeedFare(between: a, and: b, fare: 4_900)])
        let before = world
        let unknown = StationID(rawValue: 9)
        XCTAssertThrowsGameError(try world.setHighSpeedFares([HighSpeedFare(between: a, and: unknown, fare: 100)]), .unknownStation(unknown))
        XCTAssertThrowsGameError(try world.setHighSpeedFares([HighSpeedFare(between: a, and: a, fare: 100)]), .invalidFareRules)
        XCTAssertThrowsGameError(try world.setHighSpeedFares([HighSpeedFare(between: a, and: n, fare: 0)]), .invalidFareRules)
        XCTAssertThrowsGameError(try world.setHighSpeedFares([HighSpeedFare(between: a, and: n, fare: FareRules.maximumFare + 1)]), .invalidFareRules)
        XCTAssertThrowsGameError(
            try world.setHighSpeedFares([HighSpeedFare(between: a, and: n, fare: 100), HighSpeedFare(between: n, and: a, fare: 200)]), .invalidFareRules
        )
        XCTAssertEqual(world, before, "a table refused changes nothing")
    }

    func testABoarderPaysTheTablesFare() throws {
        var fast = try boardingWorld(highSpeed: true)
        // NT$1,490, Taipei to Zuoying, as the demo writes it: $149 each.
        try fast.setHighSpeedFares([HighSpeedFare(between: a, and: b, fare: 14_900)])
        try fast.advance(ticks: 5)
        XCTAssertEqual(fast.accounts.pending.fareTrips, 3)
        XCTAssertEqual(fast.accounts.pending.fareRevenue, 44_700)
    }

    /// Version 69 (decision 325): the high-speed line A–N–B, managed, with
    /// a fare table of A–B and A–N, run five minutes. It saves byte for
    /// byte and is the world this build makes; a table out of order, with a
    /// pair twice or a fare of 0 is refused, and a world without the key
    /// has none.
    func testVersionSixtyNineKeepsTheFareTable() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v69-high-speed-fares.json")
        var made = try corridor()
        made.setEconomyMode(.management)
        made.setSpeed(.normal)
        try made.setHighSpeedFares([HighSpeedFare(between: a, and: b, fare: 4_900), HighSpeedFare(between: a, and: n, fare: 400)])
        try made.advance(ticks: 5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["HIGH_SPEED_FARES_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 69)
        let world = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(world, made)
        XCTAssertEqual(world.tripFare(from: b, to: a, highSpeed: true), 4_900)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(try encoder.encode(SavedGame(world: world)), Data(text
            .replacingOccurrences(of: #""saveVersion" : 69,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))

        func accounts(_ change: (inout [String: Any]) -> Void) throws -> Data {
            var plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            var saved = try XCTUnwrap(plain["world"] as? [String: Any])
            var economy = try XCTUnwrap(saved["accounts"] as? [String: Any])
            change(&economy)
            saved["accounts"] = economy
            plain["world"] = saved
            return try JSONSerialization.data(withJSONObject: plain)
        }
        let none = try JSONDecoder().decode(SavedGame.self, from: accounts { $0["highSpeedFares"] = nil }).world
        XCTAssertEqual(none.accounts.highSpeedFares, [])
        XCTAssertEqual(none.tripFare(from: a, to: b, highSpeed: true), 2_700)
        let pair = { (from: Int, to: Int, fare: Int) -> [String: Any] in ["from": from, "to": to, "fare": fare] }
        for bad in [
            [pair(1, 3, 400), pair(1, 2, 4_900)],
            [pair(1, 2, 4_900), pair(1, 2, 400)],
            [pair(2, 1, 4_900)],
            [pair(1, 1, 4_900)],
            [pair(1, 2, 0)],
            // B3 of the #911–#944 review: a station never handed out.
            [pair(1, 99, 400)],
            [pair(0, 1, 400)],
        ] {
            XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: accounts { $0["highSpeedFares"] = bad }), "\(bad)")
        }
    }
}
