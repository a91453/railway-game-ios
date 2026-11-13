import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The city's size and kind (decision 683).
@MainActor
final class CityTitleTests: XCTestCase {
    typealias Rank = CityTitle.Rank
    typealias Kind = CityTitle.Kind

    func testEachSizeStartsAtItsResidents() {
        let starts: [(Rank, Int64)] = [
            (.hamlet, 0), (.village, 1_000), (.smallTown, 5_000), (.town, 20_000), (.smallCity, 100_000),
            (.city, 500_000), (.largeCity, 1_250_000), (.metropolis, 3_000_000), (.megalopolis, 10_000_000),
        ]
        XCTAssertEqual(starts.map(\.0), Rank.allCases)
        for (rank, residents) in starts {
            XCTAssertEqual(rank.residents, residents)
            XCTAssertEqual(Rank(residents: residents), rank)
            if residents > 0 { XCTAssertEqual(Rank(residents: residents - 1).rawValue, rank.rawValue - 1) }
        }
        XCTAssertEqual(Rank(residents: 1), .hamlet)
        XCTAssertEqual(Rank(residents: 1 << 40), .megalopolis)
        XCTAssertNil(Rank.megalopolis.next)
        XCTAssertEqual(Rank.town.next, .smallCity)
        XCTAssertLessThan(Rank.town, Rank.smallCity)
    }

    func testTheKindIsTheSectorFarthestAboveItsUsualShare() {
        // The usual shares themselves: nothing stands out.
        let usual = Kind.usualShare.mapValues { $0 * 10 }
        XCTAssertEqual(Kind.usualShare.values.reduce(0, +), 998)
        XCTAssertEqual(Set(Kind.usualShare.keys), Set(Kind.sectors))
        XCTAssertEqual(CityTitle.kind(residents: 10_000, jobs: usual), .mixed)
        // 8 points more offices at the shops' cost: offices lead.
        var offices = usual
        offices[.business, default: 0] += 800
        offices[.commercial, default: 0] -= 800
        XCTAssertEqual(CityTitle.kind(residents: 10_000, jobs: offices), .business)
        offices[.business, default: 0] -= 20
        XCTAssertEqual(CityTitle.kind(residents: 10_000, jobs: offices), .mixed, "just under the margin")
        // Two sectors above the margin: the one farther above.
        XCTAssertEqual(CityTitle.kind(residents: 10_000, jobs: [.industrial: 5_000, .tourist: 5_000]), .tourist)
        // Each sector alone.
        for sector in Kind.sectors {
            XCTAssertEqual(CityTitle.kind(residents: 10_000, jobs: [sector: 5_000]), sector)
        }
    }

    func testACityWithFewJobsIsResidentialAndASmallOneHasNoKind() {
        XCTAssertEqual(CityTitle.kind(residents: 30_000, jobs: [.industrial: 9_989]), .residential)
        XCTAssertEqual(CityTitle.kind(residents: 30_000, jobs: [.industrial: 9_990]), .industrial)
        XCTAssertNil(CityTitle.kind(residents: 4_999, jobs: [.industrial: 4_000]))
        XCTAssertEqual(CityTitle.kind(residents: 5_000, jobs: [.industrial: 4_000]), .industrial)
        XCTAssertNil(CityTitle.kind(residents: 30_000, jobs: [:]))
    }

    func testTheJobsOfHomesAndParksAreCommerce() {
        XCTAssertEqual(LandUse.allCases.map(Kind.sector(of:)), [.commercial, .commercial, .business, .industrial, .civic, .tourist, .farming, .commercial])
    }

    private func cells(residents: Int64, jobs: Int64 = 0, use: LandUse = .residential, column: Int = 0) -> [LandCell] {
        var cells: [LandCell] = []
        var left = residents, row = 0
        while left > 0 {
            let here = min(left, Land.maximumPerCell)
            cells.append(LandCell(row: row, column: column, use: .residential, residents: here, jobs: 0))
            left -= here
            row += 1
        }
        if jobs > 0 { cells.append(LandCell(row: row, column: column + 1, use: use, residents: 0, jobs: jobs)) }
        return cells
    }

    func testTheTitleOfSomeCells() throws {
        XCTAssertNil(CityTitle(cells: []))
        XCTAssertNil(CityTitle(cells: [LandCell(row: 0, column: 0, use: .industrial, residents: 0, jobs: 50)]), "no one lives there")
        let town = try XCTUnwrap(CityTitle(cells: cells(residents: 30_000, jobs: 20_000, use: .office)))
        XCTAssertEqual(town.residents, 30_000)
        XCTAssertEqual(town.rank, .town)
        XCTAssertEqual(town.kind, .business)
        XCTAssertEqual(town.residentsToNext, 70_000)
        XCTAssertEqual(town.headline(in: .english), "Town · mostly offices")
        XCTAssertEqual(town.headline(in: .traditionalChinese), "城鎮 · 以辦公為主")
        XCTAssertEqual(town.detail(in: .english), "30,000 residents. 70,000 more make it a small city.")
        XCTAssertEqual(town.detail(in: .traditionalChinese), "居民 30,000 人。再 70,000 人成為小城市。")

        let village = try XCTUnwrap(CityTitle(cells: cells(residents: 1_200, jobs: 900, use: .agricultural), countsAlongTheLines: true))
        XCTAssertNil(village.kind)
        XCTAssertEqual(village.headline(in: .traditionalChinese), "村莊")
        XCTAssertEqual(village.detail(in: .english), "1,200 residents. 3,800 more make it a small town.")
        XCTAssertEqual(village.detail(in: .traditionalChinese), "居民 1,200 人。再 3,800 人成為小鎮。")

        let largest = try XCTUnwrap(CityTitle(cells: cells(residents: 10_000_000)))
        XCTAssertEqual(largest.rank, .megalopolis)
        XCTAssertNil(largest.residentsToNext)
        XCTAssertEqual(largest.kind, nil)
        XCTAssertEqual(largest.detail(in: .english), "10,000,000 residents. The largest size there is.")
        XCTAssertEqual(largest.detail(in: .traditionalChinese), "居民 10,000,000 人。已經是最大的規模。")
    }

    // MARK: - The sights' visitors (decision 683, later)

    func testATownWhoseSightsDrawManyVisitorsIsATouristTown() throws {
        // 40 visitors a day for every thousand residents.
        XCTAssertEqual(CityTitle.touristVisitorsPerThousand, 40)
        let offices: [Kind: Int64] = [.business: 10_000]
        XCTAssertEqual(CityTitle.kind(residents: 20_000, jobs: offices), .business)
        XCTAssertEqual(CityTitle.kind(residents: 20_000, jobs: offices, visitorsPerDay: 799), .business)
        XCTAssertEqual(CityTitle.kind(residents: 20_000, jobs: offices, visitorsPerDay: 800), .tourist)
        // Before the few jobs that make a city residential.
        XCTAssertEqual(CityTitle.kind(residents: 30_000, jobs: [.industrial: 100]), .residential)
        XCTAssertEqual(CityTitle.kind(residents: 30_000, jobs: [.industrial: 100], visitorsPerDay: 1_200), .tourist)
        // Still none for a city too small, or with no jobs.
        XCTAssertNil(CityTitle.kind(residents: 4_999, jobs: offices, visitorsPerDay: 4_000))
        XCTAssertNil(CityTitle.kind(residents: 30_000, jobs: [:], visitorsPerDay: 4_000))

        let town = try XCTUnwrap(CityTitle(cells: cells(residents: 30_000, jobs: 20_000, use: .office), visitorsPerDay: 1_200))
        XCTAssertEqual(town.kind, .tourist)
        XCTAssertEqual(town.headline(in: .english), "Town · mostly tourism")
        XCTAssertEqual(town.headline(in: .traditionalChinese), "城鎮 · 以觀光為主")
    }

    func testTheVisitorsADayAreTheYearsAverage() {
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 0, lastYear: 0, daysThisYear: 0), 0)
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 6_000, lastYear: 0, daysThisYear: 3), 2_000)
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 30_000, lastYear: 999_999, daysThisYear: 30), 1_000, "a month in: this year alone")
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 1_000, lastYear: 360_000, daysThisYear: 1), 1_000, "a year's first day: last year's too")
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 0, lastYear: 3_600, daysThisYear: 0), 10)
        XCTAssertEqual(CityTitle.visitorsPerDay(thisYear: 720_000, lastYear: 0, daysThisYear: 500), 2_000, "never more than a year's days")
    }

    func testANewGamesSightsHaveNoVisitorsYet() {
        XCTAssertEqual(CityTitle.sightVisitorsPerDay(of: .newGame(eventSeed: 1)), 0)
    }

    func testEveryNameIsInBothLanguages() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            XCTAssertEqual(Set(Rank.allCases.map { $0.name(in: language) }).count, Rank.allCases.count)
            XCTAssertEqual(Set(Kind.allCases.map { $0.name(in: language) }).count, Kind.allCases.count)
        }
        XCTAssertEqual(CityTitle.promotionText(.metropolis, in: .english), "This place has grown into a metropolis.")
        XCTAssertEqual(CityTitle.promotionText(.metropolis, in: .traditionalChinese), "這裡成長為都會了。")
        // Review L17-10: no rank's news names the rank twice ("The city
        // has grown into a city.", "城市成長為城市。").
        for rank in CityTitle.Rank.allCases {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let name = rank.name(in: language).lowercased()
                let text = CityTitle.promotionText(rank, in: language).lowercased()
                XCTAssertEqual(text.components(separatedBy: name).count, 2, text)
            }
        }
    }

    func testANewGamesMapIsATownAndAMapReadInAsNeededStartsWithNone() throws {
        let blank = try XCTUnwrap(CityTitle(world: .newGame(eventSeed: 1)))
        XCTAssertEqual(blank.rank, .town)
        XCTAssertEqual(blank.kind, .business)
        XCTAssertFalse(blank.countsAlongTheLines)
        XCTAssertEqual(blank.residents, GameWorld.newGame(eventSeed: 1).totalResidents())
        XCTAssertNil(CityTitle(world: .newWholeTaiwanGame()))
        var world = try makeWorld(width: Land.blockLength, height: Land.blockLength)
        XCTAssertNil(CityTitle(world: world))
        world.setLandOnDemand()
        try world.expandLand([LandBlock(row: 0, column: 0)], cells: cells(residents: 2_000))
        XCTAssertEqual(CityTitle(world: world)?.countsAlongTheLines, true)
    }

    // MARK: - The news of a step up

    /// Runs `session` for a game day in one step.
    private func runADay(_ session: GameSession) throws {
        if session.world.clock.isPaused { session.togglePause() }
        let tick = try XCTUnwrap(session.beginLoopTick())
        let step = try GameSession.advanced(tick.world, by: 1_440, listening: false)
        XCTAssertTrue(session.finish(tick, with: .success(step)))
    }

    private func setLand(_ session: GameSession, residents: Int64) {
        let cells = cells(residents: residents)
        XCTAssertTrue(session.perform { world throws(GameError) in
            try world.setLand(cells)
            return ""
        })
    }

    private func promotions(_ session: GameSession) -> [String] {
        session.news.items.filter { $0.category == .growth }.map { $0.text(in: .traditionalChinese) }
    }

    func testAStepUpIsWrittenOnceAndNotAgainAfterShrinking() throws {
        var world = try makeWorld(width: Land.blockLength, height: Land.blockLength, speed: .normal)
        try world.setLand(cells(residents: 90_000))
        let session = GameSession(world: world, language: .traditionalChinese)
        var sounds: [SoundCue] = []
        session.playSound = { sounds.append($0) }
        try runADay(session)
        XCTAssertEqual(promotions(session), [], "the size a game starts at is no step up")

        setLand(session, residents: 120_000)
        try runADay(session)
        XCTAssertEqual(promotions(session), ["這裡成長為小城市了。"])
        XCTAssertEqual(session.news.items.first { $0.category == .growth }?.text(in: .english), "This place has grown into a small city.")
        XCTAssertEqual(session.message?.text, "這裡成長為小城市了。")
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(sounds.filter { $0 == .goalMet }.count, 1)
        try runADay(session)
        XCTAssertEqual(promotions(session).count, 1, "written once")

        setLand(session, residents: 80_000)
        try runADay(session)
        setLand(session, residents: 130_000)
        try runADay(session)
        XCTAssertEqual(promotions(session).count, 1, "a city that shrank and grew back says nothing")

        // Two steps in a day: the size reached.
        setLand(session, residents: 1_300_000)
        try runADay(session)
        XCTAssertEqual(promotions(session).first, "這裡成長為大城市了。")
        XCTAssertEqual(promotions(session).count, 2)

        // A loaded game says nothing of the size it is at.
        let loaded = GameSession(world: session.world, language: .traditionalChinese)
        loaded.restoreNews(session.news)
        try runADay(loaded)
        XCTAssertEqual(promotions(loaded).count, 2)
    }

    func testTheFirstPeopleOfAMapReadInAsNeededAreNoStepUp() throws {
        var world = try makeWorld(width: 2 * Land.blockLength, height: Land.blockLength, speed: .normal)
        world.setLandOnDemand()
        let session = GameSession(world: world, language: .english)
        try runADay(session)
        let first = cells(residents: 300_000), more = cells(residents: 300_000, column: 16)
        XCTAssertTrue(session.perform { world throws(GameError) in
            try world.expandLand([LandBlock(row: 0, column: 0)], cells: first)
            return ""
        })
        try runADay(session)
        XCTAssertEqual(promotions(session), [], "the land round the first station came in")
        XCTAssertTrue(session.perform { world throws(GameError) in
            try world.expandLand([LandBlock(row: 0, column: 1)], cells: more)
            return ""
        })
        try runADay(session)
        XCTAssertEqual(session.news.items.filter { $0.category == .growth }.map { $0.text(in: .english) }, ["This place has grown into a city."])
    }
}
