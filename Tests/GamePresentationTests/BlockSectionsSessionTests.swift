import Foundation
import GameCore
import GamePresentation
import XCTest

/// Block sections where the app meets them (ARCHITECTURE decision 212): a
/// new game cuts long legs into blocks under traffic control, and the
/// worlds measured without them (the demos, the challenges, the tutorial)
/// keep them off, as an old save does.
@MainActor
final class BlockSectionsSessionTests: XCTestCase {
    private static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("BlockSectionsSessionTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testANewGameCutsLongLegsIntoBlocks() {
        XCTAssertTrue(GameWorld.newGame().blockSections)
        XCTAssertTrue(GameWorld.newGame(eventSeed: 7).blockSections)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startNewGame()
        XCTAssertEqual(launcher.session?.world.blockSections, true)
    }

    func testTheMeasuredWorldsKeepThemOff() {
        XCTAssertFalse(DemoWorld.make(in: .english).blockSections)
        for challenge in Challenge.sandbox {
            XCTAssertFalse(GameWorld.newGame(challenge: challenge, eventSeed: 7).blockSections, challenge.id)
        }
        XCTAssertFalse(LiuMingchuanChallenge.make().blockSections)
        let directory = Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.startTutorial()
        XCTAssertEqual(launcher.session?.world.blockSections, false)
    }
}
