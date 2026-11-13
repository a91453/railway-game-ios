import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 724: a sight's card in the sights panel says how many visitors
/// it had in a year by the Tourism Administration's count, read from the
/// app's `taiwan_sight_visitors.json`; a sight without one says nothing.
final class SightVisitorsTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func bundled() throws -> SightVisitors {
        let data = try RealWorldDataLoadTests.file("taiwan_sight_visitors", "json")
        return try SightVisitors(data: data)
    }

    private func spot(_ id: String) throws -> AttractionCatalog.Spot {
        try XCTUnwrap(AttractionCatalog.spots.first { $0.id == id })
    }

    private func sight(_ id: String) throws -> Attraction {
        let spot = try spot(id)
        return Attraction(id: AttractionID(rawValue: 1), name: spot.name, englishName: spot.englishName,
                          point: PlanPoint(x: 1_000, y: 1_000), kind: spot.kind, baseStars: spot.stars)
    }

    /// The bundled file reads (its init checks that each sight is the
    /// catalog's, once, with twelve months adding up to its year), and the
    /// app's loader reads it with the rest of the real-world data.
    func testTheBundledFileReads() throws {
        let visitors = try bundled()
        XCTAssertEqual(visitors.year, 2024)
        XCTAssertGreaterThan(visitors.sights.count, 90)
        for (id, count) in visitors.sights {
            XCTAssertEqual(count.months.count, 12, id)
            XCTAssertEqual(count.months.reduce(0, +), count.visitors, id)
            XCTAssertGreaterThan(count.visitors, 0, id)
        }
        XCTAssertEqual(RealWorldData.load(file: RealWorldDataLoadTests.file).sightVisitors, visitors)
    }

    /// Every sight in the hand-checked table is one of the catalog's, under
    /// the same name; the file has exactly the table's matched sights.
    func testTheTableNamesTheCatalogsSights() throws {
        struct Table: Decodable {
            struct Entry: Decodable {
                struct Official: Decodable { let name: String; let county: String }
                let id: String
                let sight: String
                let official: [Official]
                let why: String?
            }

            let year: Int
            let sights: [Entry]
        }
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tools/tourism-spots/official_names.json"))
        let table = try JSONDecoder().decode(Table.self, from: data)
        for entry in table.sights {
            XCTAssertEqual(try spot(entry.id).name, entry.sight, entry.id)
            if entry.official.isEmpty {
                XCTAssertFalse(entry.why?.isEmpty ?? true, "\(entry.id) is left out with a reason")
            }
        }
        XCTAssertEqual(Set(table.sights.map(\.id)).count, table.sights.count, "each sight once")
        let visitors = try bundled()
        XCTAssertEqual(table.year, visitors.year)
        XCTAssertEqual(Set(visitors.sights.keys), Set(table.sights.filter { !$0.official.isEmpty }.map(\.id)))
    }

    /// A world's sight is found in the catalog by its names, so no two
    /// spots may share a Chinese name.
    func testTheCatalogsNamesAreUnique() {
        XCTAssertEqual(Set(AttractionCatalog.spots.map(\.name)).count, AttractionCatalog.spots.count)
    }

    func testTheLineSaysTheYearsVisitorsInEachLanguage() throws {
        let visitors = try bundled()
        // Sun Moon Lake: 2,870,420 in 2024.
        XCTAssertEqual(visitors.text(of: try sight("s06"), in: .traditionalChinese), "一年約 287 萬人次（2024，交通部觀光署）")
        XCTAssertEqual(visitors.text(of: try sight("s06"), in: .english), "About 2.9 million visitors a year (2024, Tourism Administration)")
        XCTAssertEqual(SightVisitors.chineseAmount(54_499), "5.4 萬")
        XCTAssertEqual(SightVisitors.chineseAmount(30_000), "3 萬")
        XCTAssertEqual(SightVisitors.chineseAmount(9_600), "9,600")
        XCTAssertEqual(SightVisitors.chineseAmount(12_748_808), "1275 萬")
        XCTAssertEqual(SightVisitors.englishAmount(54_499), "54,000")
        XCTAssertEqual(SightVisitors.englishAmount(999_700), "1 million")
        XCTAssertEqual(SightVisitors.englishAmount(2_000_000), "2 million")
        XCTAssertEqual(SightVisitors.englishAmount(960), "960")
        XCTAssertEqual(SightVisitors.text(visitors: 9_600, year: 2024, in: .traditionalChinese), "一年約 9,600 人次（2024，交通部觀光署）")
    }

    /// The sights panel's rows: one with an official count has the line,
    /// one without (Ximending has no official spot) or a sight that is not
    /// the catalog's (a lesson's) has none.
    func testOnlyASightWithAnOfficialCountHasTheLine() throws {
        let visitors = try bundled()
        var world = GameWorld.newGame(eventSeed: 3)
        let ximending = try sight("t005")
        world.setTourism([
            Attraction(id: AttractionID(rawValue: 1), name: "日月潭", englishName: "Sun Moon Lake",
                       point: PlanPoint(x: 1_000, y: 1_000), kind: .mountain, baseStars: 450),
            Attraction(id: AttractionID(rawValue: 2), name: ximending.name, englishName: ximending.englishName,
                       point: PlanPoint(x: 2_000, y: 1_000), kind: ximending.kind, baseStars: ximending.stars),
            Attraction(id: AttractionID(rawValue: 3), name: "近岬", englishName: "Near Cape",
                       point: PlanPoint(x: 3_000, y: 1_000), kind: .coast, baseStars: 400),
        ])
        for language in DisplayLanguage.allCases {
            let rows = world.attractionRows(in: language, visitors: visitors)
            let lines = Dictionary(uniqueKeysWithValues: rows.map { ($0.id.rawValue, $0.officialVisitorsText) })
            XCTAssertEqual(lines[1] ?? nil, SightVisitors.text(visitors: 2_870_420, year: 2024, in: language))
            XCTAssertNil(lines[2] ?? nil)
            XCTAssertNil(lines[3] ?? nil)
            XCTAssertTrue(world.attractionRows(in: language).allSatisfy { $0.officialVisitorsText == nil }, "none without the data")
        }
    }

    /// The session's rows take the data once it arrives.
    @MainActor func testTheSessionsRowsTakeTheDataWhenItArrives() throws {
        var world = GameWorld.newGame(eventSeed: 3)
        world.setTourism([try sight("s06")])
        let session = GameSession(world: world, language: .traditionalChinese)
        XCTAssertNil(session.sightsPanelRows.first?.officialVisitorsText)
        session.sightVisitors = try bundled()
        XCTAssertEqual(session.sightsPanelRows.first?.officialVisitorsText, "一年約 287 萬人次（2024，交通部觀光署）")
    }

    func testAFileWhoseMonthsDoNotAddUpIsRefused() {
        let wrong = #"{"year":2024,"sights":[{"id":"s06","visitors":13,"months":[1,1,1,1,1,1,1,1,1,1,1,1]}]}"#
        XCTAssertThrowsError(try SightVisitors(data: Data(wrong.utf8)))
        let unknown = #"{"year":2024,"sights":[{"id":"x99","visitors":12,"months":[1,1,1,1,1,1,1,1,1,1,1,1]}]}"#
        XCTAssertThrowsError(try SightVisitors(data: Data(unknown.utf8)))
        let short = #"{"year":2024,"sights":[{"id":"s06","visitors":11,"months":[1,1,1,1,1,1,1,1,1,1,1]}]}"#
        XCTAssertThrowsError(try SightVisitors(data: Data(short.utf8)))
    }
}

/// Decision 724: the screenshot scene of the line has the catalog's three
/// sights, two of them with an official count.
final class SightVisitorsSceneTests: XCTestCase {
    func testTheSceneHasTwoSightsWithACountAndOneWithout() throws {
        let visitors = try SightVisitors(data: RealWorldDataLoadTests.file("taiwan_sight_visitors", "json"))
        let world = ScreenshotScene.sightVisitors.make(in: .traditionalChinese)
        let rows = world.attractionRows(in: .traditionalChinese, visitors: visitors)
        XCTAssertEqual(Set(rows.map(\.name)), ["台北101", "中正紀念堂", "西門町"])
        XCTAssertEqual(rows.filter { $0.officialVisitorsText != nil }.count, 2)
    }
}

/// Decision 724: the scene waits for the real-world data, whose sights'
/// visitors its cards show.
final class SightVisitorsSceneWaitTests: XCTestCase {
    func testTheSceneWaitsForTheRealWorldData() {
        XCTAssertTrue(ScreenshotScene.sightVisitors.needsRealWorldData)
        XCTAssertTrue(ScreenshotScene.wenhu.needsRealWorldData)
        XCTAssertFalse(ScreenshotScene.sightVisitors.needsWater)
    }
}
