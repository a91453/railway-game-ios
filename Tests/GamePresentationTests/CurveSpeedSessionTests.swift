import Foundation
import GameCore
import GamePresentation
import XCTest

/// Curve speed limits where the app meets them (ARCHITECTURE decision
/// 217): a new game keeps to them, and the worlds measured without them
/// (the demos, the challenges, the tutorial) keep them off, as an old save
/// does.
@MainActor
final class CurveSpeedSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CurveSpeedSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewGameKeepsToTheCurveLimits() {
        XCTAssertTrue(GameWorld.newGame().curveSpeedLimits)
        XCTAssertTrue(GameWorld.newGame(eventSeed: 7).curveSpeedLimits)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        // Decision 258: under the realistic rules; the default simple ones
        // keep it off.
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.curveSpeedLimits, false)
        launcher.returnToStart()
        launcher.newGameOptions.rules = .realistic
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.curveSpeedLimits, true)
    }

    func testTheMeasuredWorldsKeepThemOff() {
        XCTAssertFalse(DemoWorld.make(in: .english).curveSpeedLimits)
        for challenge in Challenge.sandbox {
            XCTAssertFalse(GameWorld.newGame(challenge: challenge, eventSeed: 7).curveSpeedLimits, challenge.id)
        }
        XCTAssertFalse(LiuMingchuanChallenge.make().curveSpeedLimits)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.world.curveSpeedLimits, false)
    }
}
