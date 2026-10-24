@testable import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 400: a new blank map's roads, the station panel's
/// station road and the streets the maps draw on the roads.
final class StationRoadTests: XCTestCase {
    private func town() -> PlanPoint { Land.townCentres(seed: 1, in: GameWorld.newGameBounds)[0] }

    func testANewBlankMapHasEachTownsSquareAndARealMapNone() throws {
        let world = GameWorld.newGame()
        let roads = try XCTUnwrap(world.roads)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        XCTAssertFalse(towns.isEmpty)
        let side = Int64(Land.cellLength)
        for town in towns {
            XCTAssertTrue(roads.hasRoad(row: Int(town.y / side), column: Int(town.x / side)), "\(town)")
        }
        XCTAssertLessThanOrEqual(roads.cells.count, 9 * towns.count)
        XCTAssertNil(GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!).roads)
    }

    func testTheOfferSaysWhatTheRoadCostsAndBuildingItPays() throws {
        var world = GameWorld.newGame()
        let side = Int64(Land.cellLength), centre = town()
        let station = try world.buildStation(named: "East", at: PlanPoint(x: centre.x + 4 * side, y: centre.y))
        let quote = try world.stationRoadQuote(at: station.id)
        // Three cells to the seed square's edge, $50 a metre.
        XCTAssertEqual(quote.metres, 192)
        XCTAssertEqual(quote.price, Money(960_000))
        let offer = try XCTUnwrap(world.stationRoadOffer(of: station.id, in: .english))
        XCTAssertTrue(offer.canBuild)
        XCTAssertEqual(offer.quote, quote)
        XCTAssertEqual(offer.text, "Build Station Road · \(Money(quote.metres).displayText) m · \(quote.price.moneyText)")
        XCTAssertEqual(world.stationRoadOffer(of: station.id, in: .traditionalChinese)?.text,
                       "鋪站前路 · \(Money(quote.metres).displayText) 公尺 · \(quote.price.moneyText)")
        let balance = world.economy.balance
        try world.buildStationRoad(at: station.id)
        XCTAssertEqual(world.economy.balance, balance - quote.price)
        // A road reaches it now: nothing more to offer.
        XCTAssertNil(world.stationRoadOffer(of: station.id, in: .english))
    }

    func testAStationTooFarIsToldWhyAndAMapWithoutRoadsOffersNothing() throws {
        var world = GameWorld.newGame()
        let side = Int64(Land.cellLength), centre = town()
        let station = try world.buildStation(named: "Far", at: PlanPoint(x: centre.x + 16 * side, y: centre.y))
        let offer = try XCTUnwrap(world.stationRoadOffer(of: station.id, in: .english))
        XCTAssertFalse(offer.canBuild)
        XCTAssertEqual(offer.text, GameError.roadTooFar.playerMessage(in: .english))
        var real = GameWorld.newGame(anchor: GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170)!)
        let there = try real.buildStation(named: "Taipei", at: PlanPoint(x: side * 10, y: side * 10))
        XCTAssertNil(real.stationRoadOffer(of: there.id, in: .english))
    }

    func testEverySideOfARoadCellIsAStreet() {
        let road = Map3DScene.ChunkKey(column: 3, row: 5)
        let streets = Map3DSeededStreets(built: [:], roads: [road])
        let sides = [Map3DSeededStreets.Edge(horizontal: true, line: 5, along: 3), Map3DSeededStreets.Edge(horizontal: true, line: 6, along: 3),
                     Map3DSeededStreets.Edge(horizontal: false, line: 3, along: 5), Map3DSeededStreets.Edge(horizontal: false, line: 4, along: 5)]
        for side in sides { XCTAssertNotNil(streets.edges[side], "\(side)") }
        XCTAssertEqual(streets.edges.count, 4)
    }
}
