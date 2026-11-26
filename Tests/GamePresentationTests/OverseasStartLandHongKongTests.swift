import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 992, Hong Kong's part (``OverseasStartLandTests`` has the
/// rules every map shares): a new game starts with the four tiles with the
/// most people and buys the rest, or opens the map whole; an old game
/// stays whole and counted. SPLIT-HOTSPOTS-2: a map of its own file.
///
/// Expected values are worked out from the rules and the packs' data,
/// never taken from a previous run.
@MainActor
final class OverseasStartLandHongKongTests: XCTestCase {
    static let ground: OverseasGround = {
        do {
            return try OverseasGround(city: .hongKong, pack: XCTUnwrap(HongKongRailwaysTests.pack(.hongKong)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    // MARK: - Which four

    /// Hong Kong's world is 3.8 tiles by 2.8 (62.6 by 45.5 km), so four
    /// columns by three rows; its tiles' edges lie at 113.99°, 114.15° and
    /// 114.31° E and 22.41° and 22.26° N. Of the six two by twos the one
    /// of columns 1–2, rows 0–1 holds the most people (WorldPop, about 6.4
    /// million of 7.4): Kowloon, the north shore of Hong Kong Island,
    /// Tsuen Wan, Sha Tin, Tai Po and the border. The airport and Tung
    /// Chung, on column 0, are bought.
    func testHongKongStartsWithKowloonAndTheNewTownsNorthOfIt() throws {
        let ground = Self.ground
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

    /// Hong Kong buys its land and can be opened whole.
    func testHongKongBuysLandAndOpensWhole() {
        XCTAssertTrue(OverseasMap.hongKong.buysLand)
        XCTAssertNotNil(OverseasMap.hongKong.wholeMapSummary(in: .traditionalChinese))
    }

    // MARK: - New games

    func testANewHongKongGameOwnsItsFourTilesAndBuysTheRest() throws {
        let ground = Self.ground
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
        let ground = Self.ground
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

    // MARK: - The launcher

    func testTheLauncherStartsHongKongWithFourTilesOrWhole() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverseasStartLand-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        await launcher.loadRealWorldData {
            RealWorldData.load(overseas: [.hongKong], pack: HongKongRailwaysTests.pack, file: RealWorldDataLoadTests.file)
        }.value
        XCTAssertTrue(launcher.startOverseasMap(.hongKong), launcher.message?.text ?? "")
        var world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.mapExpansion?.owned, Self.ground.startTiles)
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
}
