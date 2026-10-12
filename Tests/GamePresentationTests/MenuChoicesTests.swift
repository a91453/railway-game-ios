import GameCore
@testable import GamePresentation
import XCTest

/// The native menus' entries (the train picker, the station menus of a
/// line, the transfer links) stay the same while the game runs, so a tick
/// does not rebuild a menu the player has open (TestFlight 54.1: the train
/// menu could not be scrolled and showed two layers of text).
final class MenuChoicesTests: XCTestCase {
    func testTicksThatMoveTrainsLeaveTheMenusEntriesAlone() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            session.setSpeed(.normal)
            guard let station = session.world.stations.first?.id else { return XCTFail("the demo has stations") }
            let trains = session.trainMenuChoices
            let stations = session.stationMenuChoices
            let transfers = session.transferMenuChoices(for: station)
            XCTAssertFalse(trains.isEmpty)
            XCTAssertFalse(stations.isEmpty)
            XCTAssertFalse(transfers.isEmpty)
            let before = session.world

            for _ in 0..<20 {
                session.advance(realElapsed: GameSession.tickInterval)
            }

            XCTAssertNotEqual(session.world, before, "the ticks changed the world")
            XCTAssertNotEqual(session.world.trains, before.trains, "the trains moved")
            XCTAssertEqual(session.trainMenuChoices, trains)
            XCTAssertEqual(session.stationMenuChoices, stations)
            XCTAssertEqual(session.transferMenuChoices(for: station), transfers)
        }
    }

    func testTheEntriesFollowTheWorld() async throws {
        let world = DemoWorld.make(in: .english)
        await MainActor.run {
            let session = GameSession(world: world)
            XCTAssertEqual(session.trainMenuChoices.map(\.id), session.world.trains.map(\.id))
            XCTAssertEqual(session.trainMenuChoices.map(\.title), session.world.trains.map(\.name))
            XCTAssertEqual(session.stationMenuChoices.map(\.title), session.world.stations.map(\.name))
            let trains = session.trainMenuChoices
            session.purchaseTrain()
            XCTAssertEqual(session.trainMenuChoices.count, trains.count + 1, "a bought train joins the menu")
            XCTAssertNotEqual(session.trainMenuChoices, trains)
        }
    }
}
