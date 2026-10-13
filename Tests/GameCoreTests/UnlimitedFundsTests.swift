import Foundation
@testable import GameCore
import XCTest

/// Unlimited funds (ARCHITECTURE decision 200, the reference's creative
/// mode, `创意模式`, "no funding limit"): in free play the company can build
/// and buy anything without paying, and is never refused for want of
/// money; its balance stays as it was. A managed company cannot have them,
/// and every world before them pays as it did.
///
/// Expected values are worked out by hand from the rules and written out,
/// never taken from a previous run.
final class UnlimitedFundsTests: XCTestCase {
    private let costs = ConstructionCosts(track: 100, station: 1_000, train: 5_000, car: 2_000)

    /// A free world of 16 × 4 tiles with `balance` and unlimited funds.
    private func world(balance: Money = 0, unlimited: Bool = true) throws -> GameWorld {
        var world = try GameWorld(
            bounds: WorldBounds(width: 16_384, height: 4_096), economy: GameEconomy(balance: balance, costs: costs),
            clock: GameClock(speed: .paused)
        )
        try world.setUnlimitedFunds(unlimited)
        return world
    }

    func testAnEconomyWithUnlimitedFundsPaysNothingAndIsNeverRefused() throws {
        var economy = GameEconomy(balance: -100)
        economy.unlimitedFunds = true
        XCTAssertTrue(economy.canAfford(Money(.max)))
        try economy.spend(1_000_000)
        economy.settle(-500)
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
        XCTAssertTrue(world.accounts.entries.isEmpty, "free play keeps no accounts")
    }

    func testTheSameWorldWithoutThemIsRefused() throws {
        var world = try world(unlimited: false)
        XCTAssertThrowsGameError(try world.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048)), .insufficientFunds(required: 1_000, available: 0))
        XCTAssertThrowsGameError(try world.purchaseTrain(named: "Blue"), .insufficientFunds(required: 5_000, available: 0))
    }

    func testOnlyFreePlayHasThem() throws {
        var managed = try world(unlimited: false)
        managed.setEconomyMode(.management)
        let before = managed
        XCTAssertThrowsGameError(try managed.setUnlimitedFunds(true), .unlimitedFundsNeedFreePlay)
        XCTAssertEqual(managed, before)
        // Turning them off is always allowed.
        try managed.setUnlimitedFunds(false)
        XCTAssertEqual(managed, before)
        // Becoming managed ends them, and the company pays again.
        var free = try world(balance: 3_000)
        free.setEconomyMode(.management)
        XCTAssertFalse(free.economy.unlimitedFunds)
        try free.buildStation(named: "Alpha", at: PlanPoint(x: 2_048, y: 2_048))
        XCTAssertEqual(free.economy.balance, 2_000)
    }

    func testTheWholeMapIsOpenedForNothing() throws {
        let length = MapExpansion.tileLength
        var world = try GameWorld(
            bounds: WorldBounds(width: 5 * length, height: 5 * length), economy: GameEconomy(balance: 0, costs: costs),
            clock: GameClock(speed: .paused)
        )
        try world.setUnlimitedFunds(true)
        try world.enableMapExpansion(owning: MapTile(row: 2, column: 2), townSeed: nil)
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
        // A managed world with unlimited funds is damaged.
        var managed = try world(balance: 5_000, unlimited: false)
        managed.setEconomyMode(.management)
        let damaged = String(decoding: try JSONEncoder().encode(managed), as: UTF8.self)
            .replacingOccurrences(of: #""economy":{"#, with: #""economy":{"unlimitedFunds":true,"#)
        XCTAssertNotEqual(damaged, String(decoding: try JSONEncoder().encode(managed), as: UTF8.self))
        XCTAssertThrowsError(try JSONDecoder().decode(GameWorld.self, from: Data(damaged.utf8)))
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
}
