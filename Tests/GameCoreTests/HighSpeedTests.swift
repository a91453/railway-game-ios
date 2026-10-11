import Foundation
@testable import GameCore
import XCTest

/// High-speed rail (ARCHITECTURE decision 168): the line kind, the fare, the
/// hinterland and the intercity trips. Every expectation is worked out by
/// hand from the rules.
final class HighSpeedTests: XCTestCase {
    // MARK: - The fare

    /// `Math.max(20, Math.round(km × .45))` dollars, the reference's legacy
    /// fare, for the straight-line distance in units of 1/64 m.
    func testTheFareIsTwentyDollarsOrFortyFiveCentsAKilometre() {
        func fare(_ units: Int64) -> Int64 { HighSpeed.fare(squaredDistance: units * units).amount }
        XCTAssertEqual(fare(0), 2_000, "the least")
        XCTAssertEqual(fare(640_000), 2_000, "10 km is $4.50")
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

    func testALineIsMadeHighSpeedByACommand() throws {
        var world = try makeWorld(width: 40_960, height: 4_096, balance: 100_000)
        for (index, name) in ["A", "B", "N"].enumerated() {
            try world.buildStation(named: name, at: PlanPoint(x: 2_048 + 8_192 * Int64(index), y: 2_048))
        }
        let line = try world.createLine(named: "Fast", stops: [a, b]).id
        let other = try world.createLine(named: "Slow", stops: [b, n]).id
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [false, false])
        XCTAssertEqual(world.highSpeedStations, [])

        try world.setLineHighSpeed(line, to: true)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [true, false])
        XCTAssertEqual(world.highSpeedStations, [a, b])
        XCTAssertTrue(world.isHighSpeedStation(b))
        XCTAssertFalse(world.isHighSpeedStation(n))
        let before = world
        try world.setLineHighSpeed(line, to: true)
        XCTAssertEqual(world, before, "again changes nothing")

        // The stops of a high-speed line are high-speed stations.
        try world.setLineStops(line, to: [a, n])
        XCTAssertEqual(world.highSpeedStations, [a, n])
        // A station on a second high-speed line stays one when the first goes.
        try world.setLineHighSpeed(other, to: true)
        XCTAssertEqual(world.highSpeedStations, [a, b, n])
        try world.removeLine(line)
        XCTAssertEqual(world.highSpeedStations, [b, n])

        try world.setLineHighSpeed(other, to: false)
        XCTAssertEqual(world.highSpeedStations, [])
        XCTAssertThrowsGameError(try world.setLineHighSpeed(LineID(rawValue: 99), to: true), .unknownLine(LineID(rawValue: 99)))
    }

    func testAFreightLineIsNotHighSpeedNorTheOtherWayRound() throws {
        var world = try makeWorld(width: 40_960, height: 4_096, balance: 100_000)
        for index in 0..<2 {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 2_048 + 8_192 * Int64(index), y: 2_048))
        }
        let freight = try world.createLine(named: "Goods", stops: [a, b]).id
        let fast = try world.createLine(named: "Fast", stops: [a, b]).id
        world.enableFreight()
        try world.setLineFreight(freight, to: true)
        try world.setLineHighSpeed(fast, to: true)

        let before = world
        XCTAssertThrowsGameError(try world.setLineHighSpeed(freight, to: true), .lineIsFreight(freight))
        XCTAssertThrowsGameError(try world.setLineFreight(fast, to: true), .lineIsHighSpeed(fast))
        XCTAssertEqual(world, before, "a refusal changes nothing")
        // Either goes back first, and the lines swap kinds.
        try world.setLineHighSpeed(fast, to: false)
        try world.setLineFreight(fast, to: true)
        try world.setLineFreight(freight, to: false)
        try world.setLineHighSpeed(freight, to: true)
        XCTAssertEqual(world.lines.map(\.isHighSpeed), [true, false])
        XCTAssertEqual(world.lines.map(\.isFreight), [false, true])
        // A freight line's stations are not high-speed stations.
        XCTAssertEqual(world.highSpeedStations, [a, b])
        try world.setLineHighSpeed(freight, to: false)
        XCTAssertEqual(world.highSpeedStations, [])
    }

    func testAHighSpeedLineIsCopiedAndSaved() throws {
        var world = try makeWorld(width: 40_960, height: 4_096, balance: 100_000)
        for index in 0..<2 {
            try world.buildStation(named: "S\(index)", at: PlanPoint(x: 2_048 + 8_192 * Int64(index), y: 2_048))
        }
        let line = try world.createLine(named: "Fast", stops: [a, b]).id
        // An ordinary world saves nothing of it: saves from before it read as they did.
        let plain = String(decoding: try JSONEncoder().encode(SavedGame(world: world)), as: UTF8.self)
        XCTAssertFalse(plain.contains("highSpeed"))
        XCTAssertFalse(plain.contains("hinterland"))

        try world.setLineHighSpeed(line, to: true)
        let copy = try world.duplicateLine(line, named: "Fast 2")
        XCTAssertTrue(copy.isHighSpeed)
        try world.setStationDemand(a, to: StationDemand(kind: .office, dailyTrips: 100, hinterland: 654_321))
        let train = try world.purchaseTrain(named: "N700").id
        try world.setTrainType(train, to: .highSpeed)

        let data = try JSONEncoder().encode(SavedGame(world: world))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""highSpeed":true"#))
        XCTAssertTrue(text.contains(#""hinterland":654321"#))
        XCTAssertTrue(text.contains(#""type":"HSR""#))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)

        // A line cannot be both, and a hinterland is bounded.
        let both = text.replacingOccurrences(of: #""highSpeed":true"#, with: #""highSpeed":true,"freight":true"#)
        XCTAssertThrowsError(try JSONDecoder().decode(SavedGame.self, from: Data(both.utf8)))
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

        try world.setLineHighSpeed(line, to: true)
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
        try world.setLineHighSpeed(line, to: false)
        XCTAssertEqual(world.stationDemand(of: a), StationDemand(kind: .residential, dailyTrips: 600))
        XCTAssertNil(world.stationDemand(of: b))
    }

    func testAFreeCompanysStationsKeepTheirRidershipAndHaveNoHinterland() throws {
        // The land sets the ridership of a managed company only (Phase 6b).
        var world = try landWorld()
        world.setEconomyMode(.free)
        try world.setLineHighSpeed(LineID(rawValue: 1), to: true)
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
    private func corridor(hinterlands: [Int64] = [2_000_000, 500_000, 1_000_000]) throws -> GameWorld {
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
        try world.assignTrain(train, to: line)
        try world.setLineHighSpeed(line, to: true)
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

    // Alpha(1,0) Beta(3,0) Gamma(5,0) on a(0,1)–g(6,1), one line, one train of
    // one car (see `EconomyAccountsTests`): three passengers waiting at Alpha
    // for Beta board at the first departure and pay as they board.
    private let tiles = TestLine(tiles: 7)
    private let main = LineID(rawValue: 1)

    private func boardingWorld() throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 8_192, height: 4_096), economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        try tiles.build(in: &world)
        try tiles.buildStation(named: "Alpha", beside: 1, at: 0, in: &world)
        try tiles.buildStation(named: "Beta", beside: 3, at: 0, in: &world)
        try tiles.buildStation(named: "Gamma", beside: 5, at: 0, in: &world)
        try world.createLine(named: "Main", stops: [a, b, StationID(rawValue: 3)])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: tiles.at(1, facingEast: true))
        try world.setTrainMovementRate(train.id, to: 1024)
        try world.assignTrain(train.id, to: main)
        world.setEconomyMode(.management)
        try world.setStationDemand(a, to: StationDemand(kind: .office, dailyTrips: 0))
        world.passengers[world.passengers.firstIndex { $0.station == a }!].release(3, to: b, along: PassengerTrip(line: main, direction: .outbound), at: .zero)
        return world
    }

    func testAHighSpeedTripPaysTheHighSpeedFare() throws {
        var ordinary = try boardingWorld()
        try ordinary.advance(ticks: 60)
        XCTAssertEqual(ordinary.accounts.pending.fareRevenue, 1_500, "three trips at the metro's $5")

        var fast = try boardingWorld()
        try fast.setLineHighSpeed(main, to: true)
        try fast.advance(ticks: 60)
        // 64 m apart is under any distance's worth: the least, $20 each.
        XCTAssertEqual(fast.accounts.pending.fareRevenue, 6_000)
        XCTAssertEqual(fast.accounts.pending.fareTrips, 3)
    }

    func testAHighSpeedFareIsNeverLessThanTheNetworks() throws {
        var world = try boardingWorld()
        let c = StationID(rawValue: 3)
        XCTAssertEqual(world.tripFare(from: a, to: c), 500)
        XCTAssertEqual(world.tripFare(from: a, to: c, highSpeed: true), 2_000)
        // A fare the company set above the high-speed one is the one asked.
        try world.setFareRules(.flat(3_000))
        XCTAssertEqual(world.tripFare(from: a, to: c), 3_000)
        XCTAssertEqual(world.tripFare(from: a, to: c, highSpeed: true), 3_000)
        XCTAssertNil(world.tripFare(from: a, to: a, highSpeed: true))
    }
}
