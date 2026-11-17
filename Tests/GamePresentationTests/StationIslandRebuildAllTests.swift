import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 770: the real island stations still on two side platforms,
/// listed on one card with their prices and rebuilt with one tap.
@MainActor
final class StationIslandRebuildAllTests: XCTestCase {
    /// A double track 2.5 km long west to east, with side-platform stations
    /// named `names` spread along it.
    private func stations(
        _ names: [String], balance: Money = 100_000_000, language: DisplayLanguage = .english
    ) throws -> GameSession {
        let world = try makeWorld(width: 163_840, height: 20_480, balance: balance, speed: .paused)
        let session = GameSession(world: world, language: language)
        session.selectTool(.network)
        session.networkBuildsDouble = true
        session.tapNetwork(at: PlanPoint(x: 2_048, y: 10_240), reach: 16)
        session.tapNetwork(at: PlanPoint(x: 161_792, y: 10_240), reach: 16)
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        session.setNetworkMode(.platform)
        session.platformCars = 4
        session.stationLayout = .doubleSide
        for (index, name) in names.enumerated() {
            let x = Int64(24_576 + index * 49_152)
            session.tapNetwork(at: PlanPoint(x: x, y: 10_240), reach: 64)
            session.stationName = name
            session.addNetworkPlatform()
            XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        }
        return session
    }

    private let realIslands: (Station) -> Bool = { ["猴硐", "八堵"].contains($0.name) }

    private func id(_ name: String, in session: GameSession) throws -> StationID {
        try XCTUnwrap(session.world.stations.first { $0.name == name }?.id)
    }

    func testOnlyRealIslandsOnSidePlatformsAreListed() throws {
        let session = try stations(["猴硐", "瑞芳", "八堵"])
        let list = session.islandRebuildList(isRealIsland: realIslands)
        XCTAssertEqual(list.map(\.name), ["猴硐", "八堵"])
        for candidate in list {
            XCTAssertNil(candidate.problem)
            let offer = try XCTUnwrap(session.stationIslandOffer(for: candidate.id))
            XCTAssertEqual(candidate.cost, offer.cost, "the list prices each as its panel does")
        }
        XCTAssertTrue(session.opensIslandRebuildListByItself(isRealIsland: realIslands))
        // On a map that is not real, no station is a real one.
        XCTAssertTrue(session.islandRebuildList.isEmpty)
        XCTAssertFalse(session.hasRealIslandsToRebuild)
        XCTAssertFalse(session.opensIslandRebuildListByItself)
    }

    /// REVIEW-L22, then decision 792's sequel: the real-world demo lays
    /// 瑞芳, 猴硐 and 十分 on side platforms, a loop 6 m from the line, as
    /// a branch line bought before decision 792 laid 十分. Their turnouts
    /// fall on the loop's curved ramp, where GameCore split the track some
    /// 0.2 m from where the plan put the turnout, and the rebuild found no
    /// stretch between them ("not enough track for the turnouts"). Now
    /// each is priced, and 十分 is rebuilt as an island.
    func testTheRealWorldDemosStationsAreRebuilt() throws {
        let railways = try BundledRealData.railways()
        let session = GameSession(world: RealWorldDemo.make(in: .traditionalChinese, railways: railways), language: .traditionalChinese)
        session.railways = railways
        XCTAssertTrue(session.hasRealIslandsToRebuild)
        let list = session.islandRebuildList
        XCTAssertEqual(Set(list.map(\.name)), ["瑞芳", "猴硐", "十分"])
        XCTAssertTrue(list.allSatisfy { $0.cost != nil && $0.problem == nil }, list.map { "\($0.name): \($0.problem ?? "")" }.joined(separator: "; "))
        let shifen = try id("十分", in: session)
        session.rebuildStationAsIsland(shifen)
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertNil(session.stationIslandOffer(for: shifen))
        XCTAssertFalse(session.islandRebuildList.contains { $0.id == shifen })
        // Its two tracks an island's 11 m apart, one platform each.
        let platforms = session.world.trackPlatforms(of: shifen)
        XCTAssertEqual(platforms.count, 2)
        let middles = platforms.map { session.middle(of: ($0.edge, $0.start, $0.end), in: session.world) }
        let dx = Double(middles[0].x - middles[1].x), dy = Double(middles[0].y - middles[1].y)
        let apart = (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
        XCTAssertGreaterThan(apart, 10)
        XCTAssertLessThan(apart, 14)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(session.world)), session.world)
    }

    func testRebuildingTheTickedOnes() throws {
        let session = try stations(["猴硐", "瑞芳", "八堵"])
        let list = session.islandRebuildList(isRealIsland: realIslands)
        let total = session.islandRebuildTotal(of: Set(list.map(\.id)), in: list)
        XCTAssertEqual(total.amount, list.compactMap(\.cost).reduce(0) { $0 + $1.amount })
        XCTAssertEqual(session.islandRebuildAllButtonText(count: 2, total: total), "Rebuild 2 stations (\(total.moneyText))")
        let before = session.world.economy.balance
        let revision = session.commandRevision
        session.rebuildStationsAsIsland(list.map(\.id))
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.hasPrefix("2 stations have an island platform now (猴硐, 八堵)") ?? false, session.message?.text ?? "")
        // Each its own command, as from its panel; the stations do not
        // touch, so the prices add up.
        XCTAssertEqual(session.commandRevision, revision + 2)
        XCTAssertEqual(Money(before.amount - session.world.economy.balance.amount), total)
        XCTAssertTrue(session.islandRebuildList(isRealIsland: realIslands).isEmpty)
        XCTAssertNil(session.stationIslandOffer(for: try id("猴硐", in: session)))
        XCTAssertNotNil(session.stationIslandOffer(for: try id("瑞芳", in: session)), "the station not ticked is left")
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(session.world)), session.world)
    }

    func testRunningOutOfCashSkipsTheRest() throws {
        let rich = try stations(["猴硐", "八堵"])
        let built = 100_000_000 - rich.world.economy.balance.amount
        let first = try XCTUnwrap(rich.islandRebuildList(isRealIsland: realIslands).first?.cost)
        // The same game with cash for the first rebuild only.
        let session = try stations(["猴硐", "八堵"], balance: Money(built + first.amount + first.amount / 4))
        let list = session.islandRebuildList(isRealIsland: realIslands)
        XCTAssertEqual(list.first?.cost, first)
        session.rebuildStationsAsIsland(list.map(\.id))
        XCTAssertEqual(session.message?.kind, .success, session.message?.text ?? "")
        XCTAssertTrue(session.message?.text.contains("Not rebuilt: 八堵") ?? false, session.message?.text ?? "")
        XCTAssertNil(session.stationIslandOffer(for: try id("猴硐", in: session)))
        XCTAssertNotNil(session.stationIslandOffer(for: try id("八堵", in: session)))
    }

    func testSaysChinese() throws {
        let session = try stations(["猴硐"], language: .traditionalChinese)
        let list = session.islandRebuildList(isRealIsland: realIslands)
        session.rebuildStationsAsIsland(list.map(\.id))
        XCTAssertTrue(session.message?.text.hasPrefix("1 站已改成島式月台（猴硐），花費") ?? false, session.message?.text ?? "")
    }
}
