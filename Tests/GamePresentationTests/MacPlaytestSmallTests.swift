import GameCore
@testable import GamePresentation
import XCTest

/// Decision 663 (the Mac playtest's A12): the sights panel says what the
/// sights do in a sentence or two, and lists the sights on the company's
/// map first; those off it come after, nearest first, set apart.
final class SightsOffTheMapTests: XCTestCase {
    /// A blank map bought tile by tile (decision 160), owning its middle
    /// tile, with three sights: one on it, one a tile away, one far.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 3, buysMap: true)
        let owned = try XCTUnwrap(world.mapExpansion?.owned.first)
        let area = world.mapArea(of: owned)
        let length = MapExpansion.tileLength
        let middle = PlanPoint(x: (area.minX + area.maxX) / 2, y: (area.minY + area.maxY) / 2)
        world.setTourism([
            // The far one has the most stars: it used to be listed first.
            Attraction(id: AttractionID(rawValue: 1), name: "遠湖", englishName: "Far Lake",
                       point: PlanPoint(x: area.maxX + 2 * length, y: middle.y), kind: .mountain, baseStars: 450),
            Attraction(id: AttractionID(rawValue: 2), name: "近岬", englishName: "Near Cape",
                       point: PlanPoint(x: area.minX - length / 2, y: middle.y), kind: .coast, baseStars: 400),
            Attraction(id: AttractionID(rawValue: 3), name: "本鎮", englishName: "Home Town",
                       point: middle, kind: .town, baseStars: 300),
        ])
        return world
    }

    func testTheSightsOnTheMapComeFirstAndTheOthersByDistance() throws {
        let rows = try world().attractionRows(in: .english)
        XCTAssertEqual(rows.map(\.name), ["Home Town", "Near Cape", "Far Lake"])
        XCTAssertNil(rows[0].offMapMetres)
        let near = try XCTUnwrap(rows[1].offMapMetres)
        let far = try XCTUnwrap(rows[2].offMapMetres)
        // Half a tile (8.192 km) and two tiles (32.768 km) off the edge.
        XCTAssertEqual(near, MapExpansion.tileLength / 2 / WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(far, 2 * MapExpansion.tileLength / WorldCoordinate.unitsPerMetre)
        XCTAssertEqual(rows[1].offMapText(in: .english), "About 8 km off your map")
        XCTAssertEqual(rows[2].offMapText(in: .traditionalChinese), "在你的地圖外約 33 公里")
    }

    /// The screenshot scene of the panel: a blank map bought tile by tile
    /// has sights on its own tile and off it.
    func testTheScreenshotSceneHasSightsOnAndOffTheMap() {
        let rows = ScreenshotScene.sightsOffMap.make(in: .traditionalChinese).attractionRows(in: .traditionalChinese)
        XCTAssertTrue(rows.contains { $0.offMapMetres == nil }, "\(rows.map(\.name))")
        XCTAssertTrue(rows.contains { $0.offMapMetres != nil }, "\(rows.map(\.name))")
        // Short, so a UI test's drags reach the folded section.
        XCTAssertEqual(rows.count, 5, "\(rows.map(\.name))")
    }

    /// A map that is not bought tile by tile is the company's everywhere.
    func testAMapNotBoughtHasNoSightOffIt() {
        var world = GameWorld.newGame(eventSeed: 3)
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "甲", englishName: "A", point: PlanPoint(x: 1_000, y: 1_000), kind: .coast, baseStars: 300),
        ])
        XCTAssertNil(world.attractionRows(in: .english).first?.offMapMetres)
    }

    /// CLAUDE.md, the words players read: what the sights do, not how
    /// their stars are counted.
    func testTheHelpSaysWhatSightsDoInTwoSentences() throws {
        let world = try world()
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let help = world.tourismHelp(in: language)
            XCTAssertFalse(help.contains("0.25"), help)
            XCTAssertFalse(help.contains("%"), help)
            XCTAssertFalse(help.contains("quarter"), help)
            let sentences = help.split(whereSeparator: { ".。".contains($0) }).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertLessThanOrEqual(sentences.count, 2, help)
        }
    }
}

/// Decision 663 (the Mac playtest's D9): the fares page of a world whose
/// high-speed trips pay a table of their own says so, with its range,
/// instead of leaving the distance steps' NT$24 as the fare of 345 km.
final class HighSpeedFareTextTests: XCTestCase {
    func testTheFaresPageSaysWhatHighSpeedTripsPay() throws {
        var world = GameWorld.newGame(eventSeed: 5)
        XCTAssertNil(world.highSpeedFareText(in: .english))
        let a = try world.buildStation(named: "南港", at: PlanPoint(x: 20_000, y: 500_000)).id
        let b = try world.buildStation(named: "台北", at: PlanPoint(x: 40_000, y: 500_000)).id
        let c = try world.buildStation(named: "左營", at: PlanPoint(x: 900_000, y: 500_000)).id
        try world.setHighSpeedFares([
            HighSpeedFare(between: a, and: b, fare: Money(4_000)),
            HighSpeedFare(between: a, and: c, fare: Money(153_000)),
            HighSpeedFare(between: b, and: c, fare: Money(149_000)),
        ])
        XCTAssertEqual(
            world.highSpeedFareText(in: .traditionalChinese),
            "搭高鐵的旅客照兩站之間的高鐵票價付，不用上面的票價：NT$40 到 NT$1,530（南港－左營）。"
        )
        XCTAssertEqual(
            world.highSpeedFareText(in: .english),
            "High-speed riders pay the fare between their two stations, not the fares above: NT$40 to NT$1,530 (南港–左營)."
        )
    }

    /// The High Speed Rail demo's own table (decision 325): Nangang to
    /// Zuoying is NT$1,530, not the NT$24 of the last distance step.
    func testTheDemosLongestTripIsItsRealFare() {
        XCTAssertEqual(HighSpeedFares.standard[0][11], Money(153_000))
        XCTAssertEqual(FareRules.standardBands.last?.fare, Money(2_400))
    }
}

/// Decision 663 (the Mac playtest's D10): the tutorial is lesson 1, whose
/// stars come once its goals are met; when its tour finishes before that,
/// the status line says so and that the lessons go on, so a player who goes
/// back to the start at once knows why it still reads ★ 0.
@MainActor
final class TutorialEndTests: XCTestCase {
    func testFinishingTheTourBeforeLessonOneIsPassedSaysWhatIsLeft() {
        let session = GameSession(world: .newGame(lesson: Lesson.all[0]), language: .traditionalChinese)
        // The first launch's tutorial is lesson 1's guide (decision 266),
        // 15 steps to the first fares.
        XCTAssertEqual(Lesson.all[0].guide.count, 15)
        XCTAssertEqual(Lesson.all[0].guide.last?.id, "first.fare")
        XCTAssertNil(Lesson.firstLessonLeftText(over: GameWorld.newGame(eventSeed: 1), in: .english))
        let expected = "導覽完成。一天的人次到 \(Lesson.firstRiders.groupedText)，入門第 1 關就過關、拿到星星；開始畫面的「入門」還有 \(Lesson.all.count - 1) 關。"
        XCTAssertEqual(Lesson.firstLessonLeftText(over: session.world, in: .traditionalChinese), expected)
        XCTAssertEqual(
            Lesson.firstLessonLeftText(over: session.world, in: .english),
            "Tour done. Lesson 1 is passed, with its stars, once a day's riders reach 30,000; Lessons on the start screen has 9 more."
        )
    }
}
