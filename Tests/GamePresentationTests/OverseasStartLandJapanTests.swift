import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 992, Japan's part (``OverseasStartLandTests`` has the rules
/// every map shares): a new game starts with the four tiles round the
/// place picked (decision 999; the places in ``OverseasStartLandJapanList``,
/// one a line) and buys the rest, or opens the grown map whole.
/// SPLIT-HOTSPOTS-2: a map of its own file.
///
/// Expected values are worked out from the rules and the packs' data,
/// never taken from a previous run.
@MainActor
final class OverseasStartLandJapanTests: XCTestCase {
    static let ground: OverseasGround = {
        do {
            return try OverseasGround(city: .fukuoka, pack: XCTUnwrap(HongKongRailwaysTests.pack(.fukuoka)))
        } catch {
            preconditionFailure("\(error)")
        }
    }()

    // MARK: - Which four

    /// Japan's map grew (decision 969): its four are those that hold
    /// Fukuoka's first extent.
    func testJapanKeepsItsFirstExtentsTiles() {
        XCTAssertEqual(Self.ground.startTiles, Self.ground.layout.startTiles)
        XCTAssertEqual(Self.ground.startTiles.count, 4)
        XCTAssertTrue(OverseasMap.fukuoka.buysLand)
    }

    // MARK: - New games

    /// Japan's whole map: the world of the map as it is now, laid as a
    /// grown game is, with nothing to buy; a normal game is the one
    /// decision 969 made, four tiles.
    func testJapansWholeMapIsTheGrownMapWithNothingToBuy() throws {
        let ground = Self.ground
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
        let ground = Self.ground
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
        let list = OverseasStartLandJapanList.places.sorted { $0.start < $1.start }
        XCTAssertEqual(list.map(\.start), Array(list.indices), "one line a place, numbered from 0 with no gap or twin")
        XCTAssertEqual(starts.map(\.name), list.map { "日本：從\($0.chinese)開始" })
        XCTAssertEqual(starts.map(\.id), list.map { $0.start == 0 ? "realWorld.overseas.fukuoka" : "realWorld.overseas.fukuoka.start.\($0.start)" })
        XCTAssertEqual(starts.map(\.start), list.map(\.start), "decision 997: Nagasaki the fourth")
        XCTAssertEqual(starts[0].summary, OverseasMap.fukuoka.mapSummary(in: .traditionalChinese))
        XCTAssertEqual(starts[2].summary, "一開始是熊本一帶約 33 × 33 公里，地圖其餘部分用買的。")
        XCTAssertEqual(launcher.overseasStartRows(for: japan, in: .english).map(\.name), list.map { "Japan: start in \($0.english)" })
        XCTAssertEqual(OverseasMap.fukuoka.wholeMapName(in: .traditionalChinese), "日本（整張全開）")
        let hongKong = try XCTUnwrap(rows.first { $0.city == .hongKong })
        XCTAssertEqual(launcher.overseasStartRows(for: hongKong, in: .traditionalChinese).map(\.id), ["realWorld.overseas.hongKong"])

        let ground = Self.ground
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
}
