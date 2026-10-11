import GameCore
import GamePresentation
import XCTest

/// Buying the map (ARCHITECTURE decision 160) in the app: a new blank game
/// of 5 × 5 tiles owning the middle one, whose towns are the usual map's;
/// choosing a tile for sale on the map and buying it, as one edit undo
/// takes back.
@MainActor
final class MapExpansionSessionTests: XCTestCase {
    private let length = MapExpansion.tileLength

    func testANewBlankGameOwnsTheMiddleOfFiveByFiveTiles() throws {
        let world = GameWorld.newGame(eventSeed: 9, buysMap: true)
        XCTAssertEqual(world.bounds, GameWorld.buyingMapBounds)
        XCTAssertEqual(world.bounds.width, 5 * length)
        XCTAssertEqual(world.mapExpansion?.owned, [MapTile(row: 2, column: 2)])
        XCTAssertEqual(world.mapExpansion?.townSeed, 9)
        // The usual map's towns, moved to the middle tile.
        let usual = GameWorld.newGame(eventSeed: 9)
        XCTAssertEqual(world.land.cells.map(\.residents), usual.land.cells.map(\.residents))
        XCTAssertEqual(world.land.cells.first?.row, usual.land.cells.first.map { $0.row + 512 })
        XCTAssertEqual(world.land.cells.first?.column, usual.land.cells.first.map { $0.column + 512 })
        XCTAssertEqual(world.buildings.all.count, usual.buildings.all.count)
        XCTAssertTrue(world.outsideConnections)
        // The challenges, the tutorial and real-world maps keep one map.
        XCTAssertNil(GameWorld.newGame(eventSeed: 9).mapExpansion)
    }

    func testChoosingAndBuyingATile() throws {
        var world = GameWorld.newGame(balance: 1_000_000_000, eventSeed: 9, buysMap: true)
        let session = GameSession(world: world, language: .english)
        XCTAssertTrue(session.buysMap)
        XCTAssertEqual(session.mapExpansionOverlay?.owned, [PlanRect(minX: 2 * length, minY: 2 * length, maxX: 3 * length, maxY: 3 * length)])
        XCTAssertEqual(session.mapExpansionOverlay?.forSale, [])
        session.startChoosingMapTile()
        XCTAssertTrue(session.isChoosingMapTile)
        let overlay = try XCTUnwrap(session.mapExpansionOverlay)
        XCTAssertEqual(overlay.forSale.count, 4)
        XCTAssertEqual(overlay.forSale.first?.price, 500_000_000)
        XCTAssertEqual(overlay.forSale.first?.isUnlocked, false)
        XCTAssertEqual(overlay.region, WorldRegion(minX: Double(length), minY: Double(length), maxX: Double(4 * length), maxY: Double(4 * length)))

        // A tile not beside the land owned is not for sale.
        XCTAssertFalse(session.tapMapExpansion(at: PlanPoint(x: length / 2, y: length / 2)))
        XCTAssertNil(session.chosenMapTile)
        XCTAssertTrue(session.tapMapExpansion(at: PlanPoint(x: 3 * length + 10, y: 2 * length + 10)))
        XCTAssertEqual(session.chosenMapTile, MapTile(row: 2, column: 3))
        XCTAssertEqual(session.chosenMapTileCaption, "Unlocks at 100,000 riders a day · best so far 0")
        // Locked: refused, and the world is as it was.
        XCTAssertFalse(session.buyChosenMapTile())
        XCTAssertEqual(session.message?.text, "Carry 100,000 riders in a day to buy one more tile.")
        XCTAssertEqual(session.world.mapExpansion?.owned.count, 1)

        world.setEconomyMode(.free)
        let free = GameSession(world: world, language: .english)
        free.startChoosingMapTile()
        free.tapMapExpansion(at: PlanPoint(x: 3 * length + 10, y: 2 * length + 10))
        let balance = free.world.economy.balance
        let cells = free.world.land.cells.count
        XCTAssertTrue(free.buyChosenMapTile())
        XCTAssertEqual(free.message?.text, "Bought the tile for $ 5,000,000. Its towns wait for your railway.")
        XCTAssertFalse(free.isChoosingMapTile)
        XCTAssertEqual(free.world.economy.balance, balance - 500_000_000)
        XCTAssertGreaterThan(free.world.land.cells.count, cells)
        XCTAssertEqual(free.world.mapExpansion?.owned, [MapTile(row: 2, column: 2), MapTile(row: 2, column: 3)])
        free.undo()
        XCTAssertEqual(free.world.mapExpansion?.owned, [MapTile(row: 2, column: 2)])
        XCTAssertEqual(free.world.economy.balance, balance)
    }

    /// The small map shows the tiles owned.
    func testTheSmallMapShowsTheTilesOwned() {
        let world = GameWorld.newGame(eventSeed: 9, buysMap: true)
        let length = Double(length)
        XCTAssertEqual(MiniMap(world: world).region, WorldRegion(minX: 2 * length, minY: 2 * length, maxX: 3 * length, maxY: 3 * length))
        XCTAssertEqual(MiniMap(world: GameWorld.newGame(eventSeed: 9)).region, WorldRegion(bounds: GameWorld.newGameBounds))
    }

    func testTheEconomyPanelsLine() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .traditionalChinese)
        XCTAssertEqual(session.mapExpansionText, "地圖：已擁有 1 / 25 塊 · 下一塊 $ 5,000,000，每日運量 100,000 人次解鎖（目前最佳 0）")
        XCTAssertNil(GameSession(world: GameWorld.newGame(eventSeed: 9), language: .english).mapExpansionText)
    }

    func testChoosingAToolStopsChoosingATile() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 9, buysMap: true), language: .english)
        session.startChoosingMapTile()
        session.selectTool(.network)
        XCTAssertFalse(session.isChoosingMapTile)
    }

    func testBuildingOnLandNotOwnedSaysSo() {
        XCTAssertEqual(
            GameError.mapTileNotOwned(MapTile(row: 0, column: 0)).playerMessage(in: .traditionalChinese),
            "這塊地還不是你的，請先用「擴建地圖」買下這一塊。"
        )
    }
}
