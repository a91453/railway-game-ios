import Foundation
@testable import GameCore
import XCTest

/// G1c (ARCHITECTURE decision 36): fares, the hourly and daily settlements
/// and the ledger, on the line of `BoardingTests`. Every expectation is
/// worked out by hand from the reference's legacy formulas, in cents.
final class EconomyAccountsTests: XCTestCase {
    // Alpha(1,0) Beta(3,0) Gamma(5,0) on a(0,1)–g(6,1); line 1 calls at all
    // three, one train of one car. Each leg is 2 links (2048 world units,
    // 32 m), which the line's standard performance plans at 16 s (Stage
    // W2c: √(2 × 2048 × 0.06) = 15.7). A trip sent out at T leaves Alpha
    // at T+0:42 (Stage W2b), is at Beta T+0:58–T+1:58, Gamma T+2:14–T+4:14,
    // Beta T+4:30–T+5:30 and back at Alpha at T+5:46, where its service
    // ends at T+6:28. The line's round trip is 424 s, planned as 8 minutes,
    // so trains leave at 0, 8, 16, 24, … A trip leaves four stops for
    // another (Alpha, Beta, Gamma, Beta) and ends at Alpha.
    private let alpha = StationID(rawValue: 1)
    private let beta = StationID(rawValue: 2)
    private let gamma = StationID(rawValue: 3)
    private let main = LineID(rawValue: 1)
    private let one = TrainID(rawValue: 1)

    private func makeWorld(managed: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts),
            clock: GameClock(speed: .normal)
        )
        try world.buildTrack(at: GridPosition(x: 0, y: 1), connections: .east)
        for x in 1...5 {
            try world.buildTrack(at: GridPosition(x: x, y: 1), connections: [.east, .west])
        }
        try world.buildTrack(at: GridPosition(x: 6, y: 1), connections: .west)
        try world.buildStation(named: "Alpha", at: GridPosition(x: 1, y: 0))
        try world.buildStation(named: "Beta", at: GridPosition(x: 3, y: 0))
        try world.buildStation(named: "Gamma", at: GridPosition(x: 5, y: 0))
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        try world.setLineServiceWindow(main, to: .allDay)
        try world.setLineTrainsInService(main, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1")
        try world.placeTrain(train.id, at: .atNode(GridPosition(x: 1, y: 1), heading: .east))
        try world.setTrainMovementRate(train.id, to: 1024)
        try world.assignTrain(train.id, to: main)
        if managed {
            world.setEconomyMode(.management)
        }
        return world
    }

    private func wait(_ world: inout GameWorld, _ count: Int64, at station: StationID, for destination: StationID) throws {
        if world.stationDemand(of: station) == nil {
            try world.setStationDemand(station, to: StationDemand(kind: .office, dailyTrips: 0))
        }
        let index = world.passengers.firstIndex { $0.station == station }!
        world.passengers[index].release(count, to: destination, along: PassengerTrip(line: main, direction: .outbound), at: .zero)
    }

    // MARK: - Free mode

    func testAFreeCompanyKeepsNoAccountsAndSavesAsBefore() throws {
        var world = try makeWorld(managed: false)
        try wait(&world, 3, at: alpha, for: beta)
        let balance = world.economy.balance
        try world.advance(ticks: 1_500)
        XCTAssertEqual(world.economy.balance, balance)
        XCTAssertEqual(world.accounts, CompanyAccounts())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        XCTAssertNil(json["accounts"])
    }

    // MARK: - Fares

    func testFaresAreFlatOrByStraightLineDistanceWithTheLegacyMinimum() throws {
        var world = try makeWorld()
        XCTAssertEqual(world.tripFare(from: alpha, to: gamma), 500, "the editor's flat 5")
        XCTAssertNil(world.tripFare(from: alpha, to: alpha))
        XCTAssertNil(world.tripFare(from: alpha, to: StationID(rawValue: 9)))
        try world.setFareRules(.distance(FareRules.standardBands))
        XCTAssertEqual(world.tripFare(from: alpha, to: gamma), 55, "64 m is in the first step")
        // Alpha to Gamma is 4 tiles: 64 m. A step ending exactly there does
        // not take the trip; one ending a metre later does.
        try world.setFareRules(.distance([
            FareBand(fromMeters: 0, toMeters: 64, fare: 30), FareBand(fromMeters: 64, toMeters: nil, fare: 90),
        ]))
        XCTAssertEqual(world.tripFare(from: alpha, to: gamma), 90)
        XCTAssertEqual(world.tripFare(from: alpha, to: beta), 30)
        try world.setFareRules(.flat(0))
        XCTAssertEqual(world.tripFare(from: alpha, to: beta), 500, "a fare of 0 is charged as 5")
    }

    func testFareRulesAreCheckedAsTheEngineDoes() throws {
        var world = try makeWorld()
        let before = world
        let band = { (from: Int64, to: Int64?, fare: Money) in FareBand(fromMeters: from, toMeters: to, fare: fare) }
        let invalid: [FareRules] = [
            .flat(-1), .flat(FareRules.maximumFare + 1), .distance([]),
            .distance([band(10, nil, 50)]), .distance([band(0, 100, 50)]),
            .distance([band(0, 100, 50), band(150, nil, 60)]), .distance([band(0, nil, 50), band(100, nil, 60)]),
            .distance([band(0, 100, -5), band(100, nil, 60)]), .distance([band(0, 100, 50), band(100, 50, 60), band(50, nil, 70)]),
            .distance(Array(repeating: band(0, 0, 1), count: 64) + [band(0, nil, 1)]),
            .distance([band(0, FareRules.maximumMeters + 1, 50), band(FareRules.maximumMeters + 1, nil, 60)]),
        ]
        for rules in invalid {
            XCTAssertThrowsGameError(try world.setFareRules(rules), .invalidFareRules)
        }
        XCTAssertEqual(world, before)
        try world.setFareRules(.distance([band(0, 0, 10), band(0, nil, 20)]))
        try world.setFareRules(.distance(Array(repeating: band(0, 0, 1), count: 63) + [band(0, nil, 1)]))
    }

    // MARK: - Settlements

    /// Hour 0: trips are sent out at 0, 8, …, 48 (four departures each) and
    /// at 56 (Alpha at 56:42, Beta at 57:58; Gamma at 60:14 is in the next
    /// hour): 30 departures, 30 × 2048 = 61440 world units. Operating
    /// round(75·30 + 42·61440/64000 + 18·3) = round(2344.32) = 2344;
    /// maintenance round(12·4096/64000 + 9·61440/64000 + 8·1) =
    /// round(17.408) = 17. Three passengers paid 5 each at Alpha at 0.
    func testAnHourIsSettledIntoOneRowAtTheTopOfTheNext() throws {
        var world = try makeWorld()
        try wait(&world, 3, at: alpha, for: beta)
        let start = world.economy.balance
        try world.advance(ticks: 60)
        XCTAssertEqual(world.accounts.pending.fareRevenue, 1_500)
        XCTAssertEqual(world.accounts.pending.fareTrips, 3)
        XCTAssertEqual(world.accounts.pending.departures, 30)
        XCTAssertEqual(world.accounts.pending.trainDistance, 30 * 2_048)
        XCTAssertEqual(world.accounts.entries, [])
        XCTAssertEqual(world.economy.balance, start, "nothing is settled within the hour")

        try world.advance(ticks: 1)
        XCTAssertEqual(world.accounts.entries, [LedgerEntry(
            kind: .hourlyNet, time: GameTime(minutes: 60), amount: 1_500 - 234_400 - 1_700,
            breakdown: [
                LedgerLine(item: .fareRevenue, amount: 1_500), LedgerLine(item: .operatingCost, amount: -234_400),
                LedgerLine(item: .maintenanceCost, amount: -1_700),
            ],
            crowding: CrowdingMetrics(crowdedStations: 0, fullTrains: 0, maxWaiting: 0, maxLoad: 0)
        )])
        XCTAssertEqual(world.economy.balance, start + Money(1_500 - 234_400 - 1_700))
        XCTAssertEqual(world.accounts.pending.departures, 1, "Gamma at 60:14 is in the next hour")
        XCTAssertEqual(world.accounts.pending.trainDistance, 2_048)
        XCTAssertEqual(world.accounts.pending.fareRevenue, .zero)
        XCTAssertEqual(world.accounts.openedAt, GameTime(minutes: 60))
    }

    /// The day's end: energy round(220·4096/64000 + 360·1) = round(374.08) =
    /// 374 (route 14, trains 360); staff 620·3 + 480·1 = 2340. Written at
    /// minute 1439, after the hour.
    func testADayEndsWithEnergyAndStaffAndTheBalanceMayGoBelowZero() throws {
        var world = try makeWorld()
        let start = world.economy.balance
        try world.advance(ticks: 1_441)
        let daily = world.accounts.entries.suffix(2)
        XCTAssertEqual(Array(daily), [
            LedgerEntry(
                kind: .dailyEnergy, time: GameTime(minutes: 1_439), amount: -37_400,
                breakdown: [LedgerLine(item: .routeEnergy, amount: -1_400), LedgerLine(item: .trainEnergy, amount: -36_000)]
            ),
            LedgerEntry(
                kind: .dailyStaff, time: GameTime(minutes: 1_439), amount: -234_000,
                breakdown: [LedgerLine(item: .stationStaff, amount: -186_000), LedgerLine(item: .trainStaff, amount: -48_000)]
            ),
        ])
        XCTAssertEqual(world.accounts.entries.dropLast(2).last?.time, GameTime(minutes: 1_440), "the hour is settled first")
        XCTAssertLessThan(world.economy.balance, .zero)
        XCTAssertEqual(world.economy.balance, start + world.accounts.days.reduce(Money.zero) { $0 + $1.fareRevenue - $1.totalCost })
        XCTAssertEqual(world.accounts.days.map(\.day), [0], "the hour settled at midnight is the ended day's")
        let report = world.financeReport(.day)
        XCTAssertEqual(report.current.index, 1)
        XCTAssertEqual(report.previous.energyCost, 37_400)
        XCTAssertEqual(report.previous.staffCost, 234_000)
    }

    /// A batch is the same as single steps, settlements included.
    func testSettlingInOneCallOrStepByStepIsTheSame() throws {
        var world = try makeWorld()
        try wait(&world, 30, at: alpha, for: gamma)
        try world.setStationDemand(beta, to: StationDemand(kind: .residential, dailyTrips: 50_000))
        try world.setStationDemand(gamma, to: StationDemand(kind: .office, dailyTrips: 50_000))
        var stepped = world
        try world.advance(ticks: 3_000)
        for _ in 0..<3_000 {
            try stepped.advance(ticks: 1)
        }
        XCTAssertEqual(world, stepped)
        XCTAssertGreaterThan(world.accounts.days.count, 1)
    }

    /// A world where nothing moves still settles every hour and day, though
    /// `advance` skips its idle minutes.
    func testAQuietWorldStillSettlesEveryHour() throws {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        world.setEconomyMode(.management)
        let balance = world.economy.balance
        try world.advance(ticks: 1_441)
        // 24 hours of 18 × 3 stations, then a day's staff of 620 × 3.
        XCTAssertEqual(world.accounts.entries.map(\.kind), Array(repeating: .hourlyNet, count: 24) + [.dailyStaff])
        XCTAssertEqual(world.economy.balance, balance - Money(24 * 5_400 + 186_000))
    }

    /// A station two lines call at is staffed and run for each of them, as
    /// the reference counts each line's stations (`metroEconomyFixedAssets`);
    /// a line calling twice at one station counts it once.
    func testAStationOfTwoLinesCountsForEach() throws {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        try world.createLine(named: "Main", stops: [alpha, beta, alpha])
        try world.createLine(named: "Branch", stops: [beta, gamma])
        world.setEconomyMode(.management)
        let balance = world.economy.balance
        try world.advance(ticks: 1_441)
        // Main has 2 stations and Branch 2: 4, so 24 hours of 18 × 4, then
        // a day's staff of 620 × 4.
        XCTAssertEqual(world.economy.balance, balance - Money(24 * 7_200 + 248_000))
    }

    /// The year report's previous year stays whole through the next year:
    /// two years of days are kept.
    func testTheYearReportKeepsTheWholePreviousYear() throws {
        var world = try GameWorld(
            width: 8, height: 4, economy: GameEconomy(balance: 1_000_000, costs: testCosts), clock: GameClock(speed: .normal)
        )
        for (name, x) in [("Alpha", 1), ("Beta", 3), ("Gamma", 5)] {
            try world.buildStation(named: name, at: GridPosition(x: x, y: 0))
        }
        try world.createLine(named: "Main", stops: [alpha, beta, gamma])
        world.setEconomyMode(.management)
        // To the last minute of day 719, the end of the second year.
        try world.advance(ticks: 720 * 1_440 - 1)
        XCTAssertEqual(world.accounts.days.count, 720)
        let year = world.financeReport(.year)
        XCTAssertEqual(year.current.index, 1)
        // A day: 24 hours of 18 × 3 stations, and staff of 620 × 3.
        XCTAssertEqual(year.previous.operatingCost, Money(360 * 24 * 5_400))
        XCTAssertEqual(year.previous.staffCost, Money(360 * 186_000))
        XCTAssertEqual(year.current.staffCost, Money(359 * 186_000), "day 719 has not ended")
        // Midnight's rows still belong to day 719; day 720's first hour is
        // settled at 01:00, and then day 0 leaves.
        try world.advance(ticks: 2)
        XCTAssertEqual(world.accounts.days.first?.day, 0)
        try world.advance(ticks: 60)
        XCTAssertEqual(world.accounts.days.count, 720)
        XCTAssertEqual(world.accounts.days.first?.day, 1)
        let next = world.financeReport(.year)
        XCTAssertEqual(next.current.index, 2)
        XCTAssertEqual(next.previous.staffCost, Money(360 * 186_000), "the second year, whole")
    }

    // MARK: - Demand

    func testFaresChangeDemandOnlyOnceTheyAreSet() throws {
        var world = try makeWorld()
        try world.setStationDemand(alpha, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(beta, to: StationDemand(kind: .office, dailyTrips: 1_000))
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 1_000, "never set: no effect")
        try world.setFareRules(.flat(75))
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 1_000, "at the baseline")
        try world.setFareRules(.flat(0))
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 1_000, "a free trip is taken as the baseline")
        try world.setFareRules(.flat(1))
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 1_078, "the cheapest fare: 1080 to 1076 at 13 thousandths of the baseline")
        try world.setFareRules(.flat(150))
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 487, "twice the baseline")
        world.setEconomyMode(.free)
        XCTAssertEqual(world.dailyDemand(from: alpha, to: beta), 1_000, "a free company")
    }

    func testTheDemandTableIsTheReferencesFormula() {
        func reference(_ ratio: Double) -> Double {
            var value: Double
            if ratio <= 1 {
                value = min(1.12, 1 + (1 - ratio) * 0.08)
            } else {
                value = exp(-0.72 * pow(ratio - 1, 1.35))
                if ratio >= 4 { value *= exp(-(ratio - 4) * 0.85) }
            }
            return max(0.01, min(1.12, value))
        }
        for (index, entry) in FareRules.demandTable.enumerated() {
            XCTAssertEqual(entry, Int64((reference(Double(index) / 20) * 1_000 + 0.5).rounded(.down)), "ratio \(Double(index) / 20)")
        }
        for cents in Int64(1)...1_000 {
            let ratio = Double(cents) / 75
            XCTAssertLessThanOrEqual(abs(Double(FareRules.demandFactor(fare: Money(cents))) - reference(ratio) * 1_000), 2.5, "fare \(cents)")
        }
        XCTAssertEqual(FareRules.demandFactor(fare: 0), 1_000, "taken as the baseline, as the reference's caller does")
        XCTAssertEqual(FareRules.demandFactor(fare: 100_000), 10)
    }

    // MARK: - Saving

    func testAccountsRoundTripAndBrokenOnesAreRejected() throws {
        var world = try makeWorld()
        try wait(&world, 3, at: alpha, for: beta)
        try world.setFareRules(.distance(FareRules.standardBands))
        try world.advance(ticks: 1_500)
        let data = try JSONEncoder().encode(world)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: data), world)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        func broken(_ change: (inout [String: Any]) -> Void) -> Data {
            var copy = json
            var accounts = copy["accounts"] as! [String: Any]
            change(&accounts)
            copy["accounts"] = accounts
            return try! JSONSerialization.data(withJSONObject: copy)
        }
        let cases: [String: Data] = [
            "unknown mode": broken { $0["mode"] = "sandbox" },
            "bad rules": broken { $0["fareRules"] = ["mode": "flat", "fare": -1] },
            "null rules": broken { $0["fareRules"] = NSNull() },
            "negative accrual": broken {
                var pending = $0["pending"] as! [String: Any]
                pending["departures"] = -1
                $0["pending"] = pending
            },
            "a row after now": broken {
                var entries = $0["entries"] as! [[String: Any]]
                entries[0]["time"] = 99_999
                $0["entries"] = entries
            },
            "days twice": broken {
                var days = $0["days"] as! [Any]
                days.append(days[0])
                $0["days"] = days
            },
            "fares not in whole dollars": broken {
                var pending = $0["pending"] as! [String: Any]
                pending["fareRevenue"] = 150
                $0["pending"] = pending
            },
            "departures beyond any hour": broken {
                var pending = $0["pending"] as! [String: Any]
                pending["departures"] = Int64(1) << 31
                $0["pending"] = pending
            },
            "a row that does not add up": broken {
                var entries = $0["entries"] as! [[String: Any]]
                entries[0]["amount"] = (entries[0]["amount"] as! Int64) + 100
                $0["entries"] = entries
            },
            "a row without its items": broken {
                var entries = $0["entries"] as! [[String: Any]]
                entries[0]["breakdown"] = [Any]()
                entries[0]["amount"] = 0
                $0["entries"] = entries
            },
            "crowding on a daily row": broken {
                var entries = $0["entries"] as! [[String: Any]]
                let index = entries.firstIndex { $0["kind"] as? String == "dailyStaff" }!
                entries[index]["crowding"] = ["crowdedStations": 0, "fullTrains": 0, "maxWaiting": 0, "maxLoad": 0]
                $0["entries"] = entries
            },
        ]
        var unbalanced = json
        var economy = unbalanced["economy"] as! [String: Any]
        economy["balance"] = Int64.min
        unbalanced["economy"] = economy
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: try JSONSerialization.data(withJSONObject: unbalanced)), "balance")
        for (name, data) in cases {
            XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: data), name)
        }
    }
}
