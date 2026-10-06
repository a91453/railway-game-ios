import GameCore
import GamePresentation
import XCTest

/// Phase 5F in the app: a new game routes passengers across the network,
/// and the session switches routing through one `GameWorld` command.
final class PassengerRoutingSessionTests: XCTestCase {
    func testANewGameRoutesPassengersAcrossTheNetwork() {
        XCTAssertEqual(GameWorld.newGame().passengerRoutingMode, .network)
        XCTAssertEqual(GameWorld.newGame(anchor: GeoAnchor(latitude: 250_805_000, longitude: 1_217_756_000)).passengerRoutingMode, .network)
    }

    func testTheSessionSwitchesRoutingThroughGameCore() async throws {
        let world = GameWorld.newGame()
        var direct = world
        direct.setPassengerRoutingMode(.direct)
        await MainActor.run { [direct] in
            let session = GameSession(world: world)
            session.setPassengerRoutingMode(.direct)
            XCTAssertEqual(session.world, direct)
            XCTAssertEqual(session.world.passengerRoutingMode, .direct)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Passengers now take only a line that serves both their stations."))
            session.setPassengerRoutingMode(.network)
            XCTAssertEqual(session.world.passengerRoutingMode, .network)
            XCTAssertEqual(session.message, StatusMessage(kind: .success, text: "Passengers now plan journeys across the network and change trains."))
            let before = session.message
            session.setPassengerRoutingMode(.network)
            XCTAssertEqual(session.message, before, "choosing the mode it has does nothing")
        }
    }
}
