import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 771 (AIR-A4): the company's air routes on the 3D map: their
/// aircraft land and leave at their own minutes, in place of the airport's
/// own flights; the camera follows one up to its cruise's start, the flight
/// window goes on from there, and a domestic one's landing is followed.
@MainActor
final class AirRouteFlightsTests: XCTestCase {
    /// A field with a taxiway from the runway to its stands, as
    /// `FollowAircraftTests` lays one.
    private func field(airports: [Int] = [0]) -> Map3DAircraft.Laid.Field {
        var field = Map3DAircraft.Laid.Field(
            seed: 7, airports: airports,
            stands: (0..<40).map { .init(nose: Map3DPoint(400 + Float($0) * 60, 0, 300), forward: Map3DPoint(0, 0, 1), room: 57) },
            runways: [.init(a: Map3DPoint(0, 0, 0), b: Map3DPoint(3_000, 0, 0), length: 3_000)], wide: 0.3, propeller: 0.2
        )
        field.layTaxiways([[Map3DPoint(1_800, 0, 0), Map3DPoint(1_800, 0, 200), Map3DPoint(600, 0, 200), Map3DPoint(100, 0, 200), Map3DPoint(100, 0, 0)],
                           [Map3DPoint(1_800, 0, 200), Map3DPoint(2_900, 0, 200)]])
        return field
    }

    /// A route from airport 0 to a place abroad due south of it (world
    /// units: the scene's z is the world's y), leaving at 10:00, two hours
    /// stand to stand.
    private func route(grounded: Bool = false, far: Int? = nil) -> Map3DAircraft.Route {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        return Map3DAircraft.Route(id: AirRouteID(rawValue: 1), airport: 0, far: far, kind: .narrowJet, minutes: [600], flightMinutes: 120,
                                   grounded: grounded, farX: 1_500 * metre, farY: 300_000 * metre, homeX: 1_500 * metre, homeY: 0)
    }

    private func traffic(_ routes: [Map3DAircraft.Route], each: Int = 3) -> Map3DAircraft.Traffic {
        Map3DAircraft.Traffic(day: 0, landings: [Array(repeating: each, count: 24)], takeOffs: [Array(repeating: each, count: 24)], routes: routes)
    }

    func testARoutesFlightsTakeTheirMinutesInPlaceOfTheAirportsOwn() throws {
        let field = field()
        let plain = Map3DAircraft.Laid.flights(of: field, day: 0, hour: 10, traffic: traffic([]))
        let flown = Map3DAircraft.Laid.flights(of: field, day: 0, hour: 10, traffic: traffic([route()]))
        XCTAssertEqual(flown.count, plain.count)
        // Its take-off: rolling ten minutes after it leaves its stand at
        // 10:00, a narrow-body jet in the company's livery, at a stand.
        let leaving = try XCTUnwrap(flown.first { $0.id.leg != nil })
        XCTAssertFalse(leaving.landing)
        // (Put back by 80 s at a time while a landing is on its runway.)
        XCTAssertEqual(leaving.time, Double((600 + Map3DAircraft.taxiMinutes) * 60), accuracy: 400)
        XCTAssertEqual(leaving.kind, .narrowJet)
        XCTAssertEqual(leaving.livery, Map3DAircraft.companyLivery)
        XCTAssertNotNil(leaving.stand)
        XCTAssertEqual(leaving.id, Map3DAircraft.FlightID(leg: .init(route: AirRouteID(rawValue: 1), departure: 600, outbound: true, airport: 0),
                                                          landing: false))
        XCTAssertEqual(flown.filter { !$0.landing && $0.id.leg == nil }.count, 2, "one of the airport's own take-offs fewer")
        XCTAssertEqual(flown.filter(\.landing).count, 3)
        // Its aircraft back from abroad touches down at 11:50.
        let back = Map3DAircraft.Laid.flights(of: field, day: 0, hour: 11, traffic: traffic([route()]))
        let landing = try XCTUnwrap(back.first { $0.id.leg != nil })
        XCTAssertTrue(landing.landing)
        XCTAssertEqual(landing.time, Double((600 + 120 - Map3DAircraft.taxiMinutes) * 60))
        XCTAssertEqual(landing.id.leg?.outbound, false)
        // The day before's flights come again the next day; a typhoon keeps
        // them on the ground.
        XCTAssertNotNil(Map3DAircraft.Laid.flights(of: field, day: 1, hour: 10, traffic: traffic([route()])).first { $0.id.leg?.departure == 1_440 + 600 })
        let grounded = Map3DAircraft.Laid.flights(of: field, day: 0, hour: 10, traffic: traffic([route(grounded: true)]))
        XCTAssertEqual(grounded.map(\.time), plain.map(\.time))
    }

    /// A domestic route: both ends of the map fly it, each way.
    func testADomesticRouteFliesAtBothEnds() {
        let far = field(airports: [1])
        let flights = Map3DAircraft.Laid.flights(of: far, day: 0, hour: 10, traffic: Map3DAircraft.Traffic(
            day: 0, landings: [[], Array(repeating: 2, count: 24)], takeOffs: [[], Array(repeating: 2, count: 24)], routes: [route(far: 1)]))
        let legs = flights.compactMap(\.id.leg)
        XCTAssertEqual(legs.count, 1)
        XCTAssertEqual(legs.first?.outbound, false, "its aircraft leaves the far end for home at 10:00")
        let later = Map3DAircraft.Laid.flights(of: far, day: 0, hour: 11, traffic: Map3DAircraft.Traffic(
            day: 0, landings: [[], Array(repeating: 2, count: 24)], takeOffs: [[], Array(repeating: 2, count: 24)], routes: [route(far: 1)]))
        XCTAssertEqual(later.filter { $0.id.leg?.outbound == true }.map(\.landing), [true], "and lands there from home at 11:50")
    }

    /// The camera follows a route's take-off up to 3,000 m, turning on the
    /// way towards where it flies (south here); an airport's own flight is
    /// let go at 3.6 km out, as before.
    func testARoutesAircraftIsFollowedToItsCruiseTurningTowardsItsDestination() throws {
        let laid = Map3DAircraft.Laid(fields: [field()]), traffic = traffic([route()])
        let id = Map3DAircraft.FlightID(leg: .init(route: AirRouteID(rawValue: 1), departure: 600, outbound: true, airport: 0), landing: false)
        var highest: Float = 0, last: Map3DAircraft.Drawn?
        var phases: [Map3DAircraft.Phase] = []
        for second in stride(from: 600.0 * 60, through: 600.0 * 60 + 3_000, by: 2) {
            guard let drawn = laid.aircraft(of: id, second: second, traffic: traffic) else { continue }
            if let phase = drawn.phase, phases.last != phase { phases.append(phase) }
            XCTAssertEqual(laid.followed(id, second: second, traffic: traffic) != nil, Map3DAircraft.canFollow(drawn))
            if drawn.phase == .climb {
                XCTAssertTrue(Map3DAircraft.canFollow(drawn))
                highest = max(highest, drawn.height)
                last = drawn
            }
        }
        XCTAssertEqual(phases.suffix(3), [.lineUp, .takeOffRoll, .climb])
        XCTAssertGreaterThan(highest, 2_900)
        XCTAssertLessThan(Double(highest), Map3DAircraft.cruiseHeight)
        let heading = try XCTUnwrap(last?.forward)
        XCTAssertGreaterThan(heading.z, 0.99, "south, the way it flies")
        // A climb of an airport's own flight of that height is not followed.
        var plain = try XCTUnwrap(last)
        plain.flight = .init(field: 7, hours: 10, landing: false, index: 0)
        XCTAssertFalse(Map3DAircraft.canFollow(plain))
        XCTAssertEqual(laid.airport(of: id), 0)
    }

    func testTheClimbTurnsAndGoesStraightOn() {
        let liftOff = Map3DPoint(0, 0, 0), east = Map3DPoint(1, 0, 0), north = Map3DPoint(0, 0, -1)
        let early = Map3DAircraft.Laid.climbed(1_000, from: liftOff, forward: east, toward: north)
        XCTAssertEqual(early.ground.x, 1_000, accuracy: 0.01)
        XCTAssertEqual(early.forward.x, 1, accuracy: 0.001)
        // A quarter turn of radius 2,500 m to the left (north, −z).
        let arc = Map3DAircraft.turnRadius * .pi / 2
        let turned = Map3DAircraft.Laid.climbed(Map3DAircraft.straightOut + arc + 500, from: liftOff, forward: east, toward: north)
        XCTAssertEqual(turned.forward.z, -1, accuracy: 0.001)
        XCTAssertEqual(Double(turned.ground.x), Map3DAircraft.straightOut + Map3DAircraft.turnRadius, accuracy: 0.5)
        XCTAssertEqual(Double(turned.ground.z), -(Map3DAircraft.turnRadius + 500), accuracy: 0.5)
        // Nowhere to turn to: straight on.
        XCTAssertEqual(Map3DAircraft.Laid.climbed(9_000, from: liftOff, forward: east, toward: nil).ground.x, 9_000, accuracy: 0.01)
    }

    // MARK: - The session

    private func taiwan() -> GameWorld {
        var world = GameWorld.newGame(anchor: WholeTaiwan.anchor, bounds: WholeTaiwan.bounds, balance: Money(10_000_000_000_000), land: [], rules: .simple)
        world.setEconomyMode(.management)
        return world
    }

    func testTheFlightWindowTakesOverAtTheCruiseAndTheLandingIsFollowed() throws {
        let session = GameSession(world: taiwan(), language: .traditionalChinese)
        let penghu = try XCTUnwrap(session.airRouteListings.first { $0.airportName == "臺北松山機場" && $0.destination.name == "澎湖" })
        XCTAssertTrue(session.buyAirRoute(penghu, size: .narrowBody, frequency: .real))
        let route = try XCTUnwrap(session.world.airRoutes.first)
        let songshan = try XCTUnwrap(session.world.airports.firstIndex { $0.id == route.airport })
        let magong = try XCTUnwrap(session.world.airports.firstIndex { $0.id == route.farAirport })
        // The 3D map counts its flights at both ends.
        let traffic = Map3DAircraft.Traffic(world: session.world)
        XCTAssertEqual(traffic.routes.map(\.airport), [songshan])
        XCTAssertEqual(traffic.routes.first?.far, magong)
        XCTAssertEqual(traffic.routes.first?.minutes, session.world.airRouteDepartureMinutes(route.id))
        XCTAssertEqual(traffic.routes.first?.kind, .narrowJet)

        session.setMap3DOpen(true)
        let departure = session.world.clock.now.seconds / 60 + 30
        let leg = Map3DAircraft.Leg(route: route.id, departure: departure, outbound: true, airport: songshan)
        let id = Map3DAircraft.FlightID(leg: leg, landing: false)
        session.followAircraft(.init(flight: id, kind: .narrowJet, phase: .climb, airport: songshan))
        let bar = try XCTUnwrap(session.aircraftFollowBar)
        XCTAssertEqual(bar.name, "臺北松山機場 → 澎湖機場")
        XCTAssertEqual(bar.directionText, "公司航線 · 窄體噴射客機")
        // Climbed to its cruise: the window opens.
        session.noteFollowedAircraft(nil, of: id)
        XCTAssertNil(session.followedAircraftID)
        let window = try XCTUnwrap(session.airFlightWindow)
        XCTAssertEqual(window.title, "臺北松山機場 → 澎湖")
        XCTAssertEqual(window.toText, "澎湖機場")
        XCTAssertTrue(window.landsOnMap)
        XCTAssertEqual(window.noteText, "降落時鏡頭會接著跟。")
        let lands = clockText(minuteOfDay: Int(departure + route.flightMinutes))
        XCTAssertEqual(window.arrivalText, "預計 \(lands) 到達")
        // Its button closes it; the 3D map closing does too.
        session.closeAirFlightWindow()
        XCTAssertNil(session.airFlightWindow)

        // Close to touchdown at Magong (a flight that left a minute short
        // of its time in the air ago) the camera follows the landing.
        let now = session.world.clock.now.seconds / 60
        let late = now - route.flightMinutes + Map3DAircraft.taxiMinutes + 1
        let lateID = Map3DAircraft.FlightID(leg: .init(route: route.id, departure: late, outbound: true, airport: songshan), landing: false)
        session.followAircraft(.init(flight: lateID, kind: .narrowJet, phase: .climb, airport: songshan))
        session.noteFollowedAircraft(nil, of: lateID)
        XCTAssertNotNil(session.airFlightWindow)
        session.keepAirFlightWindow()
        XCTAssertNil(session.airFlightWindow)
        XCTAssertEqual(session.followedAircraftID, Map3DAircraft.FlightID(leg: .init(route: route.id, departure: late, outbound: true, airport: magong),
                                                                         landing: true))
        XCTAssertEqual(session.aircraftFollowBar?.stopText, "進場中")
        session.setMap3DOpen(false)
        XCTAssertNil(session.airFlightWindow)
    }

    /// Abroad: it says it has arrived and stays until closed.
    func testAFlightAbroadArrivesInItsWindow() throws {
        let session = GameSession(world: taiwan(), language: .traditionalChinese)
        let hongKong = try XCTUnwrap(session.airRouteListings.first { $0.airportName == "高雄國際機場" && $0.destination.name == "香港" })
        XCTAssertTrue(session.buyAirRoute(hongKong, size: .wideBody, frequency: .real))
        let route = try XCTUnwrap(session.world.airRoutes.first)
        let kaohsiung = try XCTUnwrap(session.world.airports.firstIndex { $0.id == route.airport })
        let now = session.world.clock.now.seconds / 60
        let leg = Map3DAircraft.Leg(route: route.id, departure: now + 60, outbound: true, airport: kaohsiung)
        session.setMap3DOpen(true)
        session.followAircraft(.init(flight: .init(leg: leg, landing: false), kind: .wideJet, phase: .climb, airport: kaohsiung))
        session.noteFollowedAircraft(nil, of: .init(leg: leg, landing: false))
        var window = try XCTUnwrap(session.airFlightWindow)
        XCTAssertFalse(window.landsOnMap)
        XCTAssertNil(window.noteText)
        XCTAssertNil(AirFlightWindow.landing(of: leg, in: session.world))
        XCTAssertFalse(window.arrived)
        // One that left its flight's time ago has arrived.
        let arrived = Map3DAircraft.Leg(route: route.id, departure: now - route.flightMinutes - 1, outbound: true, airport: kaohsiung)
        session.followAircraft(.init(flight: .init(leg: arrived, landing: false), kind: .wideJet, phase: .climb, airport: kaohsiung))
        session.noteFollowedAircraft(nil, of: .init(leg: arrived, landing: false))
        session.keepAirFlightWindow()
        window = try XCTUnwrap(session.airFlightWindow)
        XCTAssertTrue(window.arrived)
        XCTAssertEqual(window.remainingText, "已抵達香港")
        XCTAssertEqual(window.noteText, "香港是另一張地圖，從選地圖進入。")
        XCTAssertEqual(window.progress, 1)
        XCTAssertNil(session.followedAircraftID)
    }

    /// The screenshot scene: the route bought, its first jet after 09:30
    /// lined up 20 seconds before its roll; the same moment without it.
    func testTheScreenshotScenesRoute() throws {
        let world = ScreenshotScene.airRouteSongshan.make(in: .traditionalChinese)
        let route = try XCTUnwrap(world.airRoutes.first)
        XCTAssertNil(route.farAirport, "Penghu is off the map round Songshan")
        let rolls = world.airRouteDepartureMinutes(route.id).map { ($0 + Map3DAircraft.taxiMinutes) * 60 }
        let second = world.clock.now.seconds % GameTime.secondsPerDay
        XCTAssertTrue(rolls.contains(second + 20), "\(second)")
        let none = ScreenshotScene.airRouteSongshanNone.make(in: .traditionalChinese)
        XCTAssertTrue(none.airRoutes.isEmpty)
        XCTAssertEqual(none.clock.now, world.clock.now)
    }

    /// An airport's own flight climbing away is let go, no window.
    func testAnAirportsOwnFlightOpensNoWindow() {
        let session = GameSession(world: taiwan(), language: .english)
        let id = Map3DAircraft.FlightID(field: 7, hours: 9, landing: false, index: 0)
        session.setMap3DOpen(true)
        session.followAircraft(.init(flight: id, kind: .narrowJet, phase: .climb, airport: 0))
        session.noteFollowedAircraft(nil, of: id)
        XCTAssertNil(session.airFlightWindow)
        XCTAssertNil(session.followedAircraftID)
    }
}
