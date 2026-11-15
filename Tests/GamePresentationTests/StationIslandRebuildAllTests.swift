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

    /// REVIEW-L22: the real-world demo lays 瑞芳, 猴硐 and 十分 on side
    /// platforms with no room past them for turnouts. The list shows them,
    /// each saying why it cannot be rebuilt, but the card does not open by
    /// itself over the demo with nothing to tick (it covered the toolbar a
    /// full lane UI test went on to tap).
    func testTheRealWorldDemosListDoesNotOpenByItself() throws {
        let railways = try BundledRealData.railways()
        let session = GameSession(world: RealWorldDemo.make(in: .traditionalChinese, railways: railways), language: .traditionalChinese)
        session.railways = railways
        XCTAssertTrue(session.hasRealIslandsToRebuild)
        XCTAssertFalse(session.islandRebuildList.isEmpty)
        XCTAssertTrue(session.islandRebuildList.allSatisfy { $0.cost == nil && $0.problem != nil })
        XCTAssertFalse(session.opensIslandRebuildListByItself)
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
