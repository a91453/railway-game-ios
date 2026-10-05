import Foundation
import GameCore
import GamePresentation
import XCTest

final class ScheduledTrafficTextTests: XCTestCase {
    func testScheduledWaitNamesItsStationAndPeerInBothLanguages() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (fixture, english, chinese) in [
            ("v9-scheduled-meet.json", "Waiting at M to meet T", "在 M 等候 T 交會"),
            ("v9-scheduled-clearance.json", "Standing aside at M for T", "在 M 待避 T"),
        ] {
            var world = try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: root.appendingPathComponent("SaveFixtures/\(fixture)"))).world
            let train = TrainID(rawValue: 1)
            XCTAssertEqual(world.routeWaitText(of: train, in: .english), english)
            XCTAssertEqual(world.routeWaitText(of: train, in: .traditionalChinese), chinese)
            XCTAssertNil(world.routeWaitText(of: TrainID(rawValue: 99), in: .english))
            try world.setTrafficControl(false)
            XCTAssertNil(world.routeWaitText(of: train, in: .english))
        }
    }
}
