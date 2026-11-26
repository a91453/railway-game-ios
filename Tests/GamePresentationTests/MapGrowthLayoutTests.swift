import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 969, the presentation's half (JAPAN-MAP-GROW): how a city's map
/// that grew lies over the Earth, and a game on it as it was growing with
/// it. The packs that have not grown must lie as they did, to the last
/// digit; Fukuoka's grew to Kumamoto (KUMAMOTO-GROUND), then to the whole
/// of three prefectures, laid anew (decision 991), then of four (decision
/// 997, Nagasaki's), laid anew again, and the packs it was
/// before are made here from it, with the extents they had.
@MainActor
final class MapGrowthLayoutTests: XCTestCase {
    private let fukuoka = MapPack.Extent(north: 33.72, south: 33.52, west: 130.29, east: 130.48)
    private let kumamoto = MapPack.Extent(north: 33.72, south: 32.69, west: 130.29, east: 130.9)
    /// Decision 991: the map the games before it grow to, its north-west
    /// corner Fukuoka's first.
    private let older = MapPack.Extent(north: 33.72, south: 32.09, west: 130.29, east: 131.33)
    /// Decision 991: the whole of Fukuoka, Saga and Kumamoto Prefectures.
    private let threePrefectures = MapPack.Extent(north: 34.03, south: 32.09, west: 129.73, east: 131.33)
    /// Decision 997: and Nagasaki's, the west edge moved to Hirado.
    private let prefectures = MapPack.Extent(north: 34.03, south: 32.09, west: 129.34, east: 131.33)

    // MARK: - The packs that never grew

    /// The anchor and the world of each pack in the app, written out: a
    /// save on one is found by them (``OverseasGround/holds(_:)``).
    func testThePacksInTheAppLieAsTheyDid() throws {
        let expected: [OverseasMap: (latitude: Int64, longitude: Int64, width: Int64, height: Int64)] = [
            .hongKong: (223_543_496, 1_141_375_000, 4_008_773, 2_909_631),
            .rovaniemi: (665_512_574, 264_000_000, 6_804_050, 3_562_176),
        ]
        for city in OverseasMap.allCases where city != .fukuoka {
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

    /// Decision 991: Fukuoka's pack holds the whole of three prefectures,
    /// laid anew round them, with three places to begin; the games laid
    /// on it before lie where they did, on its older layout, whose anchor
    /// and first world are written out as they were pinned before.
    func testFukuokasPackHoldsThreePrefecturesAndItsOldGamesLieWhereTheyDid() throws {
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka))
        let extents = try MapPack.extents(ofManifest: pack.file("pack", "json"))
        XCTAssertEqual(extents.extent, prefectures)
        XCTAssertEqual(extents.earlier, [])
        let ground = try OverseasGround(city: .fukuoka, pack: pack)
        XCTAssertEqual(ground.anchor, prefectures.anchor)
        XCTAssertEqual(ground.bounds, prefectures.bounds)
        XCTAssertNil(ground.layout.anchorBounds)
        XCTAssertEqual(ground.layout.starts.map(\.name), ["福岡", "佐賀", "熊本", "長崎"])
        XCTAssertEqual(ground.layout.starts.map(\.englishName), ["Fukuoka", "Saga", "Kumamoto", "Nagasaki"])
        let old = try XCTUnwrap(ground.layout.older.first)
        XCTAssertEqual(ground.layout.older.count, 2)
        XCTAssertEqual(old, MapPack.Layout(extent: older, earlier: [fukuoka, kumamoto]))
        // Decision 997: the games laid over the three prefectures stay on
        // them, round their own middle.
        XCTAssertEqual(ground.layout.older.last, MapPack.Layout(extent: threePrefectures, earlier: []))
        XCTAssertEqual(old.anchor, GeoAnchor(latitude: 336_200_580, longitude: 1_303_850_000))
        XCTAssertEqual(old.earlier, [try WorldBounds(width: 1_127_218, height: 1_424_891), try WorldBounds(width: 3_618_962, height: 7_303_379)])
        // Its ground reaches as far as its map.
        let heights = try XCTUnwrap(ground.heights), water = try XCTUnwrap(ground.water)
        XCTAssertGreaterThan(heights.height(latitude: 32.8140, longitude: 130.6388), 500, "Kinpozan, west of Kumamoto")
        XCTAssertGreaterThan(heights.height(latitude: 33.4362, longitude: 130.3674), 800, "Sefurisan, between Fukuoka and Saga")
        XCTAssertFalse(water.isWater(latitude: 32.7900, longitude: 130.6890), "Kumamoto Station")
        XCTAssertFalse(water.isWater(latitude: 33.2643, longitude: 130.2975), "Saga Station")
        XCTAssertFalse(water.isWater(latitude: 33.8865, longitude: 130.8826), "Kokura Station")
        XCTAssertTrue(water.isWater(latitude: 32.9000, longitude: 130.3500), "the Ariake Sea")
        XCTAssertTrue(water.isWater(latitude: 33.9000, longitude: 130.2000), "the Genkai Sea")
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

    /// Fukuoka's pack as it is in the app: three prefectures.
    private func grownFukuoka() throws -> OverseasGround {
        try FukuokaRailwaysTests.ground()
    }

    /// Fukuoka's pack as it was before it grew, still on a device that has
    /// not got the new one: its files, a `pack.json` with the extent it
    /// had and no `earlier`.
    private func fukuokaBeforeItGrew() throws -> OverseasGround {
        try fukuokaAsItWas(extent: fukuoka, earlier: [])
    }

    /// Fukuoka's pack as it was once it had grown to Kumamoto (decision
    /// 969), before decision 991.
    private func fukuokaGrownToKumamoto() throws -> OverseasGround {
        try fukuokaAsItWas(extent: kumamoto, earlier: [fukuoka])
    }

    private func fukuokaAsItWas(extent: MapPack.Extent, earlier: [MapPack.Extent]) throws -> OverseasGround {
        func json(_ e: MapPack.Extent) -> [String: Double] { ["north": e.north, "south": e.south, "west": e.west, "east": e.east] }
        let pack = try XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka))
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: pack.file("pack", "json")) as? [String: Any])
        manifest["extent"] = json(extent)
        manifest["earlier"] = earlier.isEmpty ? nil : earlier.map(json)
        manifest["starts"] = nil
        manifest["older"] = nil
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MapGrowthLayoutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("pack.json"))
        let files = ["population.json", "water.json", "heights.dat"].reduce(into: [String: URL]()) { $0[$1] = pack.url(of: $1) }
        return try OverseasGround(city: .fukuoka, pack: MapPack(root: folder, files: files))
    }

    /// A game on Fukuoka's map as it was before it grew, with a line built.
    private func oldFukuokaGame() throws -> GameWorld {
        var world = GameWorld.newOverseasGame(try fukuokaBeforeItGrew(), balance: Money(100_000_000_000))
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

    /// Decision 991: an old game grows on the older layout, to the new
    /// south and east edges, its north-west corner where it was.
    func testAnOldGameGrowsKeepingItsPlacesAndOwningItsFourTiles() throws {
        let ground = try grownFukuoka()
        let layout = try XCTUnwrap(ground.layout.older.first)
        let old = try oldFukuokaGame()
        XCTAssertTrue(ground.holds(old), "the grown pack knows the old game")
        XCTAssertEqual(ground.layout.layout(holding: old), layout)
        let grown = try XCTUnwrap(ground.grown(old))

        XCTAssertEqual(grown.bounds, layout.bounds)
        XCTAssertEqual(grown.geoAnchor, old.geoAnchor)
        XCTAssertEqual(grown.geoAnchorBounds, old.bounds)
        XCTAssertEqual(grown.stations, old.stations)
        XCTAssertEqual(grown.network, old.network)
        XCTAssertEqual(try places(of: grown), try places(of: old), "every station and node over the same place, to the last digit")
        XCTAssertNil(ground.grown(grown), "once")

        let expansion = try XCTUnwrap(grown.mapExpansion)
        XCTAssertEqual(expansion.owned, layout.startTiles)
        XCTAssertEqual(expansion.owned, [MapTile(row: 0, column: 0), MapTile(row: 0, column: 1), MapTile(row: 1, column: 0), MapTile(row: 1, column: 1)])
        XCTAssertEqual(expansion.granted, 4)
        XCTAssertEqual(expansion.bought, 0)
        // The first tile bought costs and asks what a one-tile game's does.
        let oneTile = MapExpansion(owned: [MapTile(row: 0, column: 0)], townSeed: nil, ridersStep: expansion.ridersStep)
        XCTAssertEqual(expansion.nextPrice, oneTile.nextPrice)
        XCTAssertEqual(expansion.ridersNeeded(toOwn: expansion.owned.count + 1), oneTile.ridersNeeded(toOwn: 2))
        XCTAssertEqual(expansion.allowance, 4)
        // The four tiles' some 2.2 million people: Fukuoka's 1.7 million
        // and, now that the pack's people reach as far as the tiles do,
        // Dazaifu's and Chikushino's south and east of the map it was (√
        // of their trips a day is 930 and some, a hundred riders each).
        XCTAssertEqual(expansion.ridersStep, 93_000)
        XCTAssertEqual(try JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(grown)), grown, "a world GameCore loads")

        // The old pack still on the device: the game goes on as it was.
        XCTAssertNil(try fukuokaBeforeItGrew().grown(old))
    }

    /// Decision 991: a game saved once the map had grown to Kumamoto grows
    /// on to the older layout's edges, owning what it owned.
    func testAGameOfTheMapGrownToKumamotoGrowsOn() throws {
        let ground = try grownFukuoka()
        let layout = try XCTUnwrap(ground.layout.older.first)
        let middle = try XCTUnwrap(try fukuokaGrownToKumamoto().grown(try oldFukuokaGame()))
        XCTAssertEqual(middle.bounds, try WorldBounds(width: 3_618_962, height: 7_303_379))
        XCTAssertEqual(ground.layout.layout(holding: middle), layout)
        let grown = try XCTUnwrap(ground.grown(middle))
        XCTAssertEqual(grown.bounds, layout.bounds)
        XCTAssertEqual(grown.geoAnchor, middle.geoAnchor)
        XCTAssertEqual(grown.geoAnchorBounds, middle.geoAnchorBounds)
        XCTAssertEqual(grown.mapExpansion, middle.mapExpansion, "what it owned and bought, as it was")
        XCTAssertEqual(try places(of: grown), try places(of: middle))
        XCTAssertNil(ground.grown(grown), "once")
        // The world now reaches Kumamoto Airport's east and Hitoyoshi's south.
        let frame = try XCTUnwrap(RealWorldFrame(world: grown))
        let southEast = frame.coordinate(worldX: Double(grown.bounds.width), worldY: Double(grown.bounds.height))
        XCTAssertEqual(southEast.latitude, 32.09, accuracy: 1e-6)
        XCTAssertEqual(southEast.longitude, 131.33, accuracy: 1e-6)
    }

    /// Decision 997: a game begun on the three prefectures' map (decision
    /// 991) stays on it, round its own middle, as it was: the map's new
    /// west does not move what it built.
    func testAGameOfTheThreePrefecturesStaysAsItWas() throws {
        let ground = try grownFukuoka()
        let three = try XCTUnwrap(MapPack.Layout(extent: threePrefectures, earlier: []))
        var world = GameWorld.newGame(anchor: three.anchor, bounds: three.bounds, land: [])
        try world.enableMapExpansion(owning: [MapTile(row: 4, column: 4)], townSeed: nil, ridersStep: 1_000)
        XCTAssertNotEqual(three.anchor, ground.anchor, "the map is laid anew")
        XCTAssertTrue(ground.holds(world))
        XCTAssertEqual(ground.layout.layout(holding: world), three)
        XCTAssertNil(ground.grown(world), "it reaches as far as it did")
    }

    /// Decision 991: a new game is laid over the whole of the three
    /// prefectures and owns the 2 × 2 tiles round the city picked, the
    /// rest bought.
    func testANewGameBeginsRoundTheCityPicked() throws {
        let ground = try grownFukuoka()
        let stations: [(name: String, latitude: Double, longitude: Double)] = [
            ("Hakata", 33.5897, 130.4207), ("Saga", 33.2643, 130.2975), ("Kumamoto", 32.7898, 130.6886),
            ("Nagasaki", 32.7528, 129.8691),
        ]
        var steps: [Int64] = []
        for (index, station) in stations.enumerated() {
            let new = GameWorld.newOverseasGame(ground, balance: Money(100_000_000_000), start: index)
            XCTAssertEqual(new.bounds, ground.bounds, station.name)
            XCTAssertEqual(new.geoAnchor, ground.anchor, station.name)
            XCTAssertNil(new.geoAnchorBounds, station.name)
            XCTAssertTrue(ground.holds(new), station.name)
            XCTAssertNil(ground.grown(new), station.name)
            let expansion = try XCTUnwrap(new.mapExpansion, station.name)
            XCTAssertEqual(expansion.owned, ground.layout.startTiles(at: index), station.name)
            XCTAssertEqual(expansion.owned.count, 4, station.name)
            XCTAssertEqual(expansion.granted, 4, station.name)
            let frame = try XCTUnwrap(RealWorldFrame(world: new))
            let at = frame.worldPosition(latitude: station.latitude, longitude: station.longitude)
            let tile = MapTile(row: Int(at.y) / Int(MapExpansion.tileLength), column: Int(at.x) / Int(MapExpansion.tileLength))
            XCTAssertTrue(expansion.owned.contains(tile), "\(station.name) Station is in the land given")
            steps.append(expansion.ridersStep)
        }
        XCTAssertEqual(GameWorld.newOverseasGame(ground).mapExpansion?.owned, ground.layout.startTiles, "Fukuoka unless another is picked")
        XCTAssertGreaterThan(steps[0], steps[2], "Fukuoka's people are more than Kumamoto's")
        XCTAssertGreaterThan(steps[2], steps[1], "and Kumamoto's than Saga's")
        // On a pack that never grew a new game is as it was: the whole map,
        // not bought.
        let whole = GameWorld.newOverseasGame(try fukuokaBeforeItGrew())
        XCTAssertNil(whole.mapExpansion)
        XCTAssertNil(whole.geoAnchorBounds)
    }

    func testTheExpandButtonAndTheAchievementCountTheTilesBought() throws {
        var world = GameWorld.newOverseasGame(try grownFukuoka(), balance: Money(100_000_000_000))
        XCTAssertTrue(GameSession(world: world, language: .english).namesMapExpansionButton, "four tiles given, none bought")
        XCTAssertEqual(AchievementFacts(world: world).tilesBought, 0)
        let owned = try XCTUnwrap(world.mapExpansion?.owned)
        let below = MapTile(row: try XCTUnwrap(owned.map(\.row).max()) + 1, column: try XCTUnwrap(owned.map(\.column).min()))
        try world.buyMapTile(below, passingMilestone: true)
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
        XCTAssertEqual(middle.latitudeDegrees, (33.72 + 32.09) / 2, accuracy: 0.01)
        XCTAssertEqual(middle.longitudeDegrees, (130.29 + 131.33) / 2, accuracy: 0.01)
    }
}
