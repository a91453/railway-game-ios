import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 992: a new game on Hong Kong's map starts with the four tiles
/// with the most people and buys the rest; Hong Kong's and Japan's maps can
/// be opened whole instead, counting no achievements; Rovaniemi stays
/// whole and counted; an old Hong Kong game stays whole and counted.
///
/// Expected values are worked out from the rules and the packs' data,
/// never taken from a previous run.
@MainActor
final class OverseasStartLandTests: XCTestCase {
    private static let hongKong: OverseasGround = {
        do {
            return try OverseasGround(city: .hongKong, pack: XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let fukuoka: OverseasGround = {
        do {
            return try OverseasGround(city: .fukuoka, pack: XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private static let rovaniemi: OverseasGround = {
        do {
            return try OverseasGround(city: .rovaniemi, pack: XCTUnwrap(HongKongRailwaysTests.pack(.rovaniemi)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    private let tile = Double(MapExpansion.tileLength)

    // MARK: - Which four

    /// Hong Kong's world is 3.8 tiles by 2.8 (62.6 by 45.5 km), so four
    /// columns by three rows; its tiles' edges lie at 113.99°, 114.15° and
    /// 114.31° E and 22.41° and 22.26° N. Of the six two by twos the one
    /// of columns 1–2, rows 0–1 holds the most people (WorldPop, about 6.4
    /// million of 7.4): Kowloon, the north shore of Hong Kong Island,
    /// Tsuen Wan, Sha Tin, Tai Po and the border. The airport and Tung
    /// Chung, on column 0, are bought.
    func testHongKongStartsWithKowloonAndTheNewTownsNorthOfIt() throws {
        let ground = Self.hongKong
        XCTAssertNil(ground.layout.anchorBounds, "Hong Kong's map never grew")
        XCTAssertEqual(ground.startTiles, [
            MapTile(row: 0, column: 1), MapTile(row: 0, column: 2), MapTile(row: 1, column: 1), MapTile(row: 1, column: 2),
        ])
        let frame = RealWorldFrame(anchor: ground.anchor, bounds: ground.bounds)
        func tile(of latitude: Double, _ longitude: Double) -> MapTile {
            let point = frame.worldPosition(latitude: latitude, longitude: longitude)
            let length = Double(MapExpansion.tileLength)
            return MapTile(row: Int(point.y / length), column: Int(point.x / length))
        }
        for (name, latitude, longitude) in [
            ("Mong Kok", 22.3193, 114.1694), ("Central", 22.2819, 114.1582), ("Sha Tin", 22.3824, 114.1880),
            ("Tsuen Wan", 22.3714, 114.1135), ("Tai Po Market", 22.4448, 114.1704), ("Lo Wu", 22.5281, 114.1135),
        ] {
            XCTAssertTrue(ground.startTiles.contains(tile(of: latitude, longitude)), name)
        }
        for (name, latitude, longitude) in [("Airport", 22.3159, 113.9365), ("Tuen Mun", 22.3951, 113.9733), ("Aberdeen", 22.2480, 114.1540)] {
            XCTAssertFalse(ground.startTiles.contains(tile(of: latitude, longitude)), name)
        }
        let all = ground.residents(of: [MapTile(row: 0, column: 0), MapTile(row: 2, column: 3)], frame: frame)
        let start = ground.residents(of: ground.startTiles, frame: frame)
        XCTAssertEqual(Double(start) / Double(all), 0.86, accuracy: 0.03, "about 6.4 of 7.4 million")
    }

    /// Japan's map grew (decision 969): its four are those that hold
    /// Fukuoka's first extent. Rovaniemi has none: it stays whole.
    func testJapanKeepsItsFirstExtentsTilesAndRovaniemiHasNone() {
        XCTAssertEqual(Self.fukuoka.startTiles, Self.fukuoka.layout.startTiles)
        XCTAssertEqual(Self.fukuoka.startTiles.count, 4)
        XCTAssertEqual(Self.rovaniemi.startTiles, [])
        XCTAssertTrue(OverseasMap.hongKong.buysLand && OverseasMap.fukuoka.buysLand)
        XCTAssertFalse(OverseasMap.rovaniemi.buysLand)
        XCTAssertNil(OverseasMap.rovaniemi.wholeMapSummary(in: .english))
        XCTAssertNotNil(OverseasMap.hongKong.wholeMapSummary(in: .traditionalChinese))
    }

    // MARK: - New games

    func testANewHongKongGameOwnsItsFourTilesAndBuysTheRest() throws {
        let ground = Self.hongKong
        let world = GameWorld.newOverseasGame(ground, wholeMap: false, eventSeed: 3)
        XCTAssertTrue(ground.holds(world))
        XCTAssertEqual(world.bounds, ground.bounds)
        XCTAssertFalse(world.wholeMapOpen)
        let expansion = try XCTUnwrap(world.mapExpansion)
        XCTAssertEqual(expansion.owned, ground.startTiles)
        XCTAssertEqual(expansion.granted, 4)
        XCTAssertEqual(expansion.bought, 0)
        // 6.4 million people: past the standard step's 2.5 million.
        XCTAssertEqual(expansion.ridersStep, MapExpansion.standardRidersStep)
        XCTAssertEqual(expansion.ridersStep, ground.ridersStep(owning: ground.startTiles, in: world))
        // The tiles that share a side with the four are for sale: two
        // west, two east and two south.
        XCTAssertEqual(world.mapTilesForSale(), [
            MapTile(row: 0, column: 0), MapTile(row: 0, column: 3), MapTile(row: 1, column: 0), MapTile(row: 1, column: 3),
            MapTile(row: 2, column: 1), MapTile(row: 2, column: 2),
        ])
        // The airport's tile is not the company's yet.
        var built = world
        let frame = RealWorldFrame(anchor: ground.anchor, bounds: ground.bounds)
        let airport = frame.worldPosition(latitude: 22.3159, longitude: 113.9365)
        XCTAssertThrowsError(try built.buildStation(named: "Airport", at: PlanPoint(x: Int64(airport.x), y: Int64(airport.y)))) { error in
            XCTAssertEqual(error as? GameError, .mapTileNotOwned(MapTile(row: 1, column: 0)))
        }
        // Saved and read back the same.
        let saved = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: saved).world, world)
    }

    func testAWholeHongKongGameIsTheOldMapMarked() throws {
        let ground = Self.hongKong
        let old = GameWorld.newOverseasGame(ground, eventSeed: 3)
        XCTAssertNil(old.mapExpansion, "an old game's map was whole")
        XCTAssertFalse(old.wholeMapOpen, "and counted")
        let whole = GameWorld.newOverseasGame(ground, wholeMap: true, eventSeed: 3)
        XCTAssertTrue(whole.wholeMapOpen)
        XCTAssertNil(whole.mapExpansion)
        XCTAssertTrue(ground.holds(whole))
        // The mark is all that differs.
        var marked = old
        try marked.openWholeMap()
        XCTAssertEqual(whole, marked)
        let saved = try JSONEncoder().encode(SavedGame(world: whole))
        XCTAssertTrue(try JSONDecoder().decode(SavedGame.self, from: saved).world.wholeMapOpen)
    }

    /// Japan's whole map: the world of the map as it is now, laid as a
    /// grown game is, with nothing to buy; a normal game is the one
    /// decision 969 made, four tiles.
    func testJapansWholeMapIsTheGrownMapWithNothingToBuy() throws {
        let ground = Self.fukuoka
        let whole = GameWorld.newOverseasGame(ground, wholeMap: true, eventSeed: 3)
        XCTAssertTrue(ground.holds(whole))
        XCTAssertEqual(whole.bounds, ground.bounds)
        XCTAssertEqual(whole.geoAnchorBounds, ground.layout.anchorBounds)
        XCTAssertNil(whole.mapExpansion)
        XCTAssertTrue(whole.wholeMapOpen)
        XCTAssertNil(ground.grown(whole), "already the map as it is")

        let bought = GameWorld.newOverseasGame(ground, wholeMap: false, eventSeed: 3)
        XCTAssertEqual(bought, GameWorld.newOverseasGame(ground, eventSeed: 3))
        XCTAssertEqual(bought.mapExpansion?.owned, ground.startTiles)
        XCTAssertFalse(bought.wholeMapOpen)
    }

    /// A whole map that grows (a game opened whole on Japan's first extent,
    /// as a later pack could find one) stays whole: no tiles to buy.
    func testAWholeMapThatGrowsStaysWhole() throws {
        // An old Fukuoka game, laid over the map as it lay before its
        // north and west edges moved (decision 991).
        let ground = Self.fukuoka
        let old = try XCTUnwrap(ground.layout.older.first)
        let first = try XCTUnwrap(old.anchorBounds)
        var world = GameWorld.newGame(anchor: old.anchor, bounds: first, eventSeed: 3, land: [])
        world.setLandOnDemand()
        try world.openWholeMap()
        XCTAssertTrue(ground.holds(world))
        let grown = try XCTUnwrap(ground.grown(world))
        XCTAssertEqual(grown.bounds, old.bounds)
        XCTAssertNil(grown.mapExpansion)
        XCTAssertTrue(grown.wholeMapOpen)
    }

    func testRovaniemiIsWholeAndCountedEitherWay() {
        let ground = Self.rovaniemi
        for wholeMap in [false, true] {
            let world = GameWorld.newOverseasGame(ground, wholeMap: wholeMap, eventSeed: 3)
            XCTAssertEqual(world, GameWorld.newOverseasGame(ground, eventSeed: 3))
            XCTAssertNil(world.mapExpansion)
            XCTAssertFalse(world.wholeMapOpen)
        }
    }

    // MARK: - The launcher and achievements

    func testTheLauncherStartsHongKongWithFourTilesOrWhole() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverseasStartLand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: [.hongKong], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        var world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.mapExpansion?.owned, Self.hongKong.startTiles)
        XCTAssertFalse(world.wholeMapOpen)
        XCTAssertEqual(launcher.session?.mapExpansionText?.hasPrefix("Map: 4 of 12 tiles"), true)

        XCTAssertTrue(launcher.startOverseasMap(.hongKong, wholeMap: true), launcher.message?.text ?? "")
        world = try XCTUnwrap(launcher.session?.world)
        XCTAssertNil(world.mapExpansion)
        XCTAssertTrue(world.wholeMapOpen)

        // A demo has the whole map, as on Taiwan.
        launcher.isDemoMode = true
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        XCTAssertNil(launcher.session?.world.mapExpansion)
    }

    // MARK: - Decision 999: which city a game on Japan's map begins round

    /// Japan's map, once open, has a row for each place its pack names to
    /// begin round, the first keeping the city's row's identifier; each
    /// starts a game owning the four tiles round its place. Closed, it is
    /// one row; a map with one place to begin (Hong Kong) has one row.
    func testJapansGamesBeginRoundTheCityPicked() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverseasStartLand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: [.hongKong, .fukuoka], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        launcher.rememberAirRoutes([AirMap.taiwan.id])
        let closed = try XCTUnwrap(launcher.overseasMapRows(in: .traditionalChinese).first { $0.city == .fukuoka })
        XCTAssertNotNil(closed.closed, "Japan waits for its flights")
        XCTAssertEqual(launcher.overseasStartRows(for: closed, in: .traditionalChinese).map(\.name), ["日本"])

        launcher.rememberAirRoutes([OverseasMap.fukuoka.rawValue])
        let rows = launcher.overseasMapRows(in: .traditionalChinese)
        let japan = try XCTUnwrap(rows.first { $0.city == .fukuoka })
        XCTAssertNil(japan.closed)
        let starts = launcher.overseasStartRows(for: japan, in: .traditionalChinese)
        XCTAssertEqual(starts.map(\.name), ["日本：從福岡開始", "日本：從佐賀開始", "日本：從熊本開始"])
        XCTAssertEqual(starts.map(\.id), ["realWorld.overseas.fukuoka", "realWorld.overseas.fukuoka.start.1", "realWorld.overseas.fukuoka.start.2"])
        XCTAssertEqual(starts.map(\.start), [0, 1, 2])
        XCTAssertEqual(starts[0].summary, OverseasMap.fukuoka.mapSummary(in: .traditionalChinese))
        XCTAssertEqual(starts[2].summary, "一開始是熊本一帶約 33 × 33 公里，地圖其餘部分用買的。")
        XCTAssertEqual(
            launcher.overseasStartRows(for: japan, in: .english).map(\.name),
            ["Japan: start in Fukuoka", "Japan: start in Saga", "Japan: start in Kumamoto"]
        )
        XCTAssertEqual(OverseasMap.fukuoka.wholeMapName(in: .traditionalChinese), "日本（整張全開）")
        let hongKong = try XCTUnwrap(rows.first { $0.city == .hongKong })
        XCTAssertEqual(launcher.overseasStartRows(for: hongKong, in: .traditionalChinese).map(\.id), ["realWorld.overseas.hongKong"])

        let ground = Self.fukuoka
        for row in starts {
            XCTAssertTrue(launcher.startOverseasMap(.fukuoka, start: row.start), launcher.message?.text ?? "")
            let world = try XCTUnwrap(launcher.session?.world)
            XCTAssertEqual(world.mapExpansion?.owned, ground.layout.startTiles(at: row.start), row.name)
            XCTAssertFalse(world.wholeMapOpen, row.name)
        }
        XCTAssertNotEqual(ground.layout.startTiles(at: 0), ground.layout.startTiles(at: 2), "Kumamoto is not Fukuoka")
        // The whole map is the whole map wherever it was asked from.
        XCTAssertTrue(launcher.startOverseasMap(.fukuoka, wholeMap: true, start: 2), launcher.message?.text ?? "")
        XCTAssertNil(launcher.session?.world.mapExpansion)
        XCTAssertEqual(launcher.session?.world.wholeMapOpen, true)
    }

    /// A map opened whole counts no achievements, and their list says so;
    /// the same network on a map bought tile by tile counts them.
    func testAWholeMapCountsNoAchievements() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverseasStartLand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var counted = try newGameLine(through: [towns[0], towns[1]])
        try counted.advance(ticks: 2 * 1_440)
        var whole = counted
        try whole.openWholeMap()
        launcher.checkAchievements(of: GameSession(world: whole, language: .english))
        XCTAssertEqual(launcher.achievements.count, 0, "a whole map earns nothing")
        launcher.checkAchievements(of: GameSession(world: counted, language: .english))
        XCTAssertTrue(launcher.achievements.unlocked.keys.contains("firstFare"))

        XCTAssertEqual(
            GameMenuLayout.achievementsNote(unlimitedFunds: false, wholeMap: true, in: .traditionalChinese), "整張全開的地圖不計成就。"
        )
        XCTAssertNil(GameMenuLayout.achievementsNote(unlimitedFunds: false, wholeMap: false, in: .english))
    }
}
