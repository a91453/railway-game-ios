import Foundation
import GameCore
import GamePresentation
import XCTest

/// ARCHITECTURE decision 177: the first minutes. A short first line that
/// loses money is told to reach the next town (not to raise fares), the
/// nearest town without a station is found from the land, a loss floats red
/// and keeps the coins quiet, the new game takes the player's options, the
/// first-time card remembers, and the help guide is searchable.
final class OnboardingTests: XCTestCase {
    private static let tile = Int64(1_024)

    /// A short line inside the first town: two stations 640 m apart, near
    /// enough that few ride, with a train. A managed company.
    private func shortLine(seed: UInt32 = 1) throws -> GameWorld {
        let towns = Land.townCentres(seed: seed, in: GameWorld.newGameBounds)
        let a = towns[0]
        let b = PlanPoint(x: a.x + 10 * Self.tile, y: a.y)
        return try newGameLine(through: [a, b], in: .newGame(eventSeed: seed))
    }

    // MARK: - The nearest town without a station

    func testTheNearestUnservedTownIsFoundFromTheStations() throws {
        let world = try shortLine()
        let clusters = UnservedCluster.all(in: world)
        XCTAssertFalse(clusters.isEmpty, "the other towns are not served")
        XCTAssertEqual(clusters.map(\.people), clusters.map(\.people).sorted(by: >), "the biggest first")
        for cluster in clusters {
            for station in world.stations {
                let dx = cluster.center.x - station.location.x, dy = cluster.center.y - station.location.y
                XCTAssertGreaterThan(dx * dx + dy * dy, 0)
            }
        }
        let found = try XCTUnwrap(UnservedCluster.nearestToTheRailway(in: world))
        XCTAssertGreaterThanOrEqual(found.cluster.people, UnservedCluster.minimumPeople)
        let direction = found.cluster.direction(from: found.from)
        XCTAssertGreaterThan(direction.tenthsOfKm, 0)
    }

    func testAServedTownIsNotUnserved() throws {
        var world = try makeWorld(width: 1_048_576, height: 1_048_576, balance: 100_000_000)
        try world.setLand([
            LandCell(row: 100, column: 100, use: .residential, residents: 2_000, jobs: 0),
            LandCell(row: 100, column: 150, use: .residential, residents: 3_000, jobs: 0),
            LandCell(row: 100, column: 151, use: .park, residents: 0, jobs: 0),
        ])
        // No station: everything is unserved, the park aside.
        XCTAssertEqual(UnservedCluster.all(in: world).map(\.people), [3_000, 2_000])
        XCTAssertNil(UnservedCluster.nearestToTheRailway(in: world), "no station to extend from")
        XCTAssertEqual(UnservedCluster.largest(in: world)?.people, 3_000)

        let west = try world.buildTrackNode(at: WorldCoordinate(x: 100 * Land.cellLength - 4_096, y: 100 * Land.cellLength + 2_048))
        let east = try world.buildTrackNode(at: WorldCoordinate(x: 100 * Land.cellLength + 20_480, y: 100 * Land.cellLength + 2_048))
        try world.buildTrackEdge(from: west, to: east)
        try world.buildStation(named: "A", at: PlanPoint(x: 100 * Land.cellLength + 2_048, y: 100 * Land.cellLength + 2_048))
        XCTAssertEqual(UnservedCluster.all(in: world).map(\.people), [3_000], "the station's 800 m reach the first town")
        let found = UnservedCluster.nearestToTheRailway(in: world)
        XCTAssertEqual(found?.cluster.people, 3_000)
        XCTAssertEqual(found?.cluster.direction(from: try XCTUnwrap(found?.from)).compass, .east)
    }

    func testTheCompassPoints() {
        let cluster = UnservedCluster(center: PlanPoint(x: 64_000, y: 0), people: 1)
        let origin = PlanPoint(x: 0, y: 0)
        XCTAssertEqual(cluster.direction(from: origin).compass, .east)
        XCTAssertEqual(cluster.direction(from: origin).tenthsOfKm, 10, "1 km = 64,000 units")
        XCTAssertEqual(UnservedCluster(center: PlanPoint(x: 64_000, y: -64_000), people: 1).direction(from: origin).compass, .northeast)
        XCTAssertEqual(UnservedCluster(center: PlanPoint(x: 0, y: 64_000), people: 1).direction(from: origin).compass, .south)
        XCTAssertEqual(UnservedCluster(center: PlanPoint(x: -64_000, y: 64_000), people: 1).direction(from: origin).compass, .southwest)
        XCTAssertEqual(UnservedCluster(center: PlanPoint(x: -64_000, y: 2_000), people: 1).direction(from: origin).compass, .west)
        XCTAssertEqual(UnservedCluster(center: PlanPoint(x: 2_000, y: -64_000), people: 1).direction(from: origin).compass, .north)
        XCTAssertEqual(UnservedCluster.Compass.northeast.title(in: .traditionalChinese), "東北")
    }

    // MARK: - The station master

    /// A managed company with `points` joined by a line, whose cash was
    /// just enough to build it, and which then runs `days` days with nobody
    /// riding: in the red.
    private func broke(through points: [PlanPoint], days: Int) throws -> GameWorld {
        let rich = try newGameLine(through: points)
        let cost = GameWorld.startingBalance.amount - rich.economy.balance.amount
        var world = try newGameLine(through: points, in: .newGame(balance: Money(cost + 1), eventSeed: 1))
        world.setEconomyMode(.management)
        world.setLandDemand(false)
        for station in world.stations {
            try world.setStationDemand(station.id, to: StationDemand(kind: .residential, dailyTrips: 0))
        }
        world.setSpeed(.normal)
        try world.advance(ticks: days * 1_440)
        return world
    }

    func testAShortLineInDebtIsToldToExtendNotToRaiseFares() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        // After the first month, the coaching of the first line is over,
        // but the debt is still a short line's.
        let world = try broke(through: [towns[0], PlanPoint(x: towns[0].x + 10 * Self.tile, y: towns[0].y)], days: 40)
        XCTAssertEqual(world.stations.count, 2)
        XCTAssertLessThan(world.economy.balance, .zero)
        guard case .inDebtShortLine(let hint)? = StationMasterAdvice(world: world) else {
            return XCTFail("a short line in debt extends: \(String(describing: StationMasterAdvice(world: world)))")
        }
        let advice = StationMasterAdvice.inDebtShortLine(hint: hint)
        XCTAssertTrue(advice.isWorry)
        let text = advice.text(in: .english)
        XCTAssertFalse(text.contains("Raise fares"))
        XCTAssertTrue(text.contains("Extend"), text)
        XCTAssertEqual(advice.cameraTarget, hint?.target)
        XCTAssertNotNil(hint, "the other towns are there to extend to")
    }

    func testALongerRailwayInDebtIsStillToldToRaiseFares() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        let a = towns[0]
        let points = (0..<4).map { PlanPoint(x: a.x + Int64($0) * 20 * Self.tile, y: a.y) }
        let world = try broke(through: points, days: 40)
        XCTAssertEqual(world.stations.count, 4)
        XCTAssertLessThan(world.economy.balance, .zero)
        XCTAssertEqual(StationMasterAdvice(world: world), .inDebt)
    }

    func testTheFirstLineLosingNamesTheLossAndThePlaceToGo() {
        let hint = StationMasterAdvice.ExtensionHint(compass: .northeast, tenthsOfKm: 42, target: PlanPoint(x: 9, y: 9))
        let advice = StationMasterAdvice.firstLineLosing(loss: Money(4_047_400), hint: hint)
        XCTAssertEqual(
            advice.text(in: .english),
            "This line lost $ 40,474 yesterday: the stations are too close and too few ride. Extend it to the next town: the nearest populated area with no station is 4.2 km northeast. Tap to look."
        )
        XCTAssertEqual(
            advice.text(in: .traditionalChinese),
            "這條線昨天虧了 $ 40,474：站太近、坐的人太少。把線延伸到下一個城鎮，最近、還沒有車站的人口熱區在東北方 4.2 公里。點一下看位置。"
        )
        XCTAssertEqual(advice.cameraTarget, PlanPoint(x: 9, y: 9))
        XCTAssertTrue(advice.isWorry)
        XCTAssertNil(StationMasterAdvice.firstLineLosing(loss: Money(1), hint: nil).cameraTarget)
    }

    func testAShortLineThatLostMoneyYesterdayIsToldSoInTheFirstMonth() throws {
        var world = try shortLine()
        // Nobody rides: the train costs and earns nothing.
        world.setLandDemand(false)
        for station in world.stations {
            try world.setStationDemand(station.id, to: StationDemand(kind: .residential, dailyTrips: 0))
        }
        world.setSpeed(.normal)
        try world.advance(ticks: 3 * 1_440)
        guard case .firstLineLosing(let loss, _)? = StationMasterAdvice(world: world) else {
            return XCTFail("a losing first line: \(String(describing: StationMasterAdvice(world: world)))")
        }
        XCTAssertGreaterThan(loss, .zero)
        // A scenario's rules coach itself: free play only.
        XCTAssertNil(world.scenario)
    }

    /// A line nobody has put a train on is not "losing money": the station
    /// master does not blame its stations.
    func testAShortLineWithNoTrainIsNotCalledLosing() throws {
        var world = try shortLine()
        for train in world.trains.map(\.id) {
            try world.unassignTrain(train)
        }
        world.setSpeed(.normal)
        try world.advance(ticks: 3 * 1_440)
        if case .firstLineLosing? = StationMasterAdvice(world: world) {
            XCTFail("a line with no train yet")
        }
    }

    // MARK: - Feedback

    func testALossFloatsRedAndShort() {
        XCTAssertEqual(IncomePulse(amount: Money(123_400), serial: 1).text, "+$ 1,234")
        XCTAssertFalse(IncomePulse(amount: Money(123_400), serial: 1).isLoss)
        let loss = IncomePulse(amount: Money(-4_047_400), serial: 2)
        XCTAssertTrue(loss.isLoss)
        XCTAssertEqual(loss.text, "\u{2212}$40k")
        XCTAssertEqual(IncomePulse(amount: Money(-250_000), serial: 3).text, "\u{2212}$2,500", "under $10,000 to the dollar")
    }

    @MainActor
    func testADayThatClosesInTheRedFloatsItsLossAndTheCoinsStayQuiet() throws {
        var world = try shortLine()
        world.setLandDemand(false)
        // No tourists either (decision 174): nothing comes in.
        world.setTourism(nil)
        for station in world.stations {
            try world.setStationDemand(station.id, to: StationDemand(kind: .residential, dailyTrips: 0))
        }
        let session = GameSession(world: world)
        var heard: [SoundCue] = []
        session.playSound = { heard.append($0) }
        session.setSpeed(.normal)
        // Two days and a bit: day 0 closes at the first midnight.
        for _ in 0..<(2 * 1_440 + 5) {
            session.advance(realElapsed: GameSession.tickInterval)
        }
        let pulse = try XCTUnwrap(session.incomePulse)
        XCTAssertTrue(pulse.isLoss, "the last thing the cash floated was a loss")
        XCTAssertFalse(heard.contains(.income), "nothing came in")
    }

    // MARK: - New game options

    func testTheDefaultOptionsAreTheNewGameAsItWas() {
        let options = NewGameOptions()
        XCTAssertEqual(options.startingBalance, GameWorld.startingBalance)
        XCTAssertEqual(options.disruption, .light)
        var world = GameWorld.newGame(eventSeed: 7, buysMap: true)
        let before = world
        options.apply(to: &world)
        XCTAssertEqual(world, before)
    }

    func testTheDifficultiesSetTheCashAndTheDisruptions() {
        var easy = NewGameOptions()
        easy.difficulty = .easy
        XCTAssertEqual(easy.startingBalance, Money(500_000_000))
        XCTAssertEqual(easy.disruption, .off)
        var expert = NewGameOptions()
        expert.difficulty = .expert
        XCTAssertEqual(expert.startingBalance, Money(150_000_000))
        expert.disruptionChoice = .light
        XCTAssertEqual(expert.disruption, .light, "chosen apart from the difficulty")

        var world = GameWorld.newGame(balance: easy.startingBalance, eventSeed: 7)
        easy.apply(to: &world)
        XCTAssertNil(world.disruptions)
        XCTAssertEqual(world.economy.balance, Money(500_000_000))
        var hard = NewGameOptions()
        hard.difficulty = .expert
        var strict = GameWorld.newGame(eventSeed: 7)
        hard.apply(to: &strict)
        XCTAssertEqual(strict.disruptions?.level, .standard)
        XCTAssertEqual(strict.disruptions?.seed, 7, "the same events, harder")
    }

    func testTheRulesTurnOff() {
        var options = NewGameOptions()
        options.buildingMaterials = false
        options.outsideConnections = false
        var world = GameWorld.newGame(eventSeed: 3)
        XCTAssertTrue(world.outsideConnections)
        XCTAssertEqual(world.freight?.buildingMaterials, true)
        options.apply(to: &world)
        XCTAssertFalse(world.outsideConnections)
        XCTAssertNotEqual(world.freight?.buildingMaterials, true)
    }

    func testTheSeedIsDigitsOnly() {
        XCTAssertEqual(NewGameOptions.seed(from: " 4294967295 "), 4_294_967_295)
        XCTAssertNil(NewGameOptions.seed(from: "4294967296"))
        XCTAssertNil(NewGameOptions.seed(from: "abc"))
        XCTAssertNil(NewGameOptions.seed(from: ""))
        var options = NewGameOptions()
        options.seed = 42
        XCTAssertEqual(options.eventSeed(), 42)
        XCTAssertTrue(options.summary(in: .english).contains("Seed 42."))
        XCTAssertTrue(options.summary(in: .traditionalChinese).contains("種子 42"))
    }

    func testTheSummarySaysWhatChanged() {
        var options = NewGameOptions()
        XCTAssertTrue(options.summary(in: .english).hasPrefix("Starts with $ 3,000,000."))
        options.buildingMaterials = false
        XCTAssertTrue(options.summary(in: .english).contains("Changed: towns grow without building materials"))
        XCTAssertTrue(options.summary(in: .traditionalChinese).contains("已更改：城市不需要建材就能成長"))
    }

    // MARK: - The launcher

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("OnboardingTests-\(UUID().uuidString)", isDirectory: true)
    }

    @MainActor
    func testANewGameTakesTheOptionsAndTheyAreKept() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        var options = launcher.newGameOptions
        options.difficulty = .easy
        options.seed = 99
        options.buysMap = false
        launcher.newGameOptions = options
        launcher.startNewGame()
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.economy.balance, Money(500_000_000))
        XCTAssertNil(world.disruptions)
        XCTAssertEqual(world.demandEvents?.seed, 99)
        XCTAssertNil(world.mapExpansion, "the usual map, not bought tile by tile")
        XCTAssertEqual(world.bounds, GameWorld.newGameBounds)

        // Another launch finds the same options.
        let again = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertEqual(again.newGameOptions, options)
        XCTAssertFalse(again.isFirstLaunch)
    }

    @MainActor
    func testTheFirstTimeCardShowsUntilTheTutorialIsDoneOrClosed() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertTrue(launcher.isFirstLaunch)
        XCTAssertTrue(launcher.preferences.hasLaunched)
        XCTAssertTrue(launcher.showsFirstGameCard)

        launcher.dismissFirstGameCard()
        XCTAssertFalse(launcher.showsFirstGameCard)
        let later = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        XCTAssertFalse(later.isFirstLaunch)
        XCTAssertFalse(later.showsFirstGameCard, "closed for good")
    }

    @MainActor
    func testFinishingTheTutorialRemembersIt() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        let session = try XCTUnwrap(launcher.session)
        session.skipTutorial()
        XCTAssertFalse(launcher.preferences.tutorialCompleted, "Skip is not finishing")
        session.onTutorialCompleted?()
        XCTAssertTrue(launcher.preferences.tutorialCompleted)
        launcher.returnToStart()
        XCTAssertFalse(launcher.showsFirstGameCard)
    }

    @MainActor
    func testAPlayerWithGamesIsNotAskedIfItIsTheirFirstTime() throws {
        let directory = makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        launcher.returnToStart()
        XCTAssertFalse(launcher.entries.isEmpty)
        XCTAssertFalse(launcher.showsFirstGameCard)
    }

    // MARK: - The help guide

    func testTheGuideAnswersTheQuestionsInBothLanguages() {
        XCTAssertGreaterThanOrEqual(HelpGuide.entries.count, 14)
        XCTAssertEqual(Set(HelpGuide.entries.map(\.id)).count, HelpGuide.entries.count, "ids are unique")
        for entry in HelpGuide.entries {
            XCTAssertFalse(entry.question(in: .english).isEmpty)
            XCTAssertNotEqual(entry.question(in: .english), entry.question(in: .traditionalChinese), entry.id)
            XCTAssertNotEqual(entry.answer(in: .english), entry.answer(in: .traditionalChinese), entry.id)
            XCTAssertEqual(entry.otherAnswer(than: .english), entry.answer(in: .traditionalChinese))
        }
        for topic in HelpEntry.Topic.allCases {
            XCTAssertTrue(HelpGuide.entries.contains { $0.topic == topic }, "no empty section")
        }
    }

    func testTheGuideIsSearchableInEitherLanguage() {
        XCTAssertEqual(HelpGuide.entries(matching: "").count, HelpGuide.entries.count)
        XCTAssertEqual(HelpGuide.entries(matching: "   ").count, HelpGuide.entries.count)
        XCTAssertTrue(HelpGuide.entries(matching: "extend").contains { $0.id == "extendLine" })
        XCTAssertTrue(HelpGuide.entries(matching: "延長").contains { $0.id == "extendLine" })
        XCTAssertTrue(HelpGuide.entries(matching: "LOAN").contains { $0.id == "loan" })
        XCTAssertTrue(HelpGuide.entries(matching: "貸款").contains { $0.id == "loan" })
        XCTAssertEqual(HelpGuide.entries(matching: "express 快車").map(\.id), ["express"], "every word must match")
        XCTAssertTrue(HelpGuide.entries(matching: "zzzz").isEmpty)
        for id in ["extendLine", "whyLosing", "cityGrowth", "materials", "buyMap", "loan", "fares", "trafficControl", "express", "annualReport"] {
            XCTAssertTrue(HelpGuide.entries.contains { $0.id == id }, id)
        }
    }
}
