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
        XCTAssertEqual(AttractionCatalog.spots.count, 214, "decision 250: 25 and 189 more")
        XCTAssertEqual(Set(AttractionCatalog.spots.map(\.kind)), Set(AttractionKind.allCases), "the hot springs are added")
        XCTAssertTrue(AttractionCatalog.spots.allSatisfy { (100...500).contains($0.stars) && $0.latitude > 21.5 && $0.latitude < 25.5 })
        XCTAssertEqual(ids.count, AttractionCatalog.spots.count, "each once")
        XCTAssertEqual(Set(AttractionCatalog.spots.map(\.name)).count, AttractionCatalog.spots.count)
        // Decision 250: the sights added stay below the alert bubbles'
        // rating, so the map asks for no more lines than before.
        let added = AttractionCatalog.spots.filter { $0.id.hasPrefix("t") }
        XCTAssertEqual(added.count, 189)
        XCTAssertTrue(added.allSatisfy { (200...350).contains($0.stars) && $0.stars < GameWorld.alertedSightStars })
        XCTAssertLessThanOrEqual(AttractionCatalog.spots.count, Tourism.maximumAttractions, "the whole of Taiwan holds them all")
    }

    /// Decision 250: a 16 km map round a county's main station has two to
    /// five sights or so (`tools/tourism-spots/coverage.py` counts them
    /// over the whole island).
    func testATownsMapHasSeveralSights() throws {
        let towns: [(String, Double, Double)] = [
            ("Keelung", 25.1319, 121.7387), ("Taoyuan", 24.9890, 121.3136), ("Hsinchu", 24.8016, 120.9716),
            ("Miaoli", 24.5700, 120.8224), ("Taichung", 24.1370, 120.6866), ("Changhua", 24.0817, 120.5383),
            ("Nantou", 23.9120, 120.6836), ("Douliu", 23.7116, 120.5414), ("Chiayi", 23.4790, 120.4410),
            ("Tainan", 22.9971, 120.2127), ("Kaohsiung", 22.6394, 120.3022), ("Pingtung", 22.6690, 120.4860),
            ("Yilan", 24.7546, 121.7584), ("Hualien", 23.9932, 121.6012), ("Taitung", 22.7932, 121.1235),
        ]
        var counts: [String: Int] = [:]
        for (town, latitude, longitude) in towns {
            let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: latitude, longitudeDegrees: longitude))
            let bounds = GameWorld.newGameBounds
            counts[town] = AttractionCatalog.attractions(in: RealWorldFrame(anchor: anchor, bounds: bounds), bounds: bounds).count
        }
        XCTAssertTrue(counts.values.allSatisfy { $0 >= 2 }, "\(counts)")
        XCTAssertGreaterThanOrEqual(counts.values.count { (2...5).contains($0) }, towns.count * 2 / 3, "\(counts)")
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

    /// Decision 250: no name twice on a map while its kind has one left.
    func testABlankMapsSightsHaveTheirOwnNames() throws {
        for seed in [UInt32(1), 7, 99, 12_345] {
            let sights = try XCTUnwrap(GameWorld.newGame(eventSeed: seed).tourism?.attractions)
            XCTAssertEqual(Set(sights.map(\.name)).count, sights.count, "seed \(seed)")
            XCTAssertEqual(Set(sights.map(\.englishName)).count, sights.count, "seed \(seed)")
        }
    }

    /// Decision 250: a blank map that buys its map (decision 160) has its
    /// sights over all its tiles, at most five a tile, and its middle tile
    /// the usual map's.
    func testABlankMapThatBuysItsMapHasSightsInEveryTile() throws {
        for seed in [UInt32(1), 7] {
            let world = GameWorld.newGame(eventSeed: seed, buysMap: true)
            let sights = try XCTUnwrap(world.tourism?.attractions, "seed \(seed)")
            let tile = MapExpansion.tileLength
            var perTile: [Int64: Int] = [:]
            for sight in sights {
                perTile[sight.point.y / tile * 5 + sight.point.x / tile, default: 0] += 1
            }
            XCTAssertEqual(perTile.count, 25, "every tile, seed \(seed): \(perTile)")
            XCTAssertTrue(perTile.values.allSatisfy { (1...5).contains($0) }, "seed \(seed): \(perTile)")
            XCTAssertLessThanOrEqual(sights.count, Tourism.maximumAttractions)
            for (index, one) in sights.enumerated() {
                for other in sights[(index + 1)...] {
                    let dx = one.point.x - other.point.x, dy = one.point.y - other.point.y
                    XCTAssertGreaterThanOrEqual(dx * dx + dy * dy, 192_000 * 192_000)
                }
            }
            // Each kind's sixteen names are all used before one comes again.
            for kind in AttractionKind.allCases {
                let names = sights.filter { $0.kind == kind }.map(\.name)
                XCTAssertEqual(Set(names).count, min(names.count, 16), "seed \(seed), \(kind)")
            }
            // The middle tile first, where the usual map's are.
            let usual = try XCTUnwrap(GameWorld.newGame(eventSeed: seed).tourism?.attractions)
            let middle = sights.prefix(usual.count)
            XCTAssertEqual(middle.map { PlanPoint(x: $0.point.x - 2 * tile, y: $0.point.y - 2 * tile) }, usual.map(\.point), "seed \(seed)")
            XCTAssertEqual(middle.map(\.kind), usual.map(\.kind))
            XCTAssertEqual(middle.map(\.baseStars), usual.map(\.baseStars))
        }
    }

    /// Decision 250: a mark gives way to a better-rated one it would lie on.
    func testTheMapsSightMarksGiveWay() {
        func mark(_ id: Int, _ stars: Int, _ x: Double, _ y: Double) -> SightMarks.Mark {
            SightMarks.Mark(id: AttractionID(rawValue: id), stars: stars, x: x, y: y)
        }
        let shown = SightMarks.shown([
            mark(1, 250, 100, 100), mark(2, 350, 120, 110), mark(3, 250, 300, 100),
            mark(4, 250, 330, 105), mark(5, 300, 100, 200), mark(6, 300, 100, 230),
        ])
        XCTAssertEqual(shown, Set([2, 3, 5, 6].map { AttractionID(rawValue: $0) }), "1 under 2; 4 under 3, the lower number; 5 and 6 a mark apart")
        XCTAssertEqual(SightMarks.shown([]), [])
    }

    /// Decision 250, later: the sight marks take touches with the Select
    /// tool, but not while a tile to buy is chosen (a tap there chooses
    /// the tile, and a map bought tile by tile has sights in every tile),
    /// nor while building.
    func testTheSightMarksGiveWayToChoosingATile() {
        let session = GameSession(world: GameWorld.newGame(eventSeed: 1, buysMap: true))
        XCTAssertTrue(session.sightMarksTakeTouches)
        session.startChoosingMapTile()
        XCTAssertTrue(session.isChoosingMapTile)
        XCTAssertFalse(session.sightMarksTakeTouches, "a tap chooses the tile")
        session.stopChoosingMapTile()
        XCTAssertTrue(session.sightMarksTakeTouches)
        session.selectTool(.network)
        XCTAssertFalse(session.sightMarksTakeTouches, "building")
    }

    /// Decision 250 (a player's report): the panel opened from a sight's
    /// mark goes to that sight's row; from the menu, or for a sight gone,
    /// to none.
    func testTheSightsPanelOpensAtTheSightTapped() throws {
        let world = GameWorld.newGame(eventSeed: 7)
        let rows = world.attractionRows(in: .english)
        let last = try XCTUnwrap(rows.last?.id)
        XCTAssertEqual(SightFocus.row(for: last, in: rows), last)
        XCTAssertEqual(SightFocus.row(for: rows[0].id, in: rows), rows[0].id)
        XCTAssertNil(SightFocus.row(for: nil, in: rows), "from the menu: the top")
        XCTAssertNil(SightFocus.row(for: AttractionID(rawValue: 999), in: rows), "a sight no longer listed")
        XCTAssertGreaterThan(SightFocus.highlightSeconds, 0)
    }

    func testARealWorldMapHasTaiwansSightsInItsBounds() throws {
        let jiufen = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.10873, longitudeDegrees: 121.84357))
        let world = GameWorld.newGame(anchor: jiufen, land: [])
        let sights = try XCTUnwrap(world.tourism?.attractions)
        XCTAssertEqual(sights.map(\.name), ["九份", "平溪天燈", "猴硐貓村", "鼻頭角", "和平島", "正濱漁港", "八斗子潮境"],
                       "Jiufen at the middle, Pingxi 9 km south west and decision 250's round Keelung, inside the 16 km square, in the catalog's order")
        // At the middle of the map, which is where the anchor is.
        XCTAssertEqual(Double(sights[0].point.x), Double(world.bounds.width) / 2, accuracy: 64)
        XCTAssertEqual(Double(sights[0].point.y), Double(world.bounds.height) / 2, accuracy: 64)
        XCTAssertEqual(sights[0].baseStars, 400)
        XCTAssertEqual(sights[0].kind, .town)

        let whole = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, land: [])
        XCTAssertEqual(whole.tourism?.attractions.count, AttractionCatalog.spots.count, "all of them on the whole of Taiwan")
        // And on a map of the island bought tile by tile (decision 167).
        let taichung = try XCTUnwrap(GeoAnchor(latitudeDegrees: 24.1370, longitudeDegrees: 120.6866))
        let expansion = try XCTUnwrap(RealWorldExpansion(around: taichung))
        XCTAssertEqual(GameWorld.newRealWorldExpansionGame(expansion, ridersStep: 1).tourism?.attractions.count, AttractionCatalog.spots.count)

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
        // Decision 183: the city's offers would be said first.
        world.setCityRequests(seed: nil)
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

    /// Decision 286: a sightseeing train calling at Foot shows on the row and
    /// in its stars; the help names the sightseeing trains.
    func testThePanelSaysASightseeingTrainCalls() throws {
        var world = try world()
        XCTAssertNil(world.attractionRows(in: .english)[0].sightseeingTrainText)
        let line = try XCTUnwrap(world.lines.first).id
        let blue = try world.purchaseTrain(named: "Blue").id
        try world.setTrainType(blue, to: .blueTrain)
        try world.assignTrain(blue, to: line)
        let row = world.attractionRows(in: .english)[0]
        XCTAssertEqual(row.starsText, "4★")
        XCTAssertEqual(row.sightseeingTrainText, "A sightseeing train calls here (+0.5★)")
        XCTAssertEqual(world.attractionRows(in: .traditionalChinese)[0].sightseeingTrainText, "有觀光列車停靠（+0.5★）")
        XCTAssertTrue(world.tourismHelp(in: .english).hasSuffix(
            "A sightseeing train (Hai-Feng sightseeing train, Blue Train sightseeing train, Shan-Lan sightseeing train) calling at a station within 800 m adds 0.5 stars; the Formosa Star sightseeing train adds 0.75 stars; the Ming-Ri sightseeing train adds 1 star."
        ), world.tourismHelp(in: .english))
        XCTAssertTrue(world.tourismHelp(in: .traditionalChinese).hasSuffix("觀光列車（海風號、藍皮解憂號、山嵐號）停靠 800 公尺內的車站時，景點加 0.5 星；環島之星加 0.75 星；鳴日號加 1 星。"))
        // The train catalog's note: only under a sightseeing type, only with sights.
        XCTAssertEqual(world.sightseeingNote(for: .blueTrain, in: .traditionalChinese), "觀光列車：停靠景點 800 公尺內的車站時，景點加 0.5 星，觀光客會變多。")
        XCTAssertEqual(world.sightseeingNote(for: .haiFeng, in: .english),
                       "Sightseeing train: calling at a station within 800 m of a sight adds 0.5 stars to it, so more tourists come.")
        XCTAssertEqual(world.sightseeingNote(for: .shanLan, in: .english), world.sightseeingNote(for: .haiFeng, in: .english))
        // Decision 286, later: the Ming-Ri adds a whole star, and the panel
        // says what the train calling there adds.
        XCTAssertEqual(world.sightseeingNote(for: .mingRi, in: .english),
                       "Sightseeing train: calling at a station within 800 m of a sight adds 1 star to it, so more tourists come.")
        XCTAssertEqual(world.sightseeingNote(for: .mingRi, in: .traditionalChinese), "觀光列車：停靠景點 800 公尺內的車站時，景點加 1 星，觀光客會變多。")
        // Decision 286, later (third): the Formosa Star adds three quarters.
        XCTAssertEqual(world.sightseeingNote(for: .formosaStar, in: .english),
                       "Sightseeing train: calling at a station within 800 m of a sight adds 0.75 stars to it, so more tourists come.")
        XCTAssertEqual(world.sightseeingNote(for: .formosaStar, in: .traditionalChinese), "觀光列車：停靠景點 800 公尺內的車站時，景點加 0.75 星，觀光客會變多。")
        let star = try world.purchaseTrain(named: "Formosa Star").id
        try world.setTrainType(star, to: .formosaStar)
        try world.assignTrain(star, to: line)
        XCTAssertEqual(world.attractionRows(in: .english)[0].sightseeingTrainText, "A sightseeing train calls here (+0.75★)")
        XCTAssertEqual(world.attractionRows(in: .english)[0].starsText, "4.25★")
        let mingRi = try world.purchaseTrain(named: "Ming-Ri").id
        try world.setTrainType(mingRi, to: .mingRi)
        try world.assignTrain(mingRi, to: line)
        XCTAssertEqual(world.attractionRows(in: .english)[0].sightseeingTrainText, "A sightseeing train calls here (+1★)")
        XCTAssertEqual(world.attractionRows(in: .english)[0].starsText, "4.5★", "the Ming-Ri's star, not the others' as well")
        XCTAssertNil(world.sightseeingNote(for: .r100ChuKuang, in: .english))
        XCTAssertNil(world.sightseeingNote(for: nil, in: .english))
        world.setTourism(nil)
        XCTAssertNil(world.sightseeingNote(for: .blueTrain, in: .english), "no sights, nothing to say")
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

    /// A souvenir shop raises the sight's rating and so its tourists: the
    /// station panel and the travel layer work their day out again.
    func testTheRidershipInputsSeeASouvenirShop() throws {
        var world = try world()
        let before = RidershipInputs(world: world)
        try world.investInSouvenirShop(of: AttractionID(rawValue: 1))
        XCTAssertNotEqual(RidershipInputs(world: world), before)
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
        // The Spring Festival starts on day 44; on day 42 it is two days off
        // (and on the game's first day, New Year's Day, nothing is said).
        world.setDisruptions(Disruptions(level: .light, country: "TW"))
        if case .touristsComing? = StationMasterAdvice(world: world) { XCTFail("not on the first day") }
        // The days pass without the sight, so that no queue fills meanwhile.
        let sights = world.tourism?.attractions
        world.setTourism(nil)
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 1))
        world.setSpeed(.normal)
        try world.advance(ticks: 42 * 1_440)
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

extension TourismSessionTests {
    /// Decision 174: tourists are announced for a holiday that starts today
    /// or in the next three days, not every day of one already under way,
    /// which would keep the station master from saying anything else.
    func testTheTouristsAreNotAnnouncedAgainEachDayOfAHoliday() throws {
        var world = try world()
        world.setDisruptions(Disruptions(level: .light, country: "TW"))
        let sights = world.tourism?.attractions
        world.setTourism(nil)
        try world.setStationDemand(StationID(rawValue: 1), to: StationDemand(kind: .residential, dailyTrips: 1))
        world.setSpeed(.normal)
        // The Spring Festival runs 7 days from day 44: day 47 is its fourth.
        try world.advance(ticks: 47 * 1_440)
        world.setTourism(sights)
        XCTAssertEqual(world.holidays(from: 47, through: 47).first?.start, 44)
        if case .touristsComing? = StationMasterAdvice(world: world) { XCTFail("the holiday began three days ago") }
    }
}
