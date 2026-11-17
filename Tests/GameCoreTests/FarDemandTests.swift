import Foundation
@testable import GameCore
import XCTest

/// Far demand (decision 828): a station beyond 20 km of an origin draws
/// less of its trips the farther it is. Every expectation is worked out by
/// hand from the rules.
final class FarDemandTests: XCTestCase {
    private let rovaniemi = StationID(rawValue: 1)
    private let muurola = StationID(rawValue: 2)
    private let kemijarvi = StationID(rawValue: 3)

    func testTheShareFallsWithTheSquareOfTheDistanceBeyondTwentyKilometres() {
        func share(_ metres: Int64) -> Int64 {
            let units = metres * WorldCoordinate.unitsPerMetre
            return DistanceDemand.farShare(squaredDistance: units * units)
        }
        XCTAssertEqual(share(0), 1_000)
        XCTAssertEqual(share(20_000), 1_000, "20 km")
        XCTAssertEqual(share(20_300), 971, "400 ÷ 412.09 = 0.9707")
        XCTAssertEqual(share(40_000), 250, "twice as far, a quarter")
        XCTAssertEqual(share(79_000), 64, "400 ÷ 6241 = 0.0641")
        XCTAssertEqual(share(80_000), 63, "62.5 rounds half up")
        XCTAssertEqual(share(10_000_000), 1, "never below 1")
    }

    /// Rovaniemi as decision 828 found it: 1,520 trips a day, Muurola
    /// 20.3 km south drawing 182, Kemijärvi 79 km east drawing 320, a line
    /// to each.
    private func lapland() throws -> GameWorld {
        let x: Int64 = 100_000, metre = WorldCoordinate.unitsPerMetre
        var world = try makeWorld(width: 5_300_000, height: 40_000, balance: 100_000)
        for east in [0, 20_300, 79_000] as [Int64] {
            try world.buildStation(named: "S\(east)", at: PlanPoint(x: x + east * metre, y: 20_000))
        }
        try world.setStationDemand(rovaniemi, to: StationDemand(kind: .residential, dailyTrips: 1_520))
        try world.setStationDemand(muurola, to: StationDemand(kind: .office, dailyTrips: 182))
        try world.setStationDemand(kemijarvi, to: StationDemand(kind: .office, dailyTrips: 320))
        try world.createLine(named: "Muurola", stops: [rovaniemi, muurola])
        return world
    }

    /// ROVANIEMI-PAIR: opening the far line took more than half of the
    /// near line's trips (Kemijärvi's 320 outdrew Muurola's 182 whatever
    /// the distance). With far demand on, Kemijärvi draws 320 × 64 against
    /// Muurola's 182 × 971: 1,520 × 176,722 ÷ 197,202 = 1,362.1 stay with
    /// Muurola, and the unit left over goes to Kemijärvi's 157.86.
    func testAFarLineTakesFewOfANearLinesTrips() throws {
        var world = try lapland()
        XCTAssertFalse(world.farDemand)
        XCTAssertEqual(world.dailyDemand(from: rovaniemi, to: muurola), 1_520)
        try world.createLine(named: "Kemijärvi", stops: [rovaniemi, kemijarvi])
        // Off, as before: 1,520 × 182 ÷ 502 = 551.07; 968.92 + 1.
        XCTAssertEqual([muurola, kemijarvi].map { world.dailyDemand(from: rovaniemi, to: $0) }, [551, 969])

        world.setFarDemand(true)
        XCTAssertTrue(world.farDemand)
        XCTAssertEqual([muurola, kemijarvi].map { world.dailyDemand(from: rovaniemi, to: $0) }, [1_362, 158])
        // The plan releases what the queries give.
        let plan = try XCTUnwrap(world.makePassengerPlan())
        for (index, flow) in plan.flows.enumerated() where flow.origin == rovaniemi {
            let day = plan.hourly[index * 24..<(index + 1) * 24].reduce(0, +)
            XCTAssertEqual(day, world.dailyDemand(from: rovaniemi, to: flow.destination))
        }
        // Muurola alone keeps all of them.
        var alone = try lapland()
        alone.setFarDemand(true)
        XCTAssertEqual(alone.dailyDemand(from: rovaniemi, to: muurola), 1_520)

        world.setFarDemand(false)
        XCTAssertEqual([muurola, kemijarvi].map { world.dailyDemand(from: rovaniemi, to: $0) }, [551, 969])
    }

    func testItSavesOnlyWhenOn() throws {
        var world = try lapland()
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(world), as: UTF8.self).contains("farDemand"))
        world.setFarDemand(true)
        let data = try JSONEncoder().encode(world)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""farDemand":true"#))
        let loaded = try JSONDecoder().decode(GameWorld.self, from: data)
        XCTAssertEqual(loaded, world)
        XCTAssertTrue(loaded.farDemand)
    }
}
