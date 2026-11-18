import XCTest
@testable import GameCore
@testable import GamePresentation

/// Decision 845: the station card's nameboard gives a real station its
/// other name under the one it has in the game.
@MainActor
final class StationSecondNameTests: XCTestCase {
    private func railways() throws -> RealRailways {
        try BundledRealData.railways()
    }

    private func second(_ name: String, _ language: DisplayLanguage) throws -> String? {
        GameSession.secondName(of: name, real: try railways().stations(named: name, near: nil), language: language)
    }

    /// In Chinese: the official English name of a Taiwanese or Hong Kong
    /// station, the Finnish one of a station in Lapland.
    func testAChineseNameGetsItsEnglishOrOwnName() throws {
        XCTAssertEqual(try second("凱米耶爾維", .traditionalChinese), "Kemijärvi")
        XCTAssertEqual(try second("羅瓦涅米", .traditionalChinese), "Rovaniemi")
        XCTAssertEqual(try second("上水", .traditionalChinese), "Sheung Shui")
        XCTAssertEqual(try second("七堵", .traditionalChinese), "Qidu")
        // A name the data tells apart by a suffix shows it as the
        // station list does.
        XCTAssertEqual(try second("中里", .traditionalChinese), "Zhongli (Yilan)")
    }

    /// In English: a Taiwanese or Hong Kong station gets its Chinese name
    /// under the English one; a Finnish one, whose English name is the
    /// one on its signs, shows one line.
    func testAnEnglishNameGetsItsChineseOneOutsideFinland() throws {
        XCTAssertEqual(try second("Sheung Shui", .english), "上水")
        XCTAssertEqual(try second("Qidu", .english), "七堵")
        XCTAssertNil(try second("Kemijärvi", .english))
        // A game named in English, played in Chinese, still gets the
        // Chinese name.
        XCTAssertEqual(try second("Kemijärvi", .traditionalChinese), "凱米耶爾維")
        // A game named in Chinese, played in English, gets the English
        // name.
        XCTAssertEqual(try second("凱米耶爾維", .english), "Kemijärvi")
    }

    /// A name no real station has (the player's own) gets nothing.
    func testAPlayersOwnNameGetsNothing() throws {
        XCTAssertNil(try second("我家門口", .traditionalChinese))
        XCTAssertNil(try second("Home Sweet Home", .english))
        XCTAssertNil(GameSession.secondName(of: "台北", real: [], language: .traditionalChinese))
    }

    /// A bought line's stations, as the game names them, get their second
    /// name; a blank map's stations get none.
    func testABoughtLineInRovaniemiShowsFinnishNames() throws {
        let session = try RovaniemiRailwaysTests.rovaniemi()
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "vr:KJA" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let stations = session.world.stations
        XCTAssertFalse(stations.isEmpty)
        let named = Dictionary(stations.map { ($0.name, session.stationSecondName(of: $0.id)) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(named["凱米耶爾維"], "Kemijärvi")
        XCTAssertEqual(named["羅瓦涅米"], "Rovaniemi")

        // A renamed station is the player's own.
        let kemijarvi = try XCTUnwrap(stations.first { $0.name == "凱米耶爾維" })
        session.selectStation(kemijarvi.id)
        session.renameSelectedStation(to: "聖誕老人站")
        XCTAssertEqual(session.world.station(id: kemijarvi.id)?.name, "聖誕老人站")
        XCTAssertNil(session.stationSecondName(of: kemijarvi.id))

        // A map that is not the real world names no real station.
        var world = try GameWorld(bounds: WorldBounds(width: 131_072, height: 65_536), economy: GameEconomy(balance: 1_000_000_000_000))
        let taipei = try world.buildStation(named: "台北", at: PlanPoint(x: 1_000, y: 1_000))
        let blank = GameSession(world: world, language: .traditionalChinese)
        blank.railways = try railways()
        XCTAssertNil(blank.stationSecondName(of: taipei.id))
    }

    /// The screenshot scene's two stations stand where the real ones do,
    /// so each shows its second name.
    func testTheScreenshotSceneNamesRealStations() throws {
        for (language, seconds) in [(DisplayLanguage.traditionalChinese, ["Taipei", "Shandao Temple"]), (.english, ["臺北", "善導寺"])] {
            let session = GameSession(world: ScreenshotScene.stationNames.make(in: language), language: language)
            session.railways = try railways()
            XCTAssertEqual(session.world.stations.map { session.stationSecondName(of: $0.id) }, seconds, "\(language)")
        }
    }
}
