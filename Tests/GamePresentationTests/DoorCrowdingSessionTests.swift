import Foundation
import GameCore
import GamePresentation
import XCTest

/// Door crowding and the EMU3000 where the app meets them (ARCHITECTURE
/// decision 169): a new game's doors slow in a crowd, the worlds whose
/// numbers were measured without the rule keep it off, and the EMU3000 is in
/// the type menu with its text and its way of running.
@MainActor
final class DoorCrowdingSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DoorCrowdingSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewGameTurnsDoorCrowdingOn() throws {
        XCTAssertTrue(GameWorld.newGame().doorCrowding, "a new game's full train dwells longer")
        XCTAssertTrue(GameWorld.newGame(eventSeed: 7).doorCrowding)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        // Decision 256: under the realistic rules; the default simple ones
        // keep it off.
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.doorCrowding, false)
        launcher.returnToStart()
        launcher.newGameOptions.rules = .realistic
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.doorCrowding, true)
    }

    /// The demos' economies and the challenges' targets were measured without
    /// it (decisions 154 and 157 keep holidays and building materials out of
    /// them the same way).
    func testTheMeasuredWorldsKeepItOff() {
        XCTAssertFalse(DemoWorld.make(in: .english).doorCrowding)
        for challenge in Challenge.sandbox {
            XCTAssertFalse(GameWorld.newGame(challenge: challenge, eventSeed: 7).doorCrowding, challenge.id)
        }
        XCTAssertFalse(LiuMingchuanChallenge.make().doorCrowding)
    }

    func testTheTutorialsWorldKeepsItOff() {
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.world.doorCrowding, false)
    }

    func testTheEMU3000IsOfferedNamedAndRunsAsTheReferenceHasIt() throws {
        var world = GameWorld.newGame()
        XCTAssertTrue(world.offeredTrainTypes.contains(.emu3000))
        let offered = world.offeredTrainTypes
        // Decision 252's Taiwan Railway models come after it.
        XCTAssertEqual(offered.firstIndex(of: .emu3000), offered.firstIndex(of: .highSpeed).map { $0 + 1 }, "after the high-speed set")
        XCTAssertEqual(TrainType.emu3000.title(in: .english), "New Tze-Chiang")
        XCTAssertEqual(TrainType.emu3000.title(in: .traditionalChinese), "新自強號")
        XCTAssertEqual(Train.typeText(.emu3000, in: .english), "New Tze-Chiang · 45 a car · 2 doors")
        XCTAssertEqual(Train.typeText(.emu3000, in: .traditionalChinese), "新自強號 · 每節 45 人 · 2 門")

        // Given to a train still running as standard, it runs as the EMU3000
        // does, in the same edit; a train the player gave a performance keeps it.
        let id = try world.purchaseTrain(named: "Express").id
        let session = GameSession(world: world)
        session.selectTrain(id)
        XCTAssertEqual(session.world.train(id: id)?.performance, .standard)
        session.setSelectedTrainType(.emu3000)
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertEqual(session.world.train(id: id)?.type, .emu3000)
        XCTAssertEqual(session.world.train(id: id)?.performance, .emu3000)
        session.setSelectedTrainPerformance(.express)
        session.setSelectedTrainType(.a)
        session.setSelectedTrainType(.emu3000)
        XCTAssertEqual(session.world.train(id: id)?.performance, .express)
    }
}
