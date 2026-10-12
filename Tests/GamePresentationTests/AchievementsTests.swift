import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 181: the achievements, judged by the game's state,
/// kept on the device and announced at midnight.
final class AchievementsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AchievementsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testThereAre38WithUniqueIDsAndBothLanguages() {
        XCTAssertEqual(Achievement.all.count, 38)
        XCTAssertEqual(Set(Achievement.all.map(\.id)).count, 38)
        XCTAssertEqual(Achievement.all.filter(\.needsTourism).count, 4)
        XCTAssertEqual(Achievement.all.filter(\.needsRollingStockEconomics).count, 3)
        for achievement in Achievement.all {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                XCTAssertFalse(achievement.title(in: language).isEmpty)
                XCTAssertFalse(achievement.detail(in: language).isEmpty)
                XCTAssertFalse(achievement.how(in: language).isEmpty)
            }
        }
    }

    func testNothingIsMetByAnEmptyCompany() {
        let facts = AchievementFacts(world: .newGame())
        XCTAssertEqual(Achievement.all.filter { $0.isMet(by: facts) }.map(\.id), [])
    }

    func testCountsAreMetAtTheirThresholdAndShowProgress() throws {
        var facts = AchievementFacts(figures: CompanyFigures(bestDayRiders: 9_999, trackMetres: 10_000, stations: 25))
        let riders = try XCTUnwrap(Achievement.named("riders10k"))
        XCTAssertFalse(riders.isMet(by: facts))
        XCTAssertEqual(riders.progress(of: facts)?.now, 9_999)
        XCTAssertEqual(riders.progress(of: facts)?.need, 10_000)
        facts.figures.bestDayRiders = 10_000
        XCTAssertTrue(riders.isMet(by: facts))
        XCTAssertTrue(try XCTUnwrap(Achievement.named("track10")).isMet(by: facts))
        XCTAssertTrue(try XCTUnwrap(Achievement.named("stations25")).isMet(by: facts))
        XCTAssertFalse(try XCTUnwrap(Achievement.named("stations50")).isMet(by: facts))
        XCTAssertNil(try XCTUnwrap(Achievement.named("ringLine")).progress(of: facts), "a mark had or not")
    }

    func testTheScenariosMarks() throws {
        var facts = AchievementFacts()
        facts.completedScenario = "history.pingxi"
        XCTAssertTrue(try XCTUnwrap(Achievement.named("pingxi")).isMet(by: facts))
        XCTAssertFalse(try XCTUnwrap(Achievement.named("liuMingchuan")).isMet(by: facts))
        XCTAssertFalse(try XCTUnwrap(Achievement.named("challengeGold")).isMet(by: facts))
        facts.completedGold = true
        XCTAssertTrue(try XCTUnwrap(Achievement.named("challengeGold")).isMet(by: facts))
    }

    func testALineRunningBetweenTwoTownsMeetsTheFirstMarks() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        let facts = AchievementFacts(world: world)
        let met = Set(Achievement.all.filter { $0.isMet(by: facts) }.map(\.id))
        XCTAssertTrue(met.contains("firstFare"))
        XCTAssertFalse(met.contains("ringLine"))
        XCTAssertFalse(met.contains("highSpeed"))
        XCTAssertFalse(met.contains("hub"))
    }

    func testTheRecordsKeepTheDateAndAreReadBack() throws {
        let file = directory.appendingPathComponent(AchievementRecords.fileName)
        var records = AchievementRecords(file: file)
        XCTAssertEqual(records.count, 0)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let facts = AchievementFacts(figures: CompanyFigures(bestDayRiders: 1_500))
        let unlocked = records.unlock(meeting: facts, at: date)
        XCTAssertEqual(unlocked.map(\.id), ["firstFare", "riders1k"])
        XCTAssertEqual(records.unlock(meeting: facts, at: date).count, 0, "once only")
        let read = AchievementRecords(file: file)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read.unlocked["riders1k"], date)
    }

    func testADamagedFileIsNoneUnlocked() throws {
        let file = directory.appendingPathComponent(AchievementRecords.fileName)
        try Data("not json".utf8).write(to: file)
        XCTAssertEqual(AchievementRecords(file: file).count, 0)
    }

    @MainActor
    func testMidnightUnlocksAndTellsTheNewsUnlessItIsADemo() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        var sounds: [SoundCue] = []
        launcher.playSound = { sounds.append($0) }
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        let session = GameSession(world: world, language: .traditionalChinese)
        session.playSound = launcher.playSound
        session.news.isDemo = true
        launcher.checkAchievements(of: session)
        XCTAssertEqual(launcher.achievements.count, 0, "a demo unlocks nothing")
        session.news.isDemo = false
        launcher.checkAchievements(of: session)
        XCTAssertTrue(launcher.achievements.unlocked.keys.contains("firstFare"))
        XCTAssertEqual(session.news.items.filter { $0.category == .achievement }.count, launcher.achievements.count)
        XCTAssertTrue(session.news.items.contains { $0.text(in: .traditionalChinese).hasPrefix("解鎖成就：第一筆票收") })
        XCTAssertTrue(session.message?.text.hasPrefix("解鎖成就：") ?? false)
        XCTAssertFalse(session.news.items.contains { $0.category == .success }, "the status line is not written twice")
        XCTAssertTrue(sounds.contains(.income))
        let file = directory.appendingPathComponent(AchievementRecords.fileName)
        XCTAssertEqual(AchievementRecords(file: file).count, launcher.achievements.count)
    }

    /// Decision 181, later: the Pingxi challenge starts on running lines, so
    /// only its own marks can unlock there; the tutorial unlocks nothing; and
    /// the end of the typhoon season needs a railway.
    @MainActor
    func testAPrebuiltChallengeOnlyUnlocksItsOwnMarksAndTheTutorialNone() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        try world.advance(ticks: 2 * 1_440)
        try world.startScenario(Scenario(id: "history.pingxi", goals: [.equity(Money(1_000_000_000_000))], goldDays: 30, silverDays: 60, deadlineDays: 90))
        let session = GameSession(world: world, language: .english)
        launcher.checkAchievements(of: session)
        XCTAssertEqual(launcher.achievements.count, 0, "the demo's lines are not the player's work")
        XCTAssertEqual(GameLauncher.achievementScope(of: world), ["challengeGold", "pingxi"])
        XCTAssertNil(GameLauncher.achievementScope(of: try newGameLine(through: [towns[0], towns[1]])))

        let plain = GameSession(world: try newGameLine(through: [towns[0], towns[1]]), language: .english)
        plain.startTutorial()
        launcher.checkAchievements(of: plain)
        XCTAssertEqual(launcher.achievements.count, 0, "the tutorial game unlocks nothing")
    }

    func testTheTyphoonSeasonMarkNeedsARailway() throws {
        var empty = GameWorld.newGame()
        try empty.advance(ticks: 300 * 1_440)
        XCTAssertFalse(AchievementFacts(world: empty).typhoonSeasonOverDebtFree)
    }

    func testTheDemoMarkIsKeptWithTheNews() throws {
        var log = NewsLog()
        log.isDemo = true
        let read = try JSONDecoder().decode(NewsLog.self, from: JSONEncoder().encode(log))
        XCTAssertTrue(read.isDemo)
        let plain = try JSONDecoder().decode(NewsLog.self, from: JSONEncoder().encode(NewsLog()))
        XCTAssertFalse(plain.isDemo)
    }
}

extension AchievementsTests {
    func testProgressIsReadInKilometresForLengths() throws {
        let facts = AchievementFacts(figures: CompanyFigures(bestDayRiders: 31_200, trackMetres: 12_400))
        XCTAssertEqual(try XCTUnwrap(Achievement.named("track50")).progressText(of: facts), "12.4 / 50.0 km")
        XCTAssertEqual(try XCTUnwrap(Achievement.named("riders100k")).progressText(of: facts), "31,200 / 100,000")
        XCTAssertNil(try XCTUnwrap(Achievement.named("tower")).progressText(of: facts))
    }
}

extension AchievementsTests {
    func testTheTouristsAndBusinessesMarks() throws {
        var facts = AchievementFacts()
        facts.hasTourism = true
        facts.touristsInAYear = 120_000
        facts.bestStars = 450
        facts.bestSouvenirShop = 2
        XCTAssertTrue(try XCTUnwrap(Achievement.named("tourists100k")).isMet(by: facts))
        XCTAssertTrue(try XCTUnwrap(Achievement.named("souvenirShop")).isMet(by: facts))
        XCTAssertFalse(try XCTUnwrap(Achievement.named("fiveStars")).isMet(by: facts))
        XCTAssertEqual(try XCTUnwrap(Achievement.named("fiveStars")).progressText(of: facts), "4.5 / 5.0 ★")
        facts.subsidiaries = 2
        facts.subsidiaryKinds = 2
        facts.bestSubsidiaryProfit = Money(40_000_000)
        XCTAssertTrue(try XCTUnwrap(Achievement.named("firstSubsidiary")).isMet(by: facts))
        XCTAssertFalse(try XCTUnwrap(Achievement.named("allBusinesses")).isMet(by: facts))
        XCTAssertEqual(try XCTUnwrap(Achievement.named("businessProfit")).progressText(of: facts), "$ 400,000 / $ 1,000,000")
    }

    func testAWorldWithAttractionsIsRead() throws {
        var world = GameWorld.newGame(eventSeed: 1)
        world.setTourism(nil)
        XCTAssertFalse(AchievementFacts(world: world).hasTourism)
        world.foundAttractions(seed: 1)
        let facts = AchievementFacts(world: world)
        XCTAssertTrue(facts.hasTourism)
        XCTAssertGreaterThan(facts.bestStars, 0)
        XCTAssertEqual(facts.touristsInAYear, 0)
    }
}

extension AchievementsTests {
    func testTheRollingStockMarksAndWhereTheyAreListed() throws {
        var facts = AchievementFacts()
        facts.trainTypes = 3
        facts.longestTrainCars = 8
        facts.rollingStockCost = Money(120_000_000)
        XCTAssertFalse(try XCTUnwrap(Achievement.named("mixedFleet")).isMet(by: facts), "not where trains are priced flat")
        facts.hasRollingStockEconomics = true
        XCTAssertTrue(try XCTUnwrap(Achievement.named("mixedFleet")).isMet(by: facts))
        facts.hasRollingStockEconomics = false
        XCTAssertFalse(try XCTUnwrap(Achievement.named("longTrain")).isMet(by: facts))
        XCTAssertEqual(try XCTUnwrap(Achievement.named("fleetInvestment")).progressText(of: facts), "$ 1,200,000 / $ 5,000,000")
        let mixed = try XCTUnwrap(Achievement.named("mixedFleet"))
        XCTAssertTrue(mixed.isListed(for: nil), "the start screen lists every one")
        XCTAssertFalse(mixed.isListed(for: facts))
        facts.hasRollingStockEconomics = true
        XCTAssertTrue(mixed.isListed(for: facts))
        XCTAssertTrue(try XCTUnwrap(Achievement.named("firstFare")).isListed(for: facts))
    }

    func testAWorldPricingItsTrainsIsRead() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.setRollingStockEconomics(true)
        let facts = AchievementFacts(world: world)
        XCTAssertTrue(facts.hasRollingStockEconomics)
        XCTAssertEqual(facts.trainTypes, 1)
        XCTAssertEqual(facts.longestTrainCars, 4)
    }
}

extension AchievementsTests {
    /// Decision 180's later fix: the three rolling-stock marks are had only
    /// where trains are priced by type. A challenge or an old save prices
    /// them flat, but a train there still takes ten cars or a type, free.
    @MainActor
    func testTheRollingStockMarksAreNotHadWhereTrainsArePricedFlat() throws {
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        world.setRollingStockEconomics(false)
        let train = try world.purchaseTrain(named: "Long").id
        try world.setTrainCars(train, to: 10)
        XCTAssertEqual(AchievementFacts(world: world).longestTrainCars, 10)
        launcher.checkAchievements(of: GameSession(world: world, language: .english))
        XCTAssertNil(launcher.achievements.unlocked["longTrain"], "not listed in this game, so not had in it")

        world.setRollingStockEconomics(true)
        launcher.checkAchievements(of: GameSession(world: world, language: .english))
        XCTAssertNotNil(launcher.achievements.unlocked["longTrain"])
    }
}
