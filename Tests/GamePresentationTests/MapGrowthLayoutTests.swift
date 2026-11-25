import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 969, the presentation's half (JAPAN-MAP-GROW): how a city's map
/// that grew lies over the Earth, and a game on it as it was growing with
/// it. The packs in the app have not grown, so they must lie as they did,
/// to the last digit; a pack that grew is made here from Fukuoka's, grown
/// to Kumamoto's extent.
@MainActor
final class MapGrowthLayoutTests: XCTestCase {
    private let fukuoka = MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48)
    private let kumamoto = MapPack.Extent(north: 33.72, south: 32.69, west: 130.29, east: 130.9)

    // MARK: - The packs that never grew

    /// The anchor and the world of each pack in the app, written out: a
    /// save on one is found by them (``OverseasGround/holds(_:)``).
    func testThePacksInTheAppLieAsTheyDid() throws {
        let expected: [OverseasMap: (latitude: Int64, longitude: Int64, width: Int64, height: Int64)] = [
            .hongKong: (223_543_496, 1_141_375_000, 4_008_773, 2_909_631),
            .rovaniemi: (665_512_574, 264_000_000, 6_804_050, 3_562_176),
            .fukuoka: (336_200_580, 1_303_850_000, 1_127_218, 1_424_891),
        ]
        for city in OverseasMap.allCases {
            let ground = try OverseasGround(city: city, pack: try XCTUnwrap(HongKongRailwaysTests.pack(city)))
            let extent = try XCTUnwrap(HongKongRailwaysTests.pack(city)).extent()
            XCTAssertEqual(ground.anchor, extent.anchor, "\(city)")
            XCTAssertEqual(ground.bounds, extent.bounds, "\(city)")
            XCTAssertEqual(ground.layout.earlier, [], "\(city)")
            XCTAssertNil(ground.layout.anchorBounds, "\(city)")
            let pinned = try XCTUnwrap(expected[city], "\(city)")
            XCTAssertEqual(ground.anchor, GeoAnchor(latitude: pinned.latitude, longitude: pinned.longitude), "\(city)")
            XCTAssertEqual(ground.bounds, try WorldBounds(width: pinned.width, height: pinned.height), "\(city)")
        }
    }

    // MARK: - A map that grew

    func testAGrownMapKeepsTheFirstAnchorAndReachesTheLaterCorner() throws {
        let layout = try XCTUnwrap(MapPack.Layout(extent: kumamoto, earlier: [fukuoka]))
        let first = try XCTUnwrap(MapPack.Layout(extent: fukuoka, earlier: []))
        XCTAssertEqual(layout.anchor, first.anchor, "where the first games were laid")
        XCTAssertEqual(layout.earlier, [first.bounds])
        XCTAssertEqual(layout.anchorBounds, first.bounds)
        // 4 tiles by 7 (decision 969's handoff: some 56.5 by 114.1 km).
        XCTAssertEqual(layout.bounds.width / MapExpansion.tileLength, 3)
        XCTAssertEqual(layout.bounds.height / MapExpansion.tileLength, 6)
        XCTAssertEqual(Double(layout.bounds.width) / 64 / 1_000, 56.5, accuracy: 0.5)
        XCTAssertEqual(Double(layout.bounds.height) / 64 / 1_000, 114.1, accuracy: 0.5)
        // The world's corners are the extents' corners.
        let frame = RealWorldFrame(anchor: layout.anchor, bounds: try XCTUnwrap(layout.anchorBounds))
        let northWest = frame.coordinate(worldX: 0, worldY: 0)
        let southEast = frame.coordinate(worldX: Double(layout.bounds.width), worldY: Double(layout.bounds.height))
        XCTAssertEqual(northWest.latitude, 33.72, accuracy: 1e-6)
        XCTAssertEqual(northWest.longitude, 130.29, accuracy: 1e-6)
        XCTAssertEqual(southEast.latitude, 32.69, accuracy: 1e-6)
        XCTAssertEqual(southEast.longitude, 130.9, accuracy: 1e-6)
        // Fukuoka's 17.6 by 22.2 km are 2 tiles by 2.
        XCTAssertEqual(layout.startTiles, [MapTile(row: 0, column: 0), MapTile(row: 0, column: 1), MapTile(row: 1, column: 0), MapTile(row: 1, column: 1)])
    }

    func testAMapThatGrewTwiceKeepsItsFirstAnchorAndMiddleWorld() throws {
        let middle = MapPack.Extent(north: 33.72, south: 33.2, west: 130.29, east: 130.6)
        let layout = try XCTUnwrap(MapPack.Layout(extent: kumamoto, earlier: [fukuoka, middle]))
        let once = try XCTUnwrap(MapPack.Layout(extent: middle, earlier: [fukuoka]))
        let twice = try XCTUnwrap(MapPack.Layout(extent: kumamoto, earlier: [fukuoka]))
        XCTAssertEqual(layout.anchor, twice.anchor)
        XCTAssertEqual(layout.bounds, twice.bounds)
        XCTAssertEqual(layout.earlier, [try XCTUnwrap(once.anchorBounds), once.bounds])
    }

    func testTheMapHoldsAGameAsItWasAndAsItIs() throws {
        let layout = try XCTUnwrap(MapPack.Layout(extent: kumamoto, earlier: [fukuoka]))
        let start = try XCTUnwrap(layout.anchorBounds)
        var old = GameWorld.newGame(anchor: layout.anchor, bounds: start, land: [])
        XCTAssertTrue(layout.holds(old), "a game laid over the first extent")
        try old.growMap(to: layout.bounds)
        XCTAssertTrue(layout.holds(old), "and grown to the map as it is")
        // The whole map round its own middle is another map.
        let elsewhere = GameWorld.newGame(anchor: try XCTUnwrap(kumamoto.anchor), bounds: try XCTUnwrap(kumamoto.bounds), land: [])
        XCTAssertFalse(layout.holds(elsewhere))
        // A world as large as the map now whose anchor is the middle of all
        // of it is not on it either.
        let unGrown = GameWorld.newGame(anchor: layout.anchor, bounds: layout.bounds, land: [])
        XCTAssertFalse(layout.holds(unGrown))
    }

    // MARK: - An old game grows

    /// Fukuoka's pack grown to Kumamoto's extent: its own files, a
    /// `pack.json` with the larger extent and Fukuoka's as `earlier`.
    private func grownFukuoka() throws -> OverseasGround {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka))
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        manifest["extent"] = ["north": 33.72, "south": 32.69, "west": 130.29, "east": 130.9]
        manifest["earlier"] = [["north": 33.72, "south": 33.52, "west": 130.29, "east": 130.48]]
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MapGrowthLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("pack.json"))
        let files = ["population.json", "water.json", "heights.dat"].reduce(into: [String: URL]()) { $0[$1] = pack.url(of: $1) }
        return try OverseasGround(city: .fukuoka, pack: MapPack(root: folder, files: files))
    }

    /// A game on Fukuoka's map as it is in the app, with a line built.
    private func oldFukuokaGame() throws -> GameWorld {
        var world = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground(), balance: Money(100_000_000_000))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 300_000, y: 500_000))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 1_000_000, y: 1_300_000))
        let edge = try world.buildTrackEdge(from: a, to: b)
        let station = try world.buildStation(named: "Hakata", at: PlanPoint(x: 650_000, y: 900_000)).id
        try world.addTrackPlatform(station, on: edge, from: 80_000, to: 120_000)
        _ = try world.buildStation(named: "Tenjin", at: PlanPoint(x: 1_100_000, y: 1_400_000))
        return world
    }

    private func places(of world: GameWorld) throws -> [Double] {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let points = world.stations.map { (Double($0.location.x), Double($0.location.y)) }
            + world.network.nodes.map { (Double($0.position.x), Double($0.position.y)) }
        return points.flatMap { point in
            let at = frame.coordinate(worldX: point.0, worldY: point.1)
            return [at.latitude, at.longitude]
        }
    }

    func testAnOldGameGrowsKeepingItsPlacesAndOwningItsFourTiles() throws {
        let ground = try grownFukuoka()
        let old = try oldFukuokaGame()
        XCTAssertTrue(ground.holds(old), "the grown pack knows the old game")
        let grown = try XCTUnwrap(ground.grown(old))

        XCTAssertEqual(grown.bounds, ground.bounds)
        XCTAssertEqual(grown.geoAnchor, old.geoAnchor)
        XCTAssertEqual(grown.geoAnchorBounds, old.bounds)
        XCTAssertEqual(grown.stations, old.stations)
        XCTAssertEqual(grown.network, old.network)
        XCTAssertEqual(try places(of: grown), try places(of: old), "every station and node over the same place, to the last digit")
        XCTAssertNil(ground.grown(grown), "once")

        let expansion = try XCTUnwrap(grown.mapExpansion)
        XCTAssertEqual(expansion.owned, ground.layout.startTiles)
        XCTAssertEqual(expansion.granted, 4)
        XCTAssertEqual(expansion.bought, 0)
        // The first tile bought costs and asks what a one-tile game's does.
        let oneTile = MapExpansion(owned: [MapTile(row: 0, column: 0)], townSeed: nil, ridersStep: expansion.ridersStep)
        XCTAssertEqual(expansion.nextPrice, oneTile.nextPrice)
        XCTAssertEqual(expansion.ridersNeeded(toOwn: expansion.owned.count + 1), oneTile.ridersNeeded(toOwn: 2))
        XCTAssertEqual(expansion.allowance, 4)
        // The four tiles' some 1.7 million people (√ of their 672,400
        // trips a day is 820, a hundred riders each).
        XCTAssertEqual(expansion.ridersStep, 82_000)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(grown)), grown, "a world GameCore loads")

        // The old pack still on the device: the game goes on as it was.
        XCTAssertNil(try FukuokaRailwaysTests.ground().grown(old))
    }

    func testANewGameOnAGrownMapOwnsTheSameTilesAsAnOldOne() throws {
        let ground = try grownFukuoka()
        let new = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000))
        let old = try XCTUnwrap(ground.grown(try oldFukuokaGame()))
        XCTAssertEqual(new.bounds, old.bounds)
        XCTAssertEqual(new.geoAnchor, old.geoAnchor)
        XCTAssertEqual(new.geoAnchorBounds, old.geoAnchorBounds)
        XCTAssertEqual(new.mapExpansion?.owned, old.mapExpansion?.owned)
        XCTAssertEqual(new.mapExpansion?.granted, 4)
        XCTAssertEqual(new.mapExpansion?.ridersStep, old.mapExpansion?.ridersStep)
        XCTAssertTrue(ground.holds(new))
        // On a pack that never grew a new game is as it was: the whole map,
        // not bought.
        let whole = GameWorld.newOverseasGame(try FukuokaRailwaysTests.ground())
        XCTAssertNil(whole.mapExpansion)
        XCTAssertNil(whole.geoAnchorBounds)
    }

    func testTheExpandButtonAndTheAchievementCountTheTilesBought() throws {
        var world = GameWorld.newOverseasGame(try grownFukuoka(), balance: Money(100_000_000_000))
        XCTAssertTrue(GameSession(world: world, language: .english).namesMapExpansionButton, "four tiles given, none bought")
        XCTAssertEqual(AchievementFacts(world: world).tilesBought, 0)
        try world.buyMapTile(MapTile(row: 2, column: 0), passingMilestone: true)
        XCTAssertFalse(GameSession(world: world, language: .english).namesMapExpansionButton)
        XCTAssertEqual(AchievementFacts(world: world).tilesBought, 1)
    }

    // MARK: - Where the map is looked round

    func testTheFrameOfAGrownWorldIsItsFirstPart() throws {
        let ground = try grownFukuoka()
        let old = try oldFukuokaGame()
        let grown = try XCTUnwrap(ground.grown(old))
        XCTAssertEqual(RealWorldFrame(world: grown), RealWorldFrame(world: old))
        let frame = try XCTUnwrap(RealWorldFrame(world: grown))
        // The middle of the world it was is the anchor itself.
        XCTAssertEqual(frame.place(atMiddleOf: WorldRegion(bounds: old.bounds)), frame.anchor)
        // The middle of the world now lies south and east of it.
        let middle = frame.place(atMiddleOf: WorldRegion(bounds: grown.bounds))
        XCTAssertLessThan(middle.latitude, frame.anchor.latitude)
        XCTAssertGreaterThan(middle.longitude, frame.anchor.longitude)
        XCTAssertEqual(middle.latitudeDegrees, (33.72 + 32.69) / 2, accuracy: 0.01)
        XCTAssertEqual(middle.longitudeDegrees, (130.29 + 130.9) / 2, accuracy: 0.01)
    }
}
