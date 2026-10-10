import GameCore
import GamePresentation
import XCTest

/// City building P0-A (ARCHITECTURE decision 92): the building tool places
/// the chosen building where the player taps, as an edit Undo takes back,
/// and says what happened. P0-C1 (decision 94): a managed company pays for
/// it and can demolish it. P0-C2 (decision 95): a tap chooses the site, the
/// preview shows what it costs and pulls down, and the action button builds.
@MainActor
final class BuildingSessionTests: XCTestCase {
    func testPlacingTheChosenBuildingAndUndoingIt() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .english)
        session.selectTool(.building)
        XCTAssertEqual(session.buildingKind, .house, "a house to begin with")
        XCTAssertEqual(session.placedBuildingsText, "0 buildings placed")

        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000)))
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.house])
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built house #1."))
        XCTAssertEqual(session.placedBuildingsText, "1 building placed")

        session.buildingKind = .office
        XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 10_000, y: 10_000)))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built office block #2."))
        XCTAssertEqual(session.placedBuildingsText, "2 buildings placed")

        // GameCore refuses ground already built on, and nothing changes.
        let before = session.world
        XCTAssertFalse(session.placeBuilding(at: PlanPoint(x: 5_500, y: 5_000)))
        XCTAssertEqual(session.world, before)
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "That would stand on building #1."))

        session.undo()
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.house])
        session.undo()
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
    }

    func testTheBuildingToolReadsInChinese() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .traditionalChinese)
        XCTAssertEqual(PlacedBuildingKind.allCases.map { $0.title(in: .traditionalChinese) }, ["小住宅", "商店", "辦公樓", "漁人碼頭", "遊艇港"])
        XCTAssertEqual(PlacedBuildingKind.allCases.map { $0.title(in: .english) }, ["House", "Shop", "Office block", "Wharf", "Marina"])
        session.buildingKind = .shop
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "蓋好商店 #1。"))
        XCTAssertEqual(session.placedBuildingsText, "已蓋 1 棟")
        session.placeBuilding(at: PlanPoint(x: 100, y: 5_000))
        XCTAssertEqual(session.message?.kind, .failure)
    }

    func testAManagedCompanyIsToldWhatItPaysAndCanDemolish() throws {
        var world = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        XCTAssertEqual(session.buildingMode, .build)
        // A house: 512 m² of floor at $40, and 256 m² of empty land at
        // $10 a m² (its base value).
        XCTAssertEqual(session.buildingQuoteText, "House: $ 20,480 to build, plus the land's value for 256 m²")
        XCTAssertNil(session.buildingEconomyText, "nothing built yet")

        // Decision 95: a tap chooses the site and shows what it costs; the
        // action button builds there.
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 500))
        XCTAssertTrue(session.world.placedBuildings.isEmpty, "a tap only chooses the site")
        XCTAssertEqual(session.buildingPreview?.cost, 2_304_000)
        XCTAssertEqual(session.buildingPreviewText, "Building $ 20,480 + land $ 2,560")
        XCTAssertTrue(session.confirmBuilding())
        XCTAssertNil(session.buildingSite, "built: the site is cleared")
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built house #1 for $ 23,040."))
        XCTAssertEqual(session.world.economy.balance, 100_000_000 - 2_304_000)
        // Empty, so no rent; upkeep 2 bp of 2,048,000 is 410 cents, tax
        // 1 bp of 256,000 is 26.
        XCTAssertEqual(session.buildingEconomyText, "Rent $ 0.00 a day · upkeep and land tax $ 4.36")

        // Demolishing: a tap on it or within reach of it (the house is
        // 1,024 units across, so it ends at 5,512); a tenth of what it cost.
        session.buildingMode = .demolish
        let before = session.world
        XCTAssertFalse(session.tapBuildingTool(at: PlanPoint(x: 9_000, y: 9_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap one of your buildings to demolish it."))
        XCTAssertEqual(session.world, before)
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_900, y: 5_000), reach: 500))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Demolished house #1 for $ 2,304."))
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        XCTAssertEqual(session.world.economy.balance, 100_000_000 - 2_304_000 - 230_400)
        XCTAssertNil(session.buildingEconomyText)

        session.undo()
        XCTAssertEqual(session.world, before, "Undo puts it back")
        XCTAssertFalse(session.demolishBuilding(PlacedBuildingID(rawValue: 9)))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "There is no building #9."))
    }

    func testDemolishingInFreePlayIsFreeAndReadsInChinese() throws {
        let session = GameSession(world: try makeWorld(width: 20_480, height: 20_480), language: .traditionalChinese)
        XCTAssertEqual(BuildingToolMode.allCases.map { $0.title(in: .traditionalChinese) }, ["建造", "拆除", "出售", "分區"])
        XCTAssertNil(session.buildingQuoteText, "free play builds for nothing")
        session.placeBuilding(at: PlanPoint(x: 5_000, y: 5_000))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "蓋好小住宅 #1。"))
        XCTAssertNil(session.buildingEconomyText)
        session.buildingMode = .demolish
        XCTAssertFalse(session.tapBuildingTool(at: PlanPoint(x: 15_000, y: 15_000), reach: 0))
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "請點選要拆除的建物。"))
        XCTAssertTrue(session.tapBuildingTool(at: PlanPoint(x: 5_000, y: 5_000), reach: 0))
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "拆除小住宅 #1。"))
        XCTAssertEqual(session.world.economy.balance, 10_000, "free")
    }

    /// Decision 140: a real-world map has a city building on nearly every
    /// cell, so the building tool draws only those round the chosen site,
    /// not every one in view, and still marks those it would buy out.
    func testARealWorldMapDrawsOnlyTheCityBuildingsRoundTheSite() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 3)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setGeoAnchor(try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.1316, longitudeDegrees: 121.7397)))
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        XCTAssertEqual(session.buildingOverlay?.showsCityBuildingSites, false, "none before a site is chosen")
        session.tapBuildingTool(at: PlanPoint(x: 22_528, y: 22_528), reach: 0)
        let overlay = try XCTUnwrap(session.buildingOverlay)
        XCTAssertTrue(overlay.showsCityBuildingSites)
        let reach = GameSession.citySitesReach
        XCTAssertEqual(overlay.citySitesArea, PlanRect(minX: 21_504 - reach, minY: 21_504 - reach, maxX: 23_552 + reach, maxY: 23_552 + reach))
        XCTAssertEqual(overlay.boughtOut, [PlanRect(minX: 21_248, minY: 21_248, maxX: 23_808, maxY: 23_808)])
    }

    /// Decision 142: a new game's city buildings stand on squares of their
    /// density's size, and the building tool marks the one it buys out at
    /// that size.
    func testANewGameMarksTheSquareOfTheDensityABuildingBuysOut() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        XCTAssertTrue(GameWorld.newGame().cityFootprints, "a new game has them")
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        session.tapBuildingTool(at: PlanPoint(x: 22_528, y: 22_528), reach: 0)
        // A D1's 20 m square: 20,480 + 1,408 to 20,480 + 2,688.
        XCTAssertEqual(session.buildingOverlay?.boughtOut, [PlanRect(minX: 21_888, minY: 21_888, maxX: 23_168, maxY: 23_168)])
        XCTAssertEqual(PlanRect.cityBuilding(row: 5, column: 5, in: session.world), PlanRect(minX: 21_888, minY: 21_888, maxX: 23_168, maxY: 23_168))
    }

    /// Decision 144: a site that would buy out a city building moves to the
    /// nearest point within 12 m where it buys out none, on a tap and when
    /// a drag lets go; one on top of a city building stays and buys it out.
    func testASiteAtACityBuildingsEdgeMovesIntoTheGapBesideIt() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        // The D1 home's 20 m square ends at 23,168; an office clears it
        // from a centre of 23,168 + 128 + 1,024 = 24,320. Tapped 300 short,
        // it moves 320 east, the nearest half metre that clears it.
        session.tapBuildingTool(at: PlanPoint(x: 24_020, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 24_340, y: 22_528))
        XCTAssertEqual(session.buildingPreview?.quote.cleared, [])
        XCTAssertNil(session.buildingPreview?.problem)

        // On top of the home it is more than 12 m from any gap: it stays,
        // and buys the home out.
        session.tapBuildingTool(at: PlanPoint(x: 22_528, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 22_528, y: 22_528))
        XCTAssertEqual(session.buildingPreview?.quote.cleared, [CellPosition(row: 5, column: 5)])

        // Dragged to the home's west edge and let go: it moves into the gap.
        session.dragBuildingSite(from: PlanPoint(x: 22_528, y: 22_528), to: PlanPoint(x: 21_000, y: 22_528))
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 21_000, y: 22_528), "it follows the finger")
        session.endBuildingDrag(from: PlanPoint(x: 22_528, y: 22_528), to: PlanPoint(x: 21_000, y: 22_528))
        // The office clears the square west of 21,888 − 128 − 1,024 = 20,736.
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 20_712, y: 22_528))
        XCTAssertEqual(session.buildingPreview?.quote.cleared, [])

        // A site that buys out nothing does not move.
        session.tapBuildingTool(at: PlanPoint(x: 60_000, y: 60_000), reach: 0)
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 60_000, y: 60_000))
    }

    /// Decision 144: a point GameCore refuses, where another of the
    /// company's buildings stands, is passed over; with no other within
    /// reach the site stays where it was put and buys the home out.
    func testASiteDoesNotMoveOntoAnotherOfTheCompanysBuildings() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 4, jobs: 0)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        // A house in the gap east of the home, 25,200 to 26,224: clear of an
        // office at 24,020 (to 25,044), in the way of one at 24,320 or east.
        _ = try world.placeBuilding(.house, at: PlanPoint(x: 25_712, y: 22_528))
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        session.tapBuildingTool(at: PlanPoint(x: 24_020, y: 22_528), reach: 0)
        // East of 24,320 the office would stand on the house; north or
        // south it would have to move 28 m to clear the home.
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 24_020, y: 22_528))
        XCTAssertEqual(session.buildingPreview?.quote.cleared, [CellPosition(row: 5, column: 5)])
        XCTAssertNil(session.buildingPreview?.problem)
    }

    /// Decision 146: a real-world new game buys out by area; a blank one by
    /// squares. Buying out by area, the site does not snap, no square is
    /// marked or drawn, and the preview names the share it buys out.
    func testBuyingOutByAreaNeitherSnapsNorMarksSquares() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.1316, longitudeDegrees: 121.7397))
        XCTAssertTrue(GameWorld.newGame(anchor: anchor).areaBuyOut, "a real-world new game buys out by area")
        XCTAssertFalse(GameWorld.newGame().areaBuyOut, "a blank one by squares")

        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 48, jobs: 8)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        world.setCityFootprints(true)
        world.setAreaBuyOut(true)
        world.setGeoAnchor(anchor)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        // By squares this site would move 320 east into the gap (decision
        // 144); by area it stays.
        session.tapBuildingTool(at: PlanPoint(x: 24_020, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingSite, PlanPoint(x: 24_020, y: 22_528))
        let quote = try XCTUnwrap(session.buildingPreview?.quote)
        XCTAssertEqual(quote.cleared, [])
        // The office runs from 22,996 to 25,044 across and 21,504 to 23,552
        // down: 1,580 × 2,048 units of cell (5, 5), which ends at 24,576.
        let covered: Int64 = (24_576 - (24_020 - 1_024)) * 2_048
        XCTAssertEqual(quote.buyOut, Money(15_705_600 * covered / Land.cellArea))
        XCTAssertEqual(session.buildingOverlay?.boughtOut, [])
        XCTAssertEqual(session.buildingOverlay?.showsCityBuildingSites, false)
        XCTAssertEqual(session.buildingPreviewText?.contains("buying out the city's floor under it \(quote.buyOut.moneyText)"), true)
        XCTAssertEqual(session.buildingPreviewText?.contains("city building"), false)
    }

    /// Buying out by area, a share of each covered cell's people move into
    /// the building, in free play as when managed: the preview says how
    /// many, and so does the message once it stands.
    func testBuyingOutByAreaSaysWhoMovesIn() throws {
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: 25.1316, longitudeDegrees: 121.7397))
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 48, jobs: 8)])
        world.setCityBuildings(true)
        world.setCityFootprints(true)
        world.setAreaBuyOut(true)
        world.setGeoAnchor(anchor)
        XCTAssertEqual(world.accounts.mode, .free)
        // 1,580 × 2,048 units of cell (5, 5): 9 of its 48 residents and 1
        // of its 8 jobs, rounded down.
        let covered: Int64 = (24_576 - (24_020 - 1_024)) * 2_048
        let residents = 48 * covered / Land.cellArea, jobs = 8 * covered / Land.cellArea
        XCTAssertEqual([residents, jobs], [9, 1])
        for mode in [EconomyMode.free, .management] {
            var copy = world
            copy.setEconomyMode(mode)
            let session = GameSession(world: copy, language: .english)
            session.selectTool(.building)
            session.buildingKind = .office
            session.tapBuildingTool(at: PlanPoint(x: 24_020, y: 22_528), reach: 0)
            XCTAssertEqual(session.buildingPreviewText?.contains("9 residents and 1 job move in"), true, "\(mode): \(session.buildingPreviewText ?? "nil")")
            XCTAssertTrue(session.placeBuilding(at: PlanPoint(x: 24_020, y: 22_528)))
            XCTAssertEqual(session.message?.text.contains("9 residents and 1 job moving in"), true, "\(mode): \(session.message?.text ?? "nil")")
        }
    }

    func testThePreviewShowsTheCityBuildingsABuildingBuysOut() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 3)])
        world.setCityBuildings(true)
        world.setEconomyMode(.management)
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .office
        XCTAssertNil(session.buildingOverlay?.site)
        XCTAssertEqual(session.buildingOverlay?.showsCityBuildingSites, true)
        XCTAssertNil(session.buildingOverlay?.citySitesArea, "a blank map draws every one in view")

        // An office on the middle of the D4 home's cell buys it out (the
        // numbers of CompanyBuildingsClearingTests).
        session.tapBuildingTool(at: PlanPoint(x: 22_528, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingPreviewText, "Building $ 245,760 + land $ 40,960, buying out 1 city building $ 3,025,920")
        let overlay = try XCTUnwrap(session.buildingOverlay)
        XCTAssertEqual(overlay.site, PlanRect(minX: 21_504, minY: 21_504, maxX: 23_552, maxY: 23_552))
        XCTAssertTrue(overlay.siteIsBuildable)
        XCTAssertEqual(overlay.boughtOut, [PlanRect(minX: 21_248, minY: 21_248, maxX: 23_808, maxY: 23_808)])
        XCTAssertTrue(session.confirmBuilding())
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Built office block #1 for $ 3,312,640, pulling down 1 city building."))
        XCTAssertNil(session.world.land.cell(row: 5, column: 5))

        // A site where it cannot stand says why, and cannot be built.
        session.tapBuildingTool(at: PlanPoint(x: 22_600, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingPreviewText, "That would stand on building #1.")
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, false)
        XCTAssertNil(session.buildingPreview?.cost)

        // Changing mode or tool forgets the site.
        session.buildingMode = .demolish
        XCTAssertNil(session.buildingSite)
        session.buildingMode = .build
        XCTAssertFalse(session.confirmBuilding())
        XCTAssertEqual(session.message, StatusMessage(kind: .failure, text: "Tap the map where it goes first."))
    }

    /// Decision 105: a site on water says so, in both languages, and
    /// cannot be built; zoning only water is refused alike.
    func testASiteOnWaterSaysSo() throws {
        var world = try makeWorld(width: 131_072, height: 98_304, balance: 1_000_000_000)
        try world.setWater((0...4).flatMap { row in (0...31).map { CellPosition(row: row, column: $0) } })
        let session = GameSession(world: world, language: .english)
        session.selectTool(.building)
        session.buildingKind = .house
        session.tapBuildingTool(at: PlanPoint(x: 10_240, y: 10_240), reach: 0)
        XCTAssertEqual(session.buildingPreviewText, "Nothing can be built or zoned on water.")
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, false)
        XCTAssertFalse(session.confirmBuilding())
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
        XCTAssertEqual(GameError.onWater(row: 2, column: 2).playerMessage(in: .traditionalChinese), "水上不能蓋建物，也不能劃分區。")
        // On the shore, it can.
        session.tapBuildingTool(at: PlanPoint(x: 10_240, y: 21_000), reach: 0)
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, true)

        // A marina goes on the shore, part over the water (decision 111).
        session.buildingKind = .marina
        session.tapBuildingTool(at: PlanPoint(x: 10_240, y: 30_720), reach: 0)
        XCTAssertEqual(session.buildingPreviewText, "A wharf or a marina goes on the shore, part over the water.")
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, false)
        XCTAssertEqual(GameError.needsShore.playerMessage(in: .traditionalChinese), "漁人碼頭與遊艇港要蓋在岸邊，一部分在水上。")
        session.tapBuildingTool(at: PlanPoint(x: 10_240, y: 20_480), reach: 0)
        XCTAssertEqual(session.buildingOverlay?.siteIsBuildable, true)
        XCTAssertTrue(session.confirmBuilding())
        XCTAssertEqual(session.world.placedBuildings.map(\.kind), [.marina])
        XCTAssertEqual(PlacedBuildingKind.wharf.title(in: .traditionalChinese), "漁人碼頭")
        XCTAssertEqual(PlacedBuildingKind.marina.title(in: .traditionalChinese), "遊艇港")
    }

    func testFreePlaySaysWhichCityBuildingsComeDownAndReadsInChinese() throws {
        var world = try makeWorld(width: 131_072, height: 98_304)
        try world.setLand([LandCell(row: 5, column: 5, use: .residential, residents: 1_000, jobs: 3)])
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTool(.building)
        session.buildingKind = .office
        session.tapBuildingTool(at: PlanPoint(x: 22_528, y: 22_528), reach: 0)
        XCTAssertEqual(session.buildingPreviewText, "拆除城市建物 1 棟")
        session.confirmBuilding()
        XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "蓋好辦公樓 #1，拆除城市建物 1 棟。"))
        // Nothing in the way: nothing to say.
        session.buildingKind = .house
        session.tapBuildingTool(at: PlanPoint(x: 60_000, y: 60_000), reach: 0)
        XCTAssertNil(session.buildingPreviewText)
    }

    func testTrackThroughACompanyBuildingSaysItComesDown() throws {
        var world = try makeWorld(width: 20_480, height: 20_480, balance: 100_000_000)
        world.setEconomyMode(.management)
        let house = try world.placeBuilding(.house, at: PlanPoint(x: 10_000, y: 10_000))
        let session = GameSession(world: world, language: .english)
        session.selectTool(.network)
        session.tapNetwork(at: PlanPoint(x: 4_000, y: 10_000), reach: 0)
        session.tapNetwork(at: PlanPoint(x: 16_000, y: 10_000), reach: 0)
        // 12,000 units of track, 1,200, and the house's demolition, 230,400.
        let preview = try XCTUnwrap(session.networkPreview)
        XCTAssertEqual(preview.cleared, [house])
        XCTAssertEqual(preview.cost, 231_600)
        XCTAssertEqual(session.networkOverlay?.cleared, [PlanRect(house)])
        session.buildNetworkTrack()
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertTrue(session.message?.text.hasSuffix("for $ 2,316, pulling down 1 of your buildings.") ?? false, session.message?.text ?? "")
        XCTAssertTrue(session.world.placedBuildings.isEmpty)
    }
}
