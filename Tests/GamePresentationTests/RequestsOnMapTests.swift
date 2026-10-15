import Foundation
import GameCore
import GamePresentation
import XCTest

/// Decision 246: the city's requests on the map. Each request in hand has a
/// pin where it points; "Show on map" sends the camera there and points it
/// out, ringed and with its card; the status bar counts the requests in
/// hand.
@MainActor
final class RequestsOnMapTests: XCTestCase {
    /// CityRequestsSessionTests' world: Home with 1,500 trips a day, so the
    /// city asks for more riders there, and the biggest town for a station.
    private func world() throws -> GameWorld {
        var world = GameWorld.newGame(eventSeed: 7)
        world.setCityRequests(seed: nil)
        world.setTourism(nil)
        world.setLandDemand(false)
        let home = try world.buildStation(named: "Home", at: PlanPoint(x: 20_000, y: 500_000)).id
        let work = try world.buildStation(named: "Work", at: PlanPoint(x: 120_000, y: 500_000)).id
        let line = try world.createLine(named: "Main", stops: [home, work]).id
        let train = try world.purchaseTrain(named: "T").id
        try world.assignTrain(train, to: line)
        try world.setStationDemand(home, to: StationDemand(kind: .residential, dailyTrips: 1_500))
        try world.setStationDemand(work, to: StationDemand(kind: .office, dailyTrips: 100))
        world.setCityRequests(seed: 7)
        return world
    }

    func testARequestInHandHasAPinAndShowOnMapPointsItOut() throws {
        let session = GameSession(world: try world())
        XCTAssertEqual(session.cityRequestsInHand, 0)
        XCTAssertTrue(session.hasCityRequestOffers)
        XCTAssertEqual(session.cityRequestsButtonValue, "0 in hand, new offers")
        XCTAssertEqual(session.cityRequestMarks, [], "offers have no pins")

        let riders = try XCTUnwrap(session.world.cityRequests?.offers.first { $0.kind == .stationRiders })
        session.acceptRequest(riders.id)
        XCTAssertEqual(session.cityRequestsInHand, 1)
        XCTAssertFalse(session.hasCityRequestOffers, "one star of trust holds one")
        XCTAssertEqual(session.cityRequestsButtonValue, "1 in hand")
        let home = PlanPoint(x: 20_000, y: 500_000)
        XCTAssertEqual(session.cityRequestMarks, [CityRequestMark(id: riders.id, location: home, radius: nil, isFocused: false)])
        XCTAssertNil(session.focusedRequest)

        let before = session.cameraRequest?.serial ?? 0
        session.showRequestOnMap(riders.id)
        XCTAssertEqual(session.cameraRequest?.location, home, "the camera goes there")
        XCTAssertEqual(session.cameraRequest?.serial, before + 1)
        XCTAssertEqual(session.cityRequestMarks.map(\.isFocused), [true])
        let card = try XCTUnwrap(session.focusedRequest)
        XCTAssertEqual(card.title, "More riders at Home")
        XCTAssertEqual(card.progressText, "1500 / 2100 trips a day")
        XCTAssertEqual(card.daysLeftText, "60 days left")

        session.clearRequestFocus()
        XCTAssertNil(session.focusedRequest)
        XCTAssertEqual(session.cityRequestMarks.map(\.isFocused), [false])
    }

    /// An offer shown on the map is pointed out too, with the 800 m a new
    /// station must stand within; once gone, so are its pin and card.
    func testAnOfferForANewStationIsRingedWhileItIsOffered() throws {
        let session = GameSession(world: try world())
        let town = try XCTUnwrap(session.world.cityRequests?.offers.first { $0.kind == .newStation })
        let point = try XCTUnwrap(town.point)
        session.showRequestOnMap(town.id)
        XCTAssertEqual(session.cameraRequest?.location, point)
        XCTAssertEqual(session.cityRequestMarks, [CityRequestMark(id: town.id, location: point, radius: Land.catchmentRadius, isFocused: true)])
        XCTAssertNotNil(session.focusedRequest)

        session.declineRequest(town.id)
        XCTAssertEqual(session.cityRequestMarks, [])
        XCTAssertNil(session.focusedRequest)
    }

    func testARequestForTheWholeNetworkIsNotPointedOut() throws {
        var world = try world()
        let network = world.cityRequests?.offers.first { $0.kind == .networkRiders }
        let session = GameSession(world: world)
        if let network {
            session.showRequestOnMap(network.id)
            XCTAssertNil(session.focusedRequestID)
            XCTAssertNil(session.cameraRequest)
        }
        world.setCityRequests(seed: nil)
        let none = GameSession(world: world)
        XCTAssertNil(none.cityRequestsInHand, "no button in a game without them")
        none.showRequestOnMap(1)
        XCTAssertNil(none.focusedRequestID)
    }

    /// The UI test's game (`-demo-layout -city-requests`): the demo map
    /// with the requests drawn from seed 1 has an offer to show on the map.
    func testTheUITestsDemoHasAnOfferThatPointsSomewhere() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RequestsOnMapTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let launcher = GameLauncher(library: SaveLibrary(directory: directory), language: .english)
        launcher.openDemo(cityRequestSeed: 1)
        let session = try XCTUnwrap(launcher.session)
        let rows = session.world.cityRequestRows(in: .english)
        XCTAssertTrue(rows.contains { $0.location != nil }, rows.map(\.title).joined(separator: ", "))
    }
}
