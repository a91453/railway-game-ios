import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 175: the news log, its side file, and what the session writes
/// into it.
final class NewsLogTests: XCTestCase {
    func testTheNewestItemIsFirstAndOnlyThreeHundredAreKept() {
        var log = NewsLog()
        for number in 1...(NewsLog.capacity + 20) {
            log.add(day: Int64(number), .success, english: "n\(number)", chinese: nil)
        }
        XCTAssertEqual(log.items.count, NewsLog.capacity)
        XCTAssertEqual(log.items.first?.english, "n\(NewsLog.capacity + 20)")
        XCTAssertEqual(log.items.last?.english, "n21")
    }

    func testUnreadCountsTheItemsSinceTheLogWasOpened() {
        var log = NewsLog()
        XCTAssertEqual(log.unread, 0)
        log.add(day: 0, .advice, english: "a", chinese: "甲")
        log.add(day: 0, .advice, english: "b", chinese: "乙")
        XCTAssertEqual(log.unread, 2)
        log.markRead()
        XCTAssertEqual(log.unread, 0)
        log.add(day: 1, .goal, english: "c", chinese: "丙")
        XCTAssertEqual(log.unread, 1)
    }

    func testAnItemSpeaksInTheLanguageAskedForElseTheOther() {
        var log = NewsLog()
        let both = log.add(day: 0, .advice, english: "Hello", chinese: "你好")
        let only = log.add(day: 0, .success, english: nil, chinese: "已儲存")
        XCTAssertEqual(both.text(in: .english), "Hello")
        XCTAssertEqual(both.text(in: .traditionalChinese), "你好")
        XCTAssertEqual(only.text(in: .english), "已儲存")
    }

    func testTheLogRoundTripsAndRefusesAnOutOfOrderOrLaterFile() throws {
        var log = NewsLog()
        log.add(day: 3, .station, target: .station(2)) { $0.text("A", "甲") }
        log.add(day: 4, .typhoon, target: nil) { $0.text("B", "乙") }
        log.markRead()
        log.baseline = MonthlyBaseline(reportedMonth: 2, stationTrips: [1: 500], tallBuildings: 3)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(NewsLog.self, from: data), log)

        let later = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\":1", with: "\"version\":9")
        XCTAssertThrowsError(try JSONDecoder().decode(NewsLog.self, from: Data(later.utf8)))
        let swapped = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"id\":2", with: "\"id\":0")
        XCTAssertThrowsError(try JSONDecoder().decode(NewsLog.self, from: Data(swapped.utf8)))
    }
}

private extension NewsCategory {
    static let station = NewsCategory.advice
}

@MainActor
final class NewsSessionTests: XCTestCase {
    static let alpha = StationID(rawValue: 1)

    /// Two stations on a line with a running train, Taiwan's holidays on
    /// (`seed` for weather and typhoons), starting at game day `day`.
    static func world(day: Int64, seed: UInt32? = nil, managed: Bool = true, balance: Money = 10_000_000_000) throws -> GameWorld {
        var world = GameWorld(
            bounds: try WorldBounds(width: 32_768, height: 4_096), economy: GameEconomy(balance: balance, costs: testCosts),
            clock: GameClock(now: GameTime(seconds: day * GameTime.secondsPerDay))
        )
        let tile = Int64(1_024), platform = 4 * Train.carLength
        let west = try world.buildTrackNode(at: WorldCoordinate(x: tile, y: 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 29 * tile, y: 2_048))
        let edge = try world.buildTrackEdge(from: west, to: east)
        var stops: [StationID] = []
        for (name, middle) in [("Alpha", tile + platform / 2), ("Beta", 27 * tile - platform / 2)] {
            let station = try world.buildStation(named: name, at: PlanPoint(x: tile + middle, y: 2_048)).id
            try world.addTrackPlatform(station, on: edge, from: middle - platform / 2, to: middle + platform / 2)
            stops.append(station)
        }
        let line = try world.createLine(named: "Main", stops: stops).id
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: "T1").id
        try world.setTrainCars(train, to: 4)
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: .forward), offset: tile + platform))
        try world.setTrainContinuation(train, along: [], stoppingAt: tile + platform)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
        try world.setStationDemand(Self.alpha, to: StationDemand(kind: .residential, dailyTrips: 200))
        try world.setStationDemand(StationID(rawValue: 2), to: StationDemand(kind: .office, dailyTrips: 200))
        if managed { world.setEconomyMode(.management) }
        world.setDisruptions(Disruptions(level: .standard, country: "TW", seed: seed))
        world.setSpeed(.normal)
        return world
    }

    /// Runs `session` for `ticks` game minutes in one step.
    private func run(_ session: GameSession, ticks: Int) throws {
        let tick = try XCTUnwrap(session.beginLoopTick())
        let step = try GameSession.advanced(tick.world, by: ticks, listening: false)
        XCTAssertTrue(session.finish(tick, with: .success(step)))
    }

    /// Decision 175, later: a challenge loaded in its last week was warned
    /// already; loading it again must not write the warning (and pause) again.
    func testTheChallengeLastWeekWarningIsNotRepeatedAfterALoad() throws {
        var world = try Self.world(day: 0)
        try world.startScenario(Scenario(id: "test", goals: [.equity(Money(1_000_000_000_000))], goldDays: 30, silverDays: 30, deadlineDays: 30))
        let session = GameSession(world: world, language: .english)
        try run(session, ticks: 23 * 1_440)
        func warnings(_ session: GameSession) -> Int { session.news.items.filter { $0.category == .deadline }.count }
        XCTAssertEqual(warnings(session), 1)
        let loaded = GameSession(world: session.world, language: .english)
        loaded.restoreNews(session.news)
        loaded.setSpeed(.normal)
        try run(loaded, ticks: 1_440)
        XCTAssertEqual(warnings(loaded), 1, "no second warning after the load")
    }

    func testAHolidayBeginningIsWrittenOnceInBothLanguages() throws {
        let session = GameSession(world: try Self.world(day: 42), language: .english)
        try run(session, ticks: 1_440)
        let holiday = try XCTUnwrap(session.news.items.first { $0.category == .holiday && ($0.english ?? "").contains("begins") })
        XCTAssertEqual(holiday.text(in: .english), "Lunar New Year begins: +20% demand on every line for 9 days.")
        XCTAssertEqual(holiday.text(in: .traditionalChinese), "春節開始：全線需求 +20%，連續 9 天。")
        XCTAssertEqual(holiday.day, 43)
        XCTAssertEqual(session.news.items.filter { ($0.english ?? "").contains("begins") }.count, 1)
    }

    func testStatusMessagesAreKeptWithTheirKind() throws {
        let session = GameSession(world: try Self.world(day: 3), language: .traditionalChinese)
        session.message = StatusMessage(kind: .success, text: "已儲存遊戲。")
        session.message = StatusMessage(kind: .failure, text: "錢不夠。")
        session.message = nil
        XCTAssertEqual(session.news.items.map(\.category), [.failure, .success])
        XCTAssertEqual(session.news.items.last?.text(in: .traditionalChinese), "已儲存遊戲。")
    }

    func testTheStationMastersWorryIsWrittenOnceNotEveryHour() throws {
        var world = try Self.world(day: 3, managed: false)
        // No trains on the line: "has no trains yet".
        let line = try XCTUnwrap(world.lines.first)
        for id in line.assignedTrains { try world.unassignTrain(id) }
        let session = GameSession(world: world, language: .english)
        try run(session, ticks: 60)
        try run(session, ticks: 60)
        try run(session, ticks: 60)
        let said = session.news.items.filter { $0.category == .advice }
        XCTAssertEqual(said.count, 1)
        XCTAssertEqual(said.first?.target, .line(line.id.rawValue))
        XCTAssertTrue(session.canGo(to: try XCTUnwrap(said.first)))
        session.goTo(try XCTUnwrap(said.first))
        XCTAssertEqual(session.selectedLineID, line.id)
        XCTAssertNotNil(session.cameraRequest)
    }

    func testATyphoonWarningPausesTheGameOnlyWhenAskedTo() throws {
        // A seed whose first typhoon covers Alpha.
        var found: (seed: UInt32, typhoon: Typhoon)?
        let probe = try Self.world(day: 0)
        let alphaPoint = try XCTUnwrap(probe.station(id: Self.alpha)).point
        for seed in UInt32(1)...400 {
            let disruptions = try XCTUnwrap(Disruptions(level: .standard, country: "TW", seed: seed))
            if let typhoon = disruptions.typhoons(ofYear: 0, in: probe.bounds).first(where: { $0.covers(alphaPoint) && $0.announced >= 1 }) {
                found = (seed, typhoon)
                break
            }
        }
        let (seed, typhoon) = try XCTUnwrap(found, "no seed in 1...400 puts a typhoon over Alpha")

        for pauses in [true, false] {
            let session = GameSession(world: try Self.world(day: typhoon.announced - 1, seed: seed), language: .english)
            session.pausesForImportantEvents = pauses
            try run(session, ticks: 1_440)
            let warning = try XCTUnwrap(session.news.items.first { $0.category == .typhoon })
            XCTAssertTrue(warning.text(in: .english).hasPrefix("Typhoon warning"), warning.text(in: .english))
            XCTAssertEqual(session.world.clock.isPaused, pauses)
        }
    }

    func testCashGoingBelowZeroIsWrittenAndPauses() throws {
        // Costs run on while the balance is nearly nothing.
        let session = GameSession(world: try Self.world(day: 3, balance: Money(40_000)), language: .english)
        XCTAssertFalse(session.news.items.contains { $0.category == .debt })
        try run(session, ticks: 1_440)
        XCTAssertLessThan(session.world.economy.balance, .zero, "the test needs the company to run out of cash")
        XCTAssertEqual(session.news.items.filter { $0.category == .debt }.count, 1)
        XCTAssertTrue(session.world.clock.isPaused)
        XCTAssertEqual(session.message?.text, "Paused: Cash is below zero.")
        XCTAssertFalse(session.news.items.contains { $0.text(in: .english).hasPrefix("Paused") }, "the pause note is not news twice")
    }

    /// An absurd counter in a damaged file is refused, not trapped on later.
    func testALogWithAnAbsurdCounterIsRefused() throws {
        var log = NewsLog()
        log.add(day: 1, .success, english: "a", chinese: nil)
        let data = try JSONEncoder().encode(log)
        let text = String(decoding: data, as: UTF8.self)
        for nextID in ["9223372036854775807", "0", "-5"] {
            let damaged = text.replacingOccurrences(of: "\"nextID\":2", with: "\"nextID\":\(nextID)")
            XCTAssertNotEqual(damaged, text)
            XCTAssertThrowsError(try JSONDecoder().decode(NewsLog.self, from: Data(damaged.utf8)), nextID)
        }
    }

    func testTheSameMessageAgainIsNotAnotherNewsItem() throws {
        let session = GameSession(world: try Self.world(day: 3), language: .english)
        for _ in 0..<6 {
            session.message = StatusMessage(kind: .failure, text: "Not enough cash.")
        }
        XCTAssertEqual(session.news.items.filter { $0.category == .failure }.count, 1)
        session.message = StatusMessage(kind: .failure, text: "Can't build here.")
        XCTAssertEqual(session.news.items.filter { $0.category == .failure }.count, 2)
    }

    func testTheNewsLogGoesBesideASaveAndIsNoSaveItself() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("news-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = SaveLibrary(directory: directory)
        var log = NewsLog()
        log.add(day: 1, .goal, english: "Goal met", chinese: "目標達成")
        let world = try Self.world(day: 3)
        let manual = try library.save(world, news: log, as: .manual, at: Date(timeIntervalSince1970: 1_000))
        try library.save(world, news: log, as: .autosave, at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(library.entries().count, 2, "a news file is not a save")
        XCTAssertEqual(library.news(for: manual).items.first?.english, "Goal met")

        // Archiving the autosave takes its log along; deleting a save removes its log.
        try library.archiveAutosave()
        XCTAssertEqual(library.entries().count, 2)
        for entry in library.entries() { XCTAssertEqual(library.news(for: entry).items.count, entry.id == manual.id ? 1 : 1) }
        for entry in library.entries() { try library.delete(entry) }
        let left = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        XCTAssertEqual(left, [])

        // A damaged log is an empty one.
        let bad = try library.save(world, as: .manual, at: Date(timeIntervalSince1970: 3_000))
        try Data("not json".utf8).write(to: directory.appendingPathComponent(SaveLibrary.newsFile(of: bad.id)))
        XCTAssertEqual(library.news(for: bad).items.count, 0)
    }

    // MARK: - The challenge

    private func challenge(goals: [Goal], deadline: Int64 = 100, insolvency: Int64? = nil) -> Scenario {
        Scenario(id: "test.secretary", goals: goals, goldDays: deadline / 3, silverDays: deadline / 2, deadlineDays: deadline, insolvencyDays: insolvency)
    }

    func testAGoalMetIsWrittenAndPauses() throws {
        var world = try Self.world(day: 3)
        try world.startScenario(challenge(goals: [.dailyRiders(1)]))
        let session = GameSession(world: world, language: .english)
        // Run until a rider has paid, a day at a time.
        for _ in 0..<5 where session.news.items.first(where: { $0.category == .goal }) == nil {
            try run(session, ticks: 1_440)
            if session.world.clock.isPaused { session.togglePause() }
        }
        let goal = try XCTUnwrap(session.news.items.first { $0.category == .goal })
        XCTAssertTrue(goal.text(in: .english).hasPrefix("Goal met: "), goal.text(in: .english))
        XCTAssertTrue(goal.text(in: .traditionalChinese).hasPrefix("目標達成："))
        XCTAssertEqual(session.news.items.filter { $0.category == .goal }.count, 1, "a goal is written once")
        XCTAssertTrue(session.news.items.contains { $0.category == .scenario }, "the challenge was completed")
    }

    func testTheLastWeekOfAChallengeIsWrittenOnceAndPauses() throws {
        var world = try Self.world(day: 3)
        try world.startScenario(challenge(goals: [.population(10_000_000)], deadline: 20))
        let session = GameSession(world: world, language: .english)
        for _ in 0..<12 { try run(session, ticks: 1_440); if session.world.clock.isPaused { session.togglePause() } }
        let warnings = session.news.items.filter { $0.category == .deadline }
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].text(in: .traditionalChinese).hasPrefix("挑戰剩 "))
    }

    func testTheBankruptcyCountdownNeedsADeadlineAndARedBalance() throws {
        var world = try Self.world(day: 3, balance: Money(40_000))
        XCTAssertNil(world.insolvencyCountdown, "no challenge")
        try world.startScenario(challenge(goals: [.population(10_000_000)], insolvency: 23))
        XCTAssertNil(world.insolvencyCountdown, "cash is above zero")
        let session = GameSession(world: world, language: .english)
        try run(session, ticks: 1_440)
        XCTAssertLessThan(session.world.economy.balance, .zero)
        let left = try XCTUnwrap(session.world.insolvencyCountdown)
        XCTAssertEqual(left, 23 - (session.world.scenario?.insolventDays ?? 0))
        XCTAssertEqual(insolvencyCountdownText(23, in: .traditionalChinese), "破產倒數 23 天")
        XCTAssertEqual(insolvencyCountdownText(1, in: .english), "Bankruptcy in 1 day")
        let debt = try XCTUnwrap(session.news.items.first { $0.category == .debt })
        XCTAssertTrue(debt.text(in: .traditionalChinese).contains("破產倒數"), debt.text(in: .traditionalChinese))
    }

    // MARK: - The forecast

    func testTheForecastLooksSevenDaysAheadAndIsEmptyWithoutEvents() throws {
        let world = try Self.world(day: 37, managed: true)
        let forecast = world.forecast()
        XCTAssertEqual(forecast.count, 7)
        XCTAssertEqual(forecast.first?.date.day, 37)
        XCTAssertEqual(forecast.last?.holiday, .springFestival, "Lunar New Year starts on day 43")
        XCTAssertEqual(forecast.last?.text(in: .traditionalChinese), "晴 · 春節")
        XCTAssertNil(world.todayHoliday())
        XCTAssertEqual(try Self.world(day: 45).todayHoliday(), .springFestival)
        var off = world
        off.setDisruptions(nil)
        XCTAssertEqual(off.forecast(), [])
        XCTAssertNil(off.todaySymbol())
        XCTAssertEqual(world.todaySymbol(), "sun.max.fill")
    }
}
