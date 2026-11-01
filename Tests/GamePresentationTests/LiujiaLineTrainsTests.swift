import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 490, the author's report on 95.1: the Neiwan Line bought, then
/// the Liujia Line during the day, its train 2 stood at Zhuzhong, empty,
/// while 2,448 riders waited there for it, the first for 337 minutes. A
/// line bought after 04:00 runs from the next day's first train (decision
/// 315), but riders set out to ride it from the moment it was bought and
/// waited for that train. Now nobody sets out for it before it runs.
@MainActor
final class LiujiaLineTrainsTests: XCTestCase {
    static let data = RealWorldData.load(file: RealWorldDataLoadTests.file)

    /// A new game of the app's real-world map at Zhuzhong, bought tile by
    /// tile and with the app's realistic rules, as the launcher begins
    /// it, with money enough.
    static func zhuzhong() throws -> GameSession {
        let junction = try BundledRealData.station("竹中", in: "tra_sched").coordinate
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: junction.latitude, longitudeDegrees: junction.longitude))
        var options = NewGameOptions()
        options.seed = 1
        var world = GameLauncher.newWorld(at: anchor, options: options, data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        world.setUnlimitedFunds(true)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    /// How many wait anywhere to ride line `id` next, and the longest
    /// any of them has waited, in minutes.
    private static func waiting(for id: LineID, in world: GameWorld) -> (count: Int64, minutes: Int64) {
        var count: Int64 = 0
        var minutes: Int64 = 0
        for record in world.passengers {
            for group in record.waiting where group.line == id {
                count += group.count
                minutes = max(minutes, (world.clock.now.seconds - group.since.seconds) / 60)
            }
        }
        return (count, minutes)
    }

    /// Runs `world` to the end of the purchase day, then through the next
    /// day: nobody waits for line `id` two hours the day it was bought;
    /// the next day every run of it goes and, when `ridden`, riders take
    /// it again.
    private static func checkNextDay(of id: LineID, _ world: inout GameWorld, ridden: Bool, _ label: String) throws {
        var longest: Int64 = 0
        while world.clock.now.seconds < GameTime.secondsPerDay {
            try world.advance(ticks: 1)
            longest = max(longest, waiting(for: id, in: world).minutes)
        }
        XCTAssertLessThan(longest, 120, "\(label): riders waited \(longest) minutes for the line the day it was bought")
        var waitingTomorrow: Int64 = 0
        while world.clock.now.seconds < 2 * GameTime.secondsPerDay + 60 {
            try world.advance(ticks: 1)
            waitingTomorrow = max(waitingTomorrow, waiting(for: id, in: world).count)
        }
        if ridden { XCTAssertGreaterThan(waitingTomorrow, 0, "\(label): nobody rode the line the next day") }
        let runs = try XCTUnwrap(world.line(id: id))
        let missed = zip(runs.runs, runs.runDays).filter { run, day in run.runs(onDay: 1) && (day ?? -1) < 1 }
        XCTAssertEqual(missed.count, 0, "\(label): runs not sent out the next day: \(missed.count) of \(runs.runs.count)")
    }

    /// Buys `order`, the first at midnight, the last at 09:00, and runs
    /// at 6000×: nobody waits two hours for the Liujia Line that day,
    /// and the next day every run of it goes.
    private func check(buying order: [String]) throws {
        let session = try Self.zhuzhong()
        for (index, network) in order.enumerated() {
            if index == order.count - 1 { session.advance(ticks: 9 * 60) }
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network }, "\(order): \(network) on sale")
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(order): \(network): \(session.message?.text ?? "")")
        }
        var world = session.world
        let id = try XCTUnwrap(world.acquisition(of: "tra:LIUJIA")?.line)
        world.setSpeed(.fast)
        try Self.checkNextDay(of: id, &world, ridden: true, "\(order)")
    }

    func testNobodyWaitsForTheLiujiaLineBoughtAfterTheNeiwanLine() throws {
        try check(buying: ["NEIWAN", "LIUJIA"])
    }

    func testNobodyWaitsForTheLiujiaLineBoughtBeforeTheNeiwanLine() throws {
        try check(buying: ["LIUJIA", "NEIWAN"])
    }

    func testNobodyWaitsForTheLiujiaLineBoughtAlone() throws {
        try check(buying: ["LIUJIA"])
    }

    /// Each branch line on sale, bought at 14:30 over the real ground
    /// under the app's realistic rules: nobody waits two hours for it that
    /// day, and the next day every run of it goes.
    func testNobodyWaitsForABranchLineBoughtDuringTheDay() throws {
        for network in ["PINGXI", "SHENAO", "JIJI", "NEIWAN", "LIUJIA", "SHALUN"] {
            let session = try RealLineAcquisitionTests.game(round: network, side: 1 << 21, heights: true)
            session.advance(ticks: 14 * 60 + 30)
            let line = try XCTUnwrap(session.buyableRealLines.first { $0.network == network }, network)
            XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), "\(network): \(session.message?.text ?? "")")
            var world = session.world
            let id = try XCTUnwrap(world.acquisition(of: line.id)?.line)
            try Self.checkNextDay(of: id, &world, ridden: false, network)
        }
    }
}
