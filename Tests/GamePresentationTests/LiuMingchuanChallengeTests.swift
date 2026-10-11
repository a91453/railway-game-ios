import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 153: the Liu Mingchuan challenge on the map from Keelung to
/// Hsinchu, its milestones, its riders and its steam trains.
final class LiuMingchuanChallengeTests: XCTestCase {
    func testTheMapReachesFromKeelungToHsinchuWithNothingBuilt() throws {
        let world = LiuMingchuanChallenge.make()
        XCTAssertEqual(world.bounds, LiuMingchuanChallenge.bounds)
        // Some 91 by 49 km: wider than a new game's 16 km, far smaller than
        // the whole of Taiwan.
        XCTAssertEqual(Double(world.bounds.width) / Double(WorldCoordinate.unitsPerMetre) / 1_000, 91, accuracy: 1)
        XCTAssertEqual(Double(world.bounds.height) / Double(WorldCoordinate.unitsPerMetre) / 1_000, 49, accuracy: 1)
        XCTAssertEqual(world.geoAnchor, LiuMingchuanChallenge.anchor)
        XCTAssertTrue(LiuMingchuanChallenge.towns.allSatisfy { world.bounds.contains($0.point) })
        XCTAssertTrue(world.stations.isEmpty)
        XCTAssertTrue(world.network.edges.isEmpty)
        XCTAssertEqual(world.economy.balance, LiuMingchuanChallenge.startingBalance)
        // Its land is read in round stations, none yet; its edges bring no
        // one from beyond the map.
        XCTAssertEqual(world.landBlocks, [])
        XCTAssertFalse(world.outsideConnections)
        XCTAssertNil(world.disruptions)
    }

    func testItsGoalsAreTheMilestonesAndTheRiders() throws {
        let world = LiuMingchuanChallenge.make()
        let state = try XCTUnwrap(world.scenario)
        XCTAssertEqual(state.scenario.id, "history.liuMingchuan")
        XCTAssertEqual(state.scenario.trainTypes, [.steam])
        XCTAssertEqual(state.scenario.goals.count, 5)
        XCTAssertEqual(state.scenario.goals.last, .dailyRiders(LiuMingchuanChallenge.ridersTarget))
        XCTAssertEqual(
            world.goalProgress(in: .traditionalChinese).map(\.title),
            ["獅球嶺：基隆—八堵", "基隆—大稻埕通車（1891）", "淡水河鐵橋：大稻埕—桃仔園", "延伸到新竹（1893）", "每日運量（人次）"]
        )
        XCTAssertEqual(Challenge.liuMingchuan.goalsText(in: .english).first, "Shiqiuling: Keelung to Badu")
        XCTAssertEqual(Challenge.named("history.liuMingchuan")?.map, .liuMingchuan)
        XCTAssertEqual(world.scenarioTitle(in: .traditionalChinese), "劉銘傳鐵路：基隆到新竹")
        XCTAssertTrue(Challenge.liuMingchuan.story(in: .traditionalChinese).contains("1891"))
        // The oldest era first.
        XCTAssertEqual(Challenge.history.map(\.id), ["history.liuMingchuan", "history.pingxi"])
        // A milestone's name is the Liu Mingchuan challenge's alone.
        XCTAssertEqual(Challenge.threeTowns.goalsText(in: .english).first, "Link all 3 towns by rail")
        // It saves and loads as it is.
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testOnlySteamTrainsRun() throws {
        var world = LiuMingchuanChallenge.make()
        XCTAssertEqual(world.offeredTrainTypes, [.steam])
        XCTAssertFalse(world.offersStandardCar)
        let train = try world.purchaseTrain(named: "騰雲號")
        XCTAssertEqual(train.type, .steam)
        XCTAssertEqual(train.performance.displayText(in: .traditionalChinese), "蒸汽列車 · 40 km/h · 0.4 / 1.2 km/h/s")
        XCTAssertEqual(train.typeText(in: .traditionalChinese), "蒸汽列車 · 每節 50 人 · 2 門")
        XCTAssertThrowsError(try world.setTrainType(train.id, to: nil)) { error in
            XCTAssertEqual((error as? GameError)?.playerMessage(in: .traditionalChinese), "這個年代還沒有標準車。")
        }
        // Without an era: the reference's types and the standard car.
        let free = GameWorld.newGame()
        XCTAssertEqual(free.offeredTrainTypes, TrainType.reference)
        XCTAssertTrue(free.offersStandardCar)
    }

    @MainActor
    func testTheLauncherWaitsForTheRealWorldData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Liu-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        launcher.startChallenge(Challenge.liuMingchuan)
        XCTAssertNil(launcher.session)
        XCTAssertEqual(launcher.message?.text, "實景資料還沒準備好。")
        // With the people, the towns the milestones name are read in.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        launcher.population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        launcher.startChallenge(Challenge.liuMingchuan)
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.scenario?.scenario.id, "history.liuMingchuan")
        XCTAssertFalse(world.landBlocks?.isEmpty ?? true)
        XCTAssertGreaterThan(world.totalResidents(), 100_000)
    }
}

/// Decision 153: the yellow-tit station master speaks for the history
/// challenges: their first words, the milestones, steam trains too short to
/// pay, and the festival coming.
final class ScenarioStationMasterTests: XCTestCase {
    func testTheStationMasterOpensCheersAndWarnsOnTheLiuMingchuanMap() throws {
        var world = LiuMingchuanChallenge.make()
        // Nothing built: the challenge's first words, not the blank map's.
        XCTAssertEqual(StationMasterAdvice(world: world), .scenarioWelcome(scenario: "history.liuMingchuan"))
        XCTAssertEqual(
            StationMasterAdvice(world: world)?.text(in: .traditionalChinese),
            "1887 年，巡撫要修台灣第一條鐵路：從基隆港穿過獅球嶺到大稻埕，再跨過淡水河鋪到新竹，6 年內完成。蒸汽列車每節只坐 50 人，列車要夠長。點「建設」再選「路網」開始吧！"
        )
        XCTAssertEqual(
            StationMasterAdvice.scenarioWelcome(scenario: "history.pingxi").text(in: .traditionalChinese),
            "平溪線交給我們了：這條為運煤而建的支線一直在虧錢。目標是每日運量 80,000 人次、一年淨利 \(PingxiChallenge.profitTarget.moneyText)。天燈節會有大批人潮湧進十分和平溪，先把列車準備好！"
        )

        // Keelung and Badu joined by a line with a steam train of one car:
        // a day later the company lost money, and the short train is why.
        let keelung = try world.buildStation(named: "基隆", at: LiuMingchuanChallenge.keelung.point).id
        let badu = try world.buildStation(named: "八堵", at: LiuMingchuanChallenge.badu.point).id
        let line = try world.createLine(named: "基隆線", stops: [keelung, badu]).id
        let train = try world.purchaseTrain(named: "騰雲號").id
        try world.assignTrain(train, to: line, pattern: nil)
        // Into the next day's first minute, when the midnight is settled
        // and judged.
        try world.advance(ticks: 1_441)
        let short = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(short, .shortSteamTrains(line: line, name: "基隆線"))
        XCTAssertTrue(short.isWorry)
        XCTAssertEqual(short.text(in: .traditionalChinese), "「基隆線」的蒸汽列車每節只坐 50 人，車廂太少會虧錢。把列車收回，加掛到 8 節以上吧。")

        // Long enough, it cheers the milestone met at that midnight instead.
        try world.setTrainCars(train, to: StationMasterAdvice.shortSteamCars)
        let met = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(met, .goalMet(scenario: "history.liuMingchuan", goal: 0, titles: ["Shiqiuling: Keelung to Badu", "獅球嶺：基隆—八堵"]))
        XCTAssertTrue(met.isCheer)
        XCTAssertEqual(met.text(in: .traditionalChinese), "獅球嶺打通了！基隆的列車開得到八堵了。")
        // A day on, the cheer is over: back to its first words for its
        // first three days.
        try world.advance(ticks: 1_440)
        XCTAssertEqual(StationMasterAdvice(world: world), .scenarioWelcome(scenario: "history.liuMingchuan"))
    }

    func testAGoalOfAnyChallengeAndTheEnd() {
        XCTAssertEqual(
            StationMasterAdvice.goalMet(scenario: "sandbox.threeTowns", goal: 1, titles: ["Riders a day", "每日運量（人次）"]).text(in: .traditionalChinese),
            "目標達成：每日運量（人次）！"
        )
        XCTAssertEqual(StationMasterAdvice.scenarioCompleted(rating: .gold).text(in: .traditionalChinese), "挑戰完成：金牌！路線照樣營運，繼續加油。")
        XCTAssertTrue(StationMasterAdvice.scenarioCompleted(rating: .bronze).isCheer)
    }

    func testTheFestivalIsAnnounced() throws {
        var world = GameWorld.newGame(eventSeed: 1)
        world.setDisruptions(nil)
        let middle = PlanPoint(x: world.bounds.width / 2, y: world.bounds.height / 2)
        let shifen = try world.buildStation(named: "十分", at: middle).id
        let pingxi = try world.buildStation(named: "平溪", at: PlanPoint(x: middle.x + 64_000, y: middle.y)).id
        let line = try world.createLine(named: "平溪線", stops: [shifen, pingxi]).id
        try world.assignTrain(try world.purchaseTrain(named: "T").id, to: line, pattern: nil)
        try world.startScenario(Scenario(
            id: "test.festival", goals: [.dailyRiders(1_000_000)], goldDays: 30, silverDays: 60, deadlineDays: 90,
            events: [ScenarioEvent(station: shifen, dayOfYear: 3, days: 3, boost: 1_500, notice: 2)]
        ))
        try world.advance(ticks: 1_441)
        let coming = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(coming, .festivalComing(days: 2, stations: ["十分"], percent: 150))
        XCTAssertEqual(coming.text(in: .traditionalChinese), "2 天後是天燈節，十分的旅客會多 150%。先加開列車吧。")
    }
}
