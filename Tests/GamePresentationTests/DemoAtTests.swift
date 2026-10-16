import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The Debug app's `-demo-at HH:MM`: the demo map opened run on to that
/// time, so that a UI test which needs the morning's trains opens on them
/// instead of waiting for the clock.
@MainActor
final class DemoAtTests: XCTestCase {
    private func launcher() -> (GameLauncher, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (GameLauncher(library: SaveLibrary(directory: directory), language: .traditionalChinese), directory)
    }

    /// At 07:00, paused, every station of the demo has trains on its board:
    /// the station board's UI test may hold any of them.
    func testTheDemoAtSevenIsPausedWithTrainsOnEveryBoard() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = try XCTUnwrap(launcher.openDemo(at: "07:00", paused: true))
        await task.value
        let world = try XCTUnwrap(launcher.session?.world, "the launcher plays the demo")
        XCTAssertEqual(world.clock.speed, .paused)
        XCTAssertEqual(world.clock.now, GameTime(seconds: 7 * 3_600))
        XCTAssertFalse(world.stations.isEmpty)
        for station in world.stations {
            XCTAssertFalse(DepartureBoard(world: world, station: station.id).isEmpty, "\(station.name) lists no train at 07:00")
        }
        // The same world as the demo run on by hand.
        var byHand = DemoWorld.make(in: .traditionalChinese)
        byHand.setSpeed(.fast)
        try byHand.advance(ticks: 42)
        XCTAssertEqual(world.trains, byHand.trains)
    }

    /// Not paused, the demo goes on at the usual speed from that time.
    func testTheDemoAtATimeRunsOnWhenNotPaused() async throws {
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        await launcher.openDemo(at: "23:58", paused: false)?.value
        let world = try XCTUnwrap(launcher.session?.world)
        XCTAssertEqual(world.clock.speed, .normal)
        XCTAssertEqual(world.clock.now, GameTime(seconds: 23 * 3_600 + 58 * 60))
    }

    func testOnlyATimeOfDayIsATime() {
        XCTAssertEqual(GameLauncher.secondOfDay("00:00"), 0)
        XCTAssertEqual(GameLauncher.secondOfDay("06:30"), 23_400)
        XCTAssertEqual(GameLauncher.secondOfDay("23:59"), 86_340)
        for wrong in ["24:00", "7:00", "07:60", "0700", "07:00:00", "", "aa:bb", "-1:00"] {
            XCTAssertNil(GameLauncher.secondOfDay(wrong), wrong)
        }
        let (launcher, directory) = launcher()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertNil(launcher.openDemo(at: "noon", paused: true))
        XCTAssertNil(launcher.session)
    }
}
