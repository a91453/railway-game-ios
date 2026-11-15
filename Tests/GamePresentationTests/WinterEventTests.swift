import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 788: the winter event's frame, by the device's date: its weeks,
/// its missions read from the network, the badges kept beside the saves.
final class WinterEventTests: XCTestCase {
    private var directory: URL!
    private let calendar = WinterEvent.calendar(in: TimeZone(identifier: "Asia/Taipei")!)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("WinterEventTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Every day from 25 November to 10 January lands where the plan's
    /// table says (§2.4).
    func testEveryDayFallsInItsWeek() {
        var expected: [String: WinterEvent.Phase] = [:]
        for day in 25...30 { expected["11/\(day)"] = .off }
        for day in 1...7 { expected["12/\(day)"] = .week(1) }
        for day in 8...14 { expected["12/\(day)"] = .week(2) }
        for day in 15...21 { expected["12/\(day)"] = .week(3) }
        for day in 22...28 { expected["12/\(day)"] = .week(4) }
        for day in 29...31 { expected["12/\(day)"] = .week(5) }
        for day in 1...4 { expected["1/\(day)"] = .week(5) }
        for day in 5...6 { expected["1/\(day)"] = .wrapUp }
        for day in 7...10 { expected["1/\(day)"] = .off }
        for (key, phase) in expected {
            let parts = key.split(separator: "/").map { Int($0)! }
            let year = parts[0] == 1 ? 2027 : 2026
            let found = WinterEvent.phase(at: date(year, parts[0], parts[1]), calendar: calendar)
            XCTAssertEqual(found.phase, phase, key)
            XCTAssertEqual(found.season, phase == .off ? nil : 2026, key)
        }
    }

    /// The week turns at the player's own midnight, not at UTC's.
    func testTheEventOpensAtTheDevicesMidnight() {
        XCTAssertEqual(WinterEvent.phase(at: date(2026, 11, 30, 23, 59), calendar: calendar).phase, .off)
        XCTAssertEqual(WinterEvent.phase(at: date(2026, 12, 1, 0, 0), calendar: calendar).phase, .week(1))
        XCTAssertEqual(WinterEvent.phase(at: date(2027, 1, 6, 23, 59), calendar: calendar).phase, .wrapUp)
        XCTAssertEqual(WinterEvent.phase(at: date(2027, 1, 7, 0, 0), calendar: calendar).phase, .off)
        let utc = WinterEvent.calendar(in: TimeZone(identifier: "UTC")!)
        // 00:30 on 1 December in Taipei is still 30 November in UTC.
        XCTAssertEqual(WinterEvent.phase(at: date(2026, 12, 1, 0, 30), calendar: utc).phase, .off)
    }

    func testTheDecorationsFollowTheEventAndTheSwitch() {
        XCTAssertTrue(WinterEvent.showsDecorations(at: date(2026, 12, 24), switchedOn: true, calendar: calendar))
        XCTAssertFalse(WinterEvent.showsDecorations(at: date(2026, 12, 24), switchedOn: false, calendar: calendar))
        XCTAssertFalse(WinterEvent.showsDecorations(at: date(2027, 2, 1), switchedOn: true, calendar: calendar))
    }

    func testFiveMissionsOneAWeekInBothLanguages() {
        XCTAssertEqual(WinterMission.all.map(\.week), [1, 2, 3, 4, 5])
        XCTAssertEqual(Set(WinterMission.all.map(\.id)).count, 5)
        XCTAssertEqual(WinterMission.all.filter(\.unlocksLivery).map(\.week), [4])
        for mission in WinterMission.all {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(mission.title(in: language).isEmpty)
                XCTAssertFalse(mission.how(in: language).isEmpty)
                XCTAssertFalse(mission.badge(in: language).isEmpty)
            }
        }
        XCTAssertEqual(WinterEvent.datesText(ofWeek: 1), "12/1–12/7")
        XCTAssertEqual(WinterEvent.datesText(ofWeek: 4), "12/22–12/28")
        XCTAssertEqual(WinterEvent.datesText(ofWeek: 5), "12/29–1/4")
        XCTAssertNil(WinterEvent.mission(at: date(2027, 1, 5), calendar: calendar), "the wrap-up has none")
    }

    func testAnEmptyCompanyMeetsNoMission() {
        let facts = WinterMissionFacts(world: .newGame())
        XCTAssertEqual(WinterMission.all.filter { $0.isMet(by: facts) }.map(\.id), [])
    }

    /// A line running all day: its stations are lit after 18:00, it runs
    /// the market's evening when it has the trains, and past midnight.
    func testALineBetweenTwoTownsIsReadFromTheNetwork() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        let facts = WinterMissionFacts(world: world)
        let line = try XCTUnwrap(world.lines.first)
        XCTAssertEqual(facts.stationsLitAtNight, Set(line.stops).count)
        XCTAssertEqual(facts.hasEveningMarketLine, line.assignedTrains.count >= WinterMission.marketTrains)
        // The helper's line runs all day: past midnight too.
        XCTAssertEqual(line.window, .allDay)
        XCTAssertTrue(facts.hasLineAfterMidnight)
        XCTAssertFalse(facts.hasLiveriedLineRunning)
        XCTAssertTrue(WinterMissionFacts(world: world, liveried: [line.id]).hasLiveriedLineRunning)
    }

    func testThresholds() throws {
        var facts = WinterMissionFacts()
        let lights = try XCTUnwrap(WinterMission.named("lights"))
        facts.stationsLitAtNight = 2
        XCTAssertFalse(lights.isMet(by: facts))
        XCTAssertEqual(lights.progress(of: facts)?.need, 3)
        facts.stationsLitAtNight = 3
        XCTAssertTrue(lights.isMet(by: facts))
        let santa = try XCTUnwrap(WinterMission.named("arctic"))
        facts.yesterdayRiders = 999
        XCTAssertFalse(santa.isMet(by: facts))
        facts.yesterdayRiders = 1_000
        XCTAssertTrue(santa.isMet(by: facts))
        XCTAssertEqual(santa.progress(of: facts)?.now, 1_000)
    }

    /// A badge is the week's only: met in week 2, the first week's mission
    /// earns nothing more.
    func testABadgeIsEarnedOnlyInItsWeekAndOnce() throws {
        let file = directory.appendingPathComponent(WinterEventRecords.fileName)
        var records = WinterEventRecords(file: file)
        var facts = WinterMissionFacts()
        facts.stationsLitAtNight = 5
        XCTAssertNil(records.earn(meeting: facts, at: date(2026, 11, 30), calendar: calendar), "not before the event")
        XCTAssertEqual(records.earn(meeting: facts, at: date(2026, 12, 2), calendar: calendar)?.id, "lights")
        XCTAssertNil(records.earn(meeting: facts, at: date(2026, 12, 3), calendar: calendar), "once")
        XCTAssertNil(records.earn(meeting: facts, at: date(2026, 12, 9), calendar: calendar), "week 2 wants the market")
        XCTAssertEqual(records.badges(season: 2026).map(\.id), ["lights"])
        XCTAssertEqual(WinterEventRecords(file: file).badges(season: 2026).map(\.id), ["lights"], "read back")
        XCTAssertEqual(WinterEventRecords(file: file).badges(season: 2027), [], "next season starts empty")
    }

    func testTheLiveryStaysOnceTheFourthWeeksBadgeIsEarned() throws {
        var records = WinterEventRecords(file: directory.appendingPathComponent(WinterEventRecords.fileName))
        XCTAssertTrue(records.liveryIsAvailable(at: date(2026, 12, 23), calendar: calendar), "during the event")
        XCTAssertFalse(records.liveryIsAvailable(at: date(2027, 3, 1), calendar: calendar))
        var facts = WinterMissionFacts()
        facts.hasLiveriedLineRunning = true
        XCTAssertEqual(records.earn(meeting: facts, at: date(2026, 12, 24), calendar: calendar)?.id, "christmasEve")
        XCTAssertTrue(records.liveryIsAvailable(at: date(2027, 3, 1), calendar: calendar))
    }

    func testAllFiveBadgesGiveTheKeepsake() throws {
        var records = WinterEventRecords(file: directory.appendingPathComponent(WinterEventRecords.fileName))
        var facts = WinterMissionFacts()
        facts.stationsLitAtNight = 3
        facts.hasEveningMarketLine = true
        facts.yesterdayRiders = 1_000
        facts.hasLiveriedLineRunning = true
        facts.hasLineAfterMidnight = true
        for day in [1, 8, 15, 22, 29] {
            XCTAssertNotNil(records.earn(meeting: facts, at: date(2026, 12, day), calendar: calendar))
            XCTAssertEqual(records.hasAllBadges(season: 2026), day == 29)
        }
    }

    func testADamagedFileIsMovedAsideNotLost() throws {
        let file = directory.appendingPathComponent(WinterEventRecords.fileName)
        try Data("not json".utf8).write(to: file)
        var records = WinterEventRecords(file: file)
        XCTAssertEqual(records.earned, [:])
        var facts = WinterMissionFacts()
        facts.stationsLitAtNight = 3
        XCTAssertNotNil(records.earn(meeting: facts, at: date(2026, 12, 1), calendar: calendar))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.appendingPathExtension("damaged").path))
        XCTAssertEqual(WinterEventRecords(file: file).badges(season: 2026).map(\.id), ["lights"])
    }

    /// The launcher's midnight check: a demo earns nothing, nor a day
    /// outside the event; a game says so in the news and on the status line.
    @MainActor
    func testMidnightEarnsTheWeeksBadgeUnlessItIsADemo() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        // The first week asks for stations a two-station line has.
        XCTAssertGreaterThanOrEqual(WinterMissionFacts(world: world).stationsLitAtNight, 2)
        let line = try XCTUnwrap(world.lines.first)
        XCTAssertGreaterThanOrEqual(Set(line.stops).count, 2)
        let session = GameSession(world: world, language: .traditionalChinese)
        let eveningLine = WinterMission.named("market")!
        let met = eveningLine.isMet(by: WinterMissionFacts(world: world))
        session.news.isDemo = true
        launcher.checkWinterEvent(of: session, at: date(2026, 12, 9), calendar: calendar)
        XCTAssertEqual(launcher.winterEvent.earned, [:], "a demo earns nothing")
        session.news.isDemo = false
        launcher.checkWinterEvent(of: session, at: date(2026, 11, 20), calendar: calendar)
        XCTAssertEqual(launcher.winterEvent.earned, [:], "nothing outside the event")
        launcher.checkWinterEvent(of: session, at: date(2026, 12, 9), calendar: calendar)
        XCTAssertEqual(launcher.winterEvent.hasEarned(eveningLine, season: 2026), met)
        if met {
            XCTAssertEqual(session.message?.text, "獲得徽章：市集")
            XCTAssertTrue(session.news.items.contains { $0.text(in: .traditionalChinese).hasPrefix("冬季活動：完成「聖誕市集專車」") })
            let file = directory.appendingPathComponent(WinterEventRecords.fileName)
            XCTAssertEqual(WinterEventRecords(file: file).badges(season: 2026).map(\.id), ["market"])
        }
    }
}
