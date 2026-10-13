import Foundation
import GameCore
import GamePresentation
import XCTest

/// Keeping left where the app meets it (ARCHITECTURE decision 202): a new
/// game's trains keep left on double track, and the worlds whose routes were
/// measured without the rule (the demos, the challenges, the tutorial) keep
/// it off, as an old save does.
@MainActor
final class KeepLeftSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KeepLeftSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewGameKeepsLeft() {
        XCTAssertTrue(GameWorld.newGame().keepLeft)
        XCTAssertTrue(GameWorld.newGame(eventSeed: 7).keepLeft)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.keepLeft, true)
    }

    func testTheMeasuredWorldsKeepItOff() {
        XCTAssertFalse(DemoWorld.make(in: .english).keepLeft)
        for challenge in Challenge.sandbox {
            XCTAssertFalse(GameWorld.newGame(challenge: challenge, eventSeed: 7).keepLeft, challenge.id)
        }
        XCTAssertFalse(LiuMingchuanChallenge.make().keepLeft)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.world.keepLeft, false)
    }
}
