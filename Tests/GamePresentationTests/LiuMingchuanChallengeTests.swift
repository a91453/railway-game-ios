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
        // Its targets were measured without building materials (decision 157).
        XCTAssertFalse(world.hasBuildingMaterials)
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
