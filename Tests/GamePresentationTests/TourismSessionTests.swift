import Foundation
import GameCore
import GamePresentation
import XCTest

/// Tourism where the app meets it (ARCHITECTURE decision 174): a new game's
/// sights, the worlds measured without them, the panel's rows, the station
/// master's two new things to say and the souvenir shop's button.
@MainActor
final class TourismSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("TourismSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - The catalog

    /// The Swift table is the tool's output, row for row.
    func testTheCatalogIsTheToolsFile() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/tourism-spots/taiwan_attractions.json")
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(object["attractions"] as? [[String: Any]])
        XCTAssertEqual(rows.count, AttractionCatalog.spots.count)
        for (row, spot) in zip(rows, AttractionCatalog.spots) {
            XCTAssertEqual(row["id"] as? String, spot.id)
            XCTAssertEqual(row["name"] as? String, spot.name, spot.id)
            XCTAssertEqual(row["englishName"] as? String, spot.englishName, spot.id)
            XCTAssertEqual(row["kind"] as? String, spot.kind.rawValue, spot.id)
            XCTAssertEqual(row["stars"] as? Int, spot.stars, spot.id)
            XCTAssertEqual(try XCTUnwrap(row["lat"] as? Double), spot.latitude, accuracy: 1e-9, spot.id)
            XCTAssertEqual(try XCTUnwrap(row["lon"] as? Double), spot.longitude, accuracy: 1e-9, spot.id)
        }
    }

    func testTheCatalogKeepsToWhatARailwayReaches() {
        let ids = Set(AttractionCatalog.spots.map(\.id))
        // The offshore islands and the two invented places of OpenWorld's
        // catalog are left out.
        for skipped in ["s03", "s05", "s10", "s13", "s14", "s19", "s22", "s24"] {
            XCTAssertFalse(ids.contains(skipped), skipped)
        }
        XCTAssertEqual(AttractionCatalog.spots.count, 25)
        XCTAssertEqual(Set(AttractionCatalog.spots.map(\.kind)), Set(AttractionKind.allCases), "the hot springs are added")
        XCTAssertTrue(AttractionCatalog.spots.allSatisfy { (100...500).contains($0.stars) && $0.latitude > 21.5 && $0.latitude < 25.5 })
    }

    // MARK: - New games

    func testABlankMapsNewGameHasThreeToFiveSights() throws {
        for seed in [UInt32(1), 7, 99, 12_345] {
            let world = GameWorld.newGame(eventSeed: seed)
            let sights = try XCTUnwrap(world.tourism?.attractions, "seed \(seed)")
            XCTAssertTrue((3...5).contains(sights.count), "seed \(seed): \(sights.count)")
            XCTAssertEqual(sights.map(\.id.rawValue), Array(1...sights.count))
            XCTAssertTrue(sights.allSatisfy { $0.point.x >= 0 && $0.point.x < world.bounds.width && $0.point.y >= 0 && $0.point.y < world.bounds.height })
            XCTAssertTrue(sights.allSatisfy { (200...400).contains($0.baseStars) })
            // The same seed draws the same sights.
            XCTAssertEqual(GameWorld.newGame(eventSeed: seed).tourism, world.tourism)
            // 3 km apart at least.
            for (index, one) in sights.enumerated() {
                for other in sights[(index + 1)...] {
                    let dx = one.point.x - other.point.x, dy = one.point.y - other.point.y
                    XCTAssertGreaterThanOrEqual(dx * dx + dy * dy, 192_000 * 192_000)
                }
            }
        }
        XCTAssertNotEqual(GameWorld.newGame(eventSeed: 1).tourism, GameWorld.newGame(eventSeed: 2).tourism)
    }

    func testARealWorldMapHasTaiwansSightsInItsBounds() throws {
        let jiufen = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.10873, longitudeDegrees: 121.84357))
        let world = GameWorld.newGame(anchor: jiufen, land: [])
        let sights = try XCTUnwrap(world.tourism?.attractions)
        XCTAssertEqual(sights.map(\.name), ["九份", "平溪天燈"], "Jiufen at the middle and Pingxi 9 km south west, inside the 16 km square")
        // At the middle of the map, which is where the anchor is.
        XCTAssertEqual(Double(sights[0].point.x), Double(world.bounds.width) / 2, accuracy: 64)
        XCTAssertEqual(Double(sights[0].point.y), Double(world.bounds.height) / 2, accuracy: 64)
        XCTAssertEqual(sights[0].baseStars, 400)
        XCTAssertEqual(sights[0].kind, .town)

        let whole = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, land: [])
        XCTAssertEqual(whole.tourism?.attractions.count, AttractionCatalog.spots.count, "all of them on the whole of Taiwan")

        let tokyo = try XCTUnwrap(GeoAnchor(latitudeDegrees: 35.68, longitudeDegrees: 139.76))
        XCTAssertNil(GameWorld.newGame(anchor: tokyo, land: []).tourism, "none away from Taiwan")
    }

    func testTheAppsNewGameHasSights() {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.hasTourism, true)
    }

    /// The measured worlds keep tourism off, as they keep door crowding off.
    func testTheMeasuredWorldsKeepItOff() {
        XCTAssertNil(DemoWorld.make(in: .english).tourism)
        for challenge in Challenge.sandbox {
            XCTAssertNil(GameWorld.newGame(challenge: challenge, eventSeed: 7).tourism, challenge.id)
        }
        XCTAssertNil(LiuMingchuanChallenge.make().tourism)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertNil(launcher.session?.world.tourism)
    }

    // MARK: - The panel

    /// Home and Foot with a train by the map's edge (outside connections),
    /// and a 3.5-star sight 15.6 m from Foot.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 7)
        world.setTourism(nil)
        world.setLandDemand(false)
        world.setPassengerRoutingMode(.direct)
        world.setDistanceDemand(false)
        world.setOutsideConnections(true)
        let home = try world.buildStation(named: "Home", at: PlanPoint(x: 20_000, y: 500_000)).id
        let foot = try world.buildStation(named: "Foot", at: PlanPoint(x: 26_000, y: 500_000)).id
        let line = try world.createLine(named: "Main", stops: [home, foot]).id
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_000))
        try world.setStationDemand(foot, to: StationDemand(kind: .scenic, dailyTrips: 0))
        world.setTourism([Attraction(id: AttractionID(rawValue: 1), name: "老街", englishName: "Old Street",
                                     point: PlanPoint(x: 27_000, y: 500_000), kind: .town, baseStars: 350)])
        return world
    }

    func testThePanelListsTheSightsWithTheirNumbers() throws {
        let world = try world()
        let rows = world.attractionRows(in: .english)
        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.name, "Old Street")
        XCTAssertEqual(row.kind, "Old town")
        XCTAssertEqual(row.starsText, "3.5★")
        XCTAssertEqual(row.stationName, "Foot")
        XCTAssertEqual(row.status, .ok)
        XCTAssertEqual(row.souvenir, 0)
        let offer = try XCTUnwrap(row.nextShop)
        XCTAssertEqual(offer.cost, Money(30_000_000))
        XCTAssertTrue(offer.preview.contains("3.5★ → 3.75★"), offer.preview)
        XCTAssertEqual(world.attractionRows(in: .traditionalChinese)[0].name, "老街")
        XCTAssertTrue(world.attractionRows(in: .traditionalChinese)[0].nextShop?.preview.contains("名產店") ?? false)
        XCTAssertEqual(StationMasterAdvice.starsText(325), "3.25★")
        XCTAssertEqual(StationMasterAdvice.starsText(400), "4★")
        XCTAssertEqual(StationMasterAdvice.starsText(450), "4.5★")
        XCTAssertEqual(StationMasterAdvice.starsText(305), "3.05★")
    }

    func testTheShopButtonBuysTheNextLevelAndSaysSo() throws {
        let session = GameSession(world: try world())
        let before = session.world.economy.balance
        session.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.attraction(id: AttractionID(rawValue: 1))?.souvenir, 1)
        XCTAssertEqual(before - session.world.economy.balance, Money(30_000_000))
        session.investInSouvenirShop(of: AttractionID(rawValue: 1))
        session.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertEqual(session.message?.kind, .failure, "a third level is refused")
        XCTAssertEqual(session.world.attraction(id: AttractionID(rawValue: 1))?.souvenir, 2)
        XCTAssertNil(session.world.attractionRows(in: .english)[0].nextShop)
    }

    // MARK: - The station master

    func testTheStationMasterSaysASightHasNoStation() throws {
        var world = try world()
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "九份", englishName: "Jiufen", point: PlanPoint(x: 86_000, y: 500_000),
                       kind: .town, baseStars: 400),
        ])
        // 60,000 units (940 m) from Foot: within 5 km, but not 800 m.
        let advice = try XCTUnwrap(StationMasterAdvice(world: world))
        guard case .sightUnreachable(_, let english, let chinese, let stars, let status) = advice else {
            return XCTFail("\(advice)")
        }
        XCTAssertEqual([english, chinese, status], ["Jiufen", "九份", AttractionStatus.noStation] as [AnyHashable])
        XCTAssertEqual(stars, 400)
        XCTAssertEqual(advice.text(in: .traditionalChinese), "九份 4★ 沒有車站可到。在 800 公尺內蓋車站，再開一條線過去吧。")
        XCTAssertTrue(advice.text(in: .english).hasPrefix("Jiufen 4★ has no station to reach it."))
    }

    func testTheStationMasterWarnsOfTouristsBeforeAHoliday() throws {
        var world = try world()
        // The Spring Festival starts on day 43; on day 41 it is two days off
        // (and on the game's first day, New Year's Day, nothing is said).
        world.setDisruptions(Disruptions(level: .light, country: "TW"))
        if case .touristsComing? = StationMasterAdvice(world: world) { XCTFail("not on the first day") }
        // The days pass without the sight, so that no queue fills meanwhile.
        let sights = world.tourism?.attractions
        world.setTourism(nil)
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 1))
        world.setSpeed(.normal)
        try world.advance(ticks: 41 * 1_440)
        world.setTourism(sights)
        let advice = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(advice, .touristsComing(kind: .springFestival, days: 2, times: 2))
        XCTAssertTrue(advice.text(in: .english).contains("×2 tourists"), advice.text(in: .english))
        XCTAssertTrue(advice.text(in: .traditionalChinese).contains("觀光客約 ×2"), advice.text(in: .traditionalChinese))
        XCTAssertFalse(advice.isWorry)
        // Without a sight tourists can reach, only the ordinary holiday words.
        var elsewhere = world
        elsewhere.setTourism(nil)
        if case .touristsComing? = StationMasterAdvice(world: elsewhere) { XCTFail("no sights, no tourists") }
    }
}
