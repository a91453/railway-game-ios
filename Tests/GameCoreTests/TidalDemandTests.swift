import Foundation
@testable import GameCore
import XCTest

/// Tidal demand (ARCHITECTURE decision 319): the tidal hours, a station's
/// home share, the land's, and the release by each hour's middle. Every
/// expectation is worked out by hand from the rules.
final class TidalDemandTests: XCTestCase {
    private static let track = TestLine(tiles: 7)
    private let home = StationID(rawValue: 1)
    private let office = StationID(rawValue: 2)

    /// The tidal tables are their formulas, `(1 + 1.9·g(h; 8, 0.8))·(1 −
    /// 0.8·g(h; 18, 2))` and the other way round, normalised to a mean of
    /// 1000 and rounded.
    func testTheTidalHoursAreTheirFormulas() {
        func g(_ h: Double, _ mu: Double, _ sigma: Double) -> Double { exp(-0.5 * pow((h - mu) / sigma, 2)) }
        func table(_ f: (Double) -> Double) -> [Int64] {
            let values = (0..<24).map { f(Double($0)) }
            let mean = values.reduce(0, +) / 24
            return values.map { Int64(($0 / mean * 1_000).rounded()) }
        }
        XCTAssertEqual(StationDemandKind.tidalMorning, table { (1 + 1.9 * g($0, 8, 0.8)) * (1 - 0.8 * g($0, 18, 2)) })
        XCTAssertEqual(StationDemandKind.tidalEvening, table { (1 + 1.9 * g($0, 18, 2)) * (1 - 0.8 * g($0, 8, 0.8)) })
        for shape in [StationDemand.tidalDayShape, StationDemand.tidalWeekendShape] {
            XCTAssertEqual(shape.count, 24)
            // The night after 01:00 is all but empty.
            XCTAssertEqual(Array(shape[1...5]), [10, 10, 10, 10, 10])
        }
    }

    /// A home share blends the morning and the evening; without one a home
    /// and a workplace take the ends and any other kind its own hours; off
    /// the tide, the kind's hours.
    func testAHomeShareBlendsTheMorningAndTheEvening() {
        let morning = StationDemandKind.tidalMorning, evening = StationDemandKind.tidalEvening
        func demand(_ kind: StationDemandKind, _ home: Int64?) -> StationDemand {
            StationDemand(kind: kind, dailyTrips: 100, homeShare: home)
        }
        XCTAssertEqual(demand(.shopping, 1_000).departureShape(tidal: true), morning)
        XCTAssertEqual(demand(.shopping, 1_000).arrivalShape(tidal: true), evening)
        XCTAssertEqual(demand(.residential, 0).departureShape(tidal: true), evening)
        XCTAssertEqual(demand(.residential, 500).departureShape(tidal: true)[8], (2_923 * 500 + 150 * 500 + 500) / 1_000)
        XCTAssertEqual(demand(.residential, nil).departureShape(tidal: true), morning)
        XCTAssertEqual(demand(.office, nil).departureShape(tidal: true), evening)
        XCTAssertEqual(demand(.scenic, nil).departureShape(tidal: true), StationDemandKind.scenic.departureShape)
        XCTAssertEqual(demand(.shopping, 1_000).departureShape(tidal: false), StationDemandKind.shopping.departureShape)
    }

    /// With the tide a working day's trips from a home to an office leave
    /// in the morning, and all but none after 01:00; a day off keeps the kinds'
    /// hours with the tidal weekend's.
    func testTheTideSendsAHomesTripsOutInTheMorning() {
        let from = StationDemand(kind: .residential, dailyTrips: 0), to = StationDemand(kind: .office, dailyTrips: 0)
        let plain = GameWorld.hourly(10_000, from: from, to: to)
        let tidal = GameWorld.hourly(10_000, from: from, to: to, tidal: true)
        XCTAssertEqual(plain, GameWorld.hourly(10_000, from: .residential, to: .office))
        XCTAssertEqual(tidal.reduce(0, +), 10_000)
        XCTAssertGreaterThan(tidal[7] + tidal[8], 5_000)
        XCTAssertLessThan(plain[7] + plain[8], 3_000)
        XCTAssertTrue(tidal[1...5].allSatisfy { $0 <= 5 })
        // Back home: the evening.
        let back = GameWorld.hourly(10_000, from: to, to: from, tidal: true)
        XCTAssertGreaterThan(back[17] + back[18] + back[19], 5_000)
        XCTAssertLessThan(back[7] + back[8], 200)
        let off = GameWorld.hourly(10_000, from: from, to: to, weekend: true, tidal: true)
        let weights = (0..<24).map {
            StationDemand.tidalWeekendShape[$0] * StationDemandKind.morningPeak[$0] * StationDemandKind.morningPeak[$0]
        }
        XCTAssertEqual(off, GameWorld.apportion(10_000, by: weights))
    }

    /// A share's home share: its residents' share of its people, 40 % or
    /// less 0, 85 % or more 1000, rounded down between.
    func testAShareOfTheLandSaysHowMuchAHomeItIs() {
        XCTAssertNil(LandDemand.Share().homeShare)
        XCTAssertEqual(LandDemand.Share(residents: 1_000).homeShare, 1_000)
        XCTAssertEqual(LandDemand.Share(officeJobs: 1_000).homeShare, 0)
        // 600 of 1,000: (600,000,000 − 400,000,000) / 450,000 = 444.
        XCTAssertEqual(LandDemand.Share(residents: 600, officeJobs: 300, shopJobs: 100).homeShare, 444)
        XCTAssertEqual(LandDemand.Share(residents: 400, officeJobs: 600).homeShare, 0)
        XCTAssertEqual(LandDemand.Share(residents: 850, shopJobs: 150).homeShare, 1_000)
    }

    /// A managed world of the standard bounds with demand from land: Town
    /// on 600 residents and 400 office jobs.
    private func landWorld() throws -> GameWorld {
        var world = GameWorld(bounds: .standard, economy: GameEconomy(balance: 1_000_000_000, costs: testCosts), clock: GameClock(speed: .normal))
        world.setEconomyMode(.management)
        try world.setLand([
            LandCell(row: 128, column: 128, use: .residential, residents: 600, jobs: 0),
            LandCell(row: 128, column: 129, use: .office, residents: 0, jobs: 400),
        ])
        world.setLandDemand(true)
        try world.buildStation(named: "Town", at: PlanPoint(x: 524_288 + 2_048, y: 524_288 + 2_048))
        return world
    }

    /// The land gives its stations their home shares only with the tide,
    /// and takes them back when it is turned off.
    func testTheLandGivesItsStationsHomeSharesWithTheTide() throws {
        var world = try landWorld()
        XCTAssertEqual(world.stationDemand(of: home), StationDemand(kind: .residential, dailyTrips: 400))

        world.setTidalDemand(true)
        XCTAssertTrue(world.tidalDemand)
        XCTAssertEqual(world.stationDemand(of: home), StationDemand(kind: .residential, dailyTrips: 400, homeShare: 444))
        world.setTidalDemand(false)
        XCTAssertEqual(world.stationDemand(of: home), StationDemand(kind: .residential, dailyTrips: 400))
    }

    func testVersionSixtySevenKeepsTheTide() throws {
        var world = try landWorld()
        world.setTidalDemand(true)
        try world.advance(ticks: 10)

        let url = SavedGameTests.fixtures.appendingPathComponent("v67-tidal-demand.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["TIDAL_DEMAND_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: world)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 67)
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertTrue(loaded.tidalDemand)
        XCTAssertEqual(loaded.stationDemand(of: home)?.homeShare, 444)
        XCTAssertEqual(try encoder.encode(SavedGame(world: loaded)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 67,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
        // Without the key the tide is off.
        var plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var saved = try XCTUnwrap(plain["world"] as? [String: Any])
        saved["tidalDemand"] = nil
        plain["world"] = saved
        let off = try JSONDecoder().decode(SavedGame.self, from: JSONSerialization.data(withJSONObject: plain)).world
        XCTAssertFalse(off.tidalDemand)
    }

    /// A home share outside 0 to 1000 is refused, as a command and in a
    /// save; a demand without one saves no key.
    func testAHomeShareIsZeroToAThousand() throws {
        var world = try makeWorld(width: 8 * TestLine.tile, height: 4 * TestLine.tile)
        try Self.track.build(in: &world)
        let id = try Self.track.buildStation(named: "Home", beside: 1, at: 2, in: &world)
        XCTAssertThrowsGameError(try world.setStationDemand(id, to: StationDemand(kind: .residential, dailyTrips: 10, homeShare: 1_001)),
                                 .invalidStationDemand)
        let data = try JSONEncoder().encode(StationDemand(kind: .residential, dailyTrips: 10))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("homeShare"))
        for share in [-1, 1_001] {
            let bad = Data(#"{"kind":"residential","dailyTrips":10,"homeShare":\#(share)}"#.utf8)
            XCTAssertThrowsError(try JSONDecoder().decode(StationDemand.self, from: bad))
        }
        let good = Data(#"{"kind":"residential","dailyTrips":10,"homeShare":250}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(StationDemand.self, from: good).homeShare, 250)
    }

    /// With the tide each hour releases by its middle: about three
    /// quarters of its own trips and an eighth of each neighbour's, where
    /// the reference's release took half of the next hour's. A day still
    /// releases exactly the day's trips.
    func testEachHourReleasesByItsMiddleWithTheTide() throws {
        for tidal in [false, true] {
            var world = try twoStations()
            world.setTidalDemand(tidal)
            let table = world.hourlyDemand(from: home, to: office)
            var released: [Int64] = []
            var before: Int64 = 0
            for _ in 0..<48 {
                try world.advance(ticks: 60)
                let now = world.passengerLedger(of: home).released
                released.append(now - before)
                before = now
            }
            let day = Array(released[24...])
            XCTAssertEqual(day.reduce(0, +), table.reduce(0, +))
            for hour in 1..<23 {
                // Minute by minute: 30 + 29 + … + 1 sixtieths of the hour
                // before, and so on.
                let expected = tidal
                    ? (465 * table[hour - 1] + 2_700 * table[hour] + 435 * table[hour + 1]) / 3_600
                    : (1_830 * table[hour] + 1_770 * table[hour + 1]) / 3_600
                XCTAssertEqual(Double(day[hour]), Double(expected), accuracy: 2, "hour \(hour), tidal \(tidal)")
            }
        }
    }

    /// Home and Office on a short line, 2,400 and 2,400 trips a day, from
    /// midnight, open all day; no train, so the passengers only wait.
    private func twoStations() throws -> GameWorld {
        var world = try makeWorld(width: 8 * TestLine.tile, height: 4 * TestLine.tile)
        try Self.track.build(in: &world)
        let a = try Self.track.buildStation(named: "Home", beside: 1, at: 2, in: &world)
        let b = try Self.track.buildStation(named: "Office", beside: 5, at: 2, in: &world)
        let line = try world.createLine(named: "Main", stops: [a, b]).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setStationDemand(a, to: StationDemand(kind: .residential, dailyTrips: 2_400))
        try world.setStationDemand(b, to: StationDemand(kind: .office, dailyTrips: 2_400))
        world.setSpeed(.normal)
        return world
    }
}
