import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 289: the branch-line challenges, played as the Liu Mingchuan
/// challenge is: a real map round the line with nothing built, its
/// milestones, its riders and its sights. The Jiji Line first.
final class BranchLineChallengeTests: XCTestCase {
    let jiji = BranchLineChallenge.jiji

    func testTheJijiMapReachesFromErshuiToChechengWithNothingBuilt() throws {
        let world = jiji.make()
        XCTAssertEqual(world.bounds, jiji.bounds)
        // Some 33 by 10 km round the line's 30 km.
        XCTAssertEqual(Double(world.bounds.width) / Double(WorldCoordinate.unitsPerMetre) / 1_000, 33, accuracy: 1)
        XCTAssertEqual(Double(world.bounds.height) / Double(WorldCoordinate.unitsPerMetre) / 1_000, 10, accuracy: 1)
        XCTAssertEqual(world.geoAnchor, jiji.anchor)
        XCTAssertTrue(jiji.townPoints.allSatisfy { world.bounds.contains($0) })
        XCTAssertTrue(world.stations.isEmpty)
        XCTAssertTrue(world.network.edges.isEmpty)
        XCTAssertEqual(world.economy.balance, jiji.startingBalance)
        XCTAssertEqual(world.landBlocks, [])
        XCTAssertFalse(world.outsideConnections)
        XCTAssertNil(world.disruptions)
        XCTAssertFalse(world.hasBuildingMaterials)
        // Its two sights: Jiji Station and Checheng, both on the line.
        XCTAssertEqual(world.tourism?.attractions.map(\.name), ["集集車站", "車埕"])
        // Any train runs: the line has no era.
        XCTAssertEqual(world.offeredTrainTypes, TrainType.offered)
    }

    func testItsGoalsAreTheMilestonesAndTheRiders() throws {
        let world = jiji.make()
        let state = try XCTUnwrap(world.scenario)
        XCTAssertEqual(state.scenario.id, "branch.jiji")
        XCTAssertEqual(state.scenario.goals.last, .dailyRiders(JijiTargets.riders))
        XCTAssertEqual(
            world.goalProgress(in: .traditionalChinese).map(\.title),
            ["二水—集集", "延伸到水里", "終點車埕", "每日運量（人次）"]
        )
        let challenge = try XCTUnwrap(Challenge.named("branch.jiji"))
        XCTAssertEqual(challenge.map, .branchLine("jiji"))
        XCTAssertEqual(challenge.goalsText(in: .english).first, "Ershui to Jiji")
        XCTAssertEqual(world.scenarioTitle(in: .traditionalChinese), "集集線：木業與水力")
        XCTAssertTrue(challenge.story(in: .traditionalChinese).contains("1927"))
        XCTAssertEqual(BranchLineChallenge.named("branch.jiji")?.id, "jiji")
        XCTAssertEqual(BranchLineChallenge.line("jiji")?.challengeID, "branch.jiji")
        XCTAssertNil(BranchLineChallenge.named("history.pingxi"))
        // It saves and loads as it is.
        let data = try JSONEncoder().encode(SavedGame(world: world))
        XCTAssertEqual(try JSONDecoder().decode(SavedGame.self, from: data).world, world)
    }

    func testTheStationMasterOpensAndCheersTheMilestones() throws {
        var world = jiji.make()
        XCTAssertEqual(StationMasterAdvice(world: world), .scenarioWelcome(scenario: "branch.jiji"))
        XCTAssertTrue(try XCTUnwrap(StationMasterAdvice(world: world)?.text(in: .traditionalChinese)).hasPrefix("集集線交給我們重新鋪"))
        // Ershui and Jiji joined by a line with a train: at the next
        // midnight the first milestone is met and cheered.
        let ershui = try world.buildStation(named: "二水", at: jiji.townPoints[0]).id
        let station = try world.buildStation(named: "集集", at: jiji.townPoints[1]).id
        let line = try world.createLine(named: "集集線", stops: [ershui, station]).id
        let train = try world.purchaseTrain(named: "集集 1").id
        try world.assignTrain(train, to: line, pattern: nil)
        try world.advance(ticks: 1_441)
        let met = try XCTUnwrap(StationMasterAdvice(world: world))
        XCTAssertEqual(met, .goalMet(scenario: "branch.jiji", goal: 0, titles: ["Ershui to Jiji", "二水—集集"]))
        XCTAssertEqual(met.text(in: .traditionalChinese), "二水的列車開到集集了，木造車站迎接遊客！")
    }

    @MainActor
    func testTheLauncherWaitsForTheRealWorldData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Jiji-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese)
        let challenge = try XCTUnwrap(Challenge.named("branch.jiji"))
        launcher.startChallenge(challenge)
        XCTAssertNil(launcher.session)
        XCTAssertEqual(launcher.message?.text, "實景資料還沒準備好。")
        // With the people, the line's towns are read in.
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        launcher.population = try PopulationGrid(data: Data(contentsOf: root.appendingPathComponent("RailwayGameApp/Resources/RealWorld/taiwan_population.json")))
        launcher.startChallenge(challenge)
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.scenario?.scenario.id, "branch.jiji")
        XCTAssertFalse(world.landBlocks?.isEmpty ?? true)
        XCTAssertGreaterThan(world.totalResidents(), 10_000)
    }
}
