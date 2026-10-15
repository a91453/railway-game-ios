import Foundation
@testable import GameCore
import XCTest

/// Unlimited funds (ARCHITECTURE decision 200, after the reference's
/// creative mode, `创意模式`, "no funding limit"): a managed company that
/// builds and buys anything without paying and is never refused for want
/// of money; its balance stays as it was, while fares and costs are still
/// recorded. Every world before them pays as it did.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class UnlimitedFundsTests: XCTestCase {
    private let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: 2_000)

    /// A managed world of 16 × 4 tiles with `balance` and, unless told
    /// otherwise, unlimited funds.
    private func world(balance: Money = 0, unlimited: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 4_096), economy: GameEconomy(balance: balance, costs: costs),
            clock: GameClock(speed: .paused)
        )
        world.setEconomyMode(.management)
        world.setUnlimitedFunds(unlimited)
        return world
    }

    func testAnEconomyWithUnlimitedFundsPaysNothingAndIsNeverRefused() throws {
        var economy = GameEconomy(balance: -100)
        economy.unlimitedFunds = true
        XCTAssertTrue(economy.canAfford(Money(.max)))
        try economy.spend(1_000_000)
        economy.settle(-500)
        economy.settle(700)
        economy.earn(900)
        XCTAssertEqual(economy.balance, -100)
    }

    func testBuildingAndBuyingCostNothingAtAZeroBalance() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048, z: 0))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 2_048, z: 0))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048)).id
        try world.addTrackPlatform(station, on: edge, from: 512, to: 1_536)
        let train = try world.purchaseTrain(named: "Blue").id
        try world.setTrainCars(train, to: 6)
        XCTAssertEqual(world.economy.balance, .zero)
        XCTAssertEqual(world.train(id: train)?.cars, 6)
        // The books still record what each thing cost.
        XCTAssertEqual(world.accounts.assets.map(\.cost).reduce(.zero, +), Money(8 * 100 + 1_000 + 5_000 + 5 * 2_000))
    }

    /// What is settled is recorded as ever but leaves the balance alone:
    /// a loan's interest at midnight (the app offers no loan with
    /// unlimited funds; borrowed here, it brings nothing in either).
    func testSettlementsAreRecordedButNotPaid() throws {
        var world = try world(balance: 7)
        try world.borrow(CompanyAccounts.loanStep)
        XCTAssertEqual(world.economy.balance, 7, "nothing brought in")
        world.setSpeed(.normal)
        try world.advance(ticks: 1_441)
        XCTAssertTrue(world.accounts.entries.contains { $0.kind == .dailyInterest && $0.amount < .zero }, "interest recorded")
        XCTAssertEqual(world.economy.balance, 7)
    }

    func testTheSameWorldWithoutThemIsRefused() throws {
        var world = try world(unlimited: false)
        XCTAssertThrowsGameError(try world.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048)), .insufficientFunds(required: 1_000, available: 0))
        XCTAssertThrowsGameError(try world.purchaseTrain(named: "Blue"), .insufficientFunds(required: 5_000, available: 0))
    }

    func testTurnedOffTheCompanyPaysAgain() throws {
        var world = try world(balance: 3_000)
        world.setUnlimitedFunds(false)
        try world.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048))
        XCTAssertEqual(world.economy.balance, 2_000)
    }

    func testMapTilesCostNothing() throws {
        let length = MapExpansion.tileLength
        var world = try GameWorld(
            bounds: WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: 0, costs: costs),
            clock: GameClock(speed: .paused)
        )
        world.setUnlimitedFunds(true)
        try world.enableMapExpansion(owning: MapTile(row: 2, column: 2), townSeed: nil)
        // Free play needs no riders for a tile; a tile costs nothing.
        while let tile = world.mapTilesForSale().first {
            try world.buyMapTile(tile)
        }
        XCTAssertEqual(world.mapExpansion?.owned.count, 25)
        XCTAssertEqual(world.economy.balance, .zero)
    }

    func testASaveWithoutThemPaysAndOneWithThemKeepsThem() throws {
        let plain = try world(balance: 5_000, unlimited: false)
        let encoded = try JSONEncoder().encode(plain)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("unlimitedFunds"), "written only when on")
        let unlimited = try world()
        let text = String(decoding: try JSONEncoder().encode(unlimited), as: UTF8.self)
        XCTAssertTrue(text.contains(#""unlimitedFunds":true"#))
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: Data(text.utf8)), unlimited)
    }

    func testVersionFiftyOneKeepsUnlimitedFunds() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SaveFixtures/v51-unlimited-funds.json")
        var made = try world()
        let a = try made.buildTrackNode(at: WorldCoordinate(x: 1_024, y: 2_048, z: 0))
        let b = try made.buildTrackNode(at: WorldCoordinate(x: 9_216, y: 2_048, z: 0))
        let edge = try made.buildTrackEdge(from: a, to: b)
        let station = try made.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048)).id
        try made.addTrackPlatform(station, on: edge, from: 512, to: 1_536)
        let train = try made.purchaseTrain(named: "Blue").id
        try made.setTrainCars(train, to: 6)
        made.setSpeed(.normal)
        try made.advance(ticks: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if ProcessInfo.processInfo.environment["UNLIMITED_FUNDS_SAVE_NEW"] != nil {
            try encoder.encode(SavedGame(world: made)).write(to: url)
        }
        let data = try Data(contentsOf: url)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["saveVersion"] as? Int, 51)
        var loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, made)
        XCTAssertTrue(loaded.economy.unlimitedFunds)
        XCTAssertEqual(loaded.economy.balance, .zero)
        XCTAssertEqual(loaded.train(id: train)?.cars, 6)
        // It goes on building for nothing.
        try loaded.buildStation(named: "Beta", at: PlanPoint(x: 8_192, y: 2_048))
        XCTAssertEqual(loaded.economy.balance, .zero)
        XCTAssertEqual(try encoder.encode(SavedGame(world: JSONDecoder().decode(SavedGame.self, from: data).world)), Data(String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: #""saveVersion" : 51,"#, with: #""saveVersion" : \#(SavedGame.currentVersion),"#).utf8))
    }

    /// Decision 245: a pricing copy holds cash for anything, so a command of
    /// several steps runs through, and what it took is its whole price;
    /// the world refuses the second step with the cash the first left.
    /// With unlimited funds, nothing. The copy is the world but for its
    /// balance.
    func testAPricingCopyMeasuresTheWholePrice() throws {
        let start = try world(balance: 1_500, unlimited: false)
        let copy = start.pricingCopy()
        XCTAssertEqual(copy.economy.balance, GameWorld.pricingBalance)
        XCTAssertFalse(copy.economy.unlimitedFunds)
        var back = copy
        back.economy = start.economy
        XCTAssertEqual(back, start, "only the balance differs")

        func stationAndTrain(_ world: inout GameWorld) throws(GameError) {
            try world.buildStation(named: "A", at: PlanPoint(x: 1_024, y: 1_024))
            _ = try world.purchaseTrain(named: "T")
        }
        var real = start
        XCTAssertThrowsError(try stationAndTrain(&real)) { error in
            XCTAssertEqual(error as? GameError, .insufficientFunds(required: 5_000, available: 500), "the step's price, against what the first step left")
        }
        var priced = copy
        try stationAndTrain(&priced)
        XCTAssertEqual(GameWorld.pricingBalance - priced.economy.balance, Money(6_000), "the station and the train")

        var free = try world(balance: 1_500).pricingCopy()
        try stationAndTrain(&free)
        XCTAssertEqual(free.economy.balance, GameWorld.pricingBalance, "unlimited funds pay nothing")
    }
}
