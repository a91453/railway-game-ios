@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 400, 10i-6: a bus route's buses at a second of the day, from
/// its legs, service and buses alone.
///
/// The route: two stops, 900 m and then 900 m to the station (1,800 m,
/// 360 s each way at 18 km/h, a round trip of 22 minutes with the
/// layovers).
final class BusMotionTests: XCTestCase {
    private func route(_ service: BusService, buses: Int) -> BusRoute {
        BusRoute(id: BusRouteID(rawValue: 1), station: StationID(rawValue: 1),
                 stops: [CellPosition(row: 0, column: 0), CellPosition(row: 0, column: 14)], legMetres: [900, 900], service: service,
                 buses: buses)
    }

    func testNoBusNoMotion() {
        XCTAssertNil(BusMotion(route(.every(minutes: 10), buses: 0)))
    }

    func testTheSameSecondPutsTheBusesInTheSamePlaces() throws {
        let a = try XCTUnwrap(BusMotion(route(.every(minutes: 10), buses: 3)))
        let b = try XCTUnwrap(BusMotion(route(.every(minutes: 10), buses: 3)))
        for second in stride(from: 0.0, to: 86_400, by: 997) {
            XCTAssertEqual(a.buses(at: second), b.buses(at: second))
        }
        XCTAssertEqual(a.oneWay, 360)
        XCTAssertEqual(a.departures.count, 144)
    }

    func testNeverMoreBusesOutThanTheRouteHas() throws {
        for buses in 1...4 {
            let motion = try XCTUnwrap(BusMotion(route(.every(minutes: 5), buses: buses)))
            var most = 0
            for second in stride(from: 0.0, to: 86_400, by: 7) { most = max(most, motion.buses(at: second).count) }
            XCTAssertEqual(most, buses, "\(buses) buses keep a headway of \(route(.every(minutes: 5), buses: buses).headway ?? 0) minutes")
        }
    }

    func testABusGoesOutStopsOnTheWayWaitsAtTheStationAndComesBack() throws {
        let motion = try XCTUnwrap(BusMotion(route(.runs([480]), buses: 1)))
        let stops = [0.0, 900, 1_800]
        let leaves = 480.0 * 60
        // Waiting at the first stop before it leaves.
        let waiting = try XCTUnwrap(motion.buses(at: leaves - 60).first)
        XCTAssertTrue(waiting.stopped)
        XCTAssertTrue(waiting.outbound)
        XCTAssertEqual(waiting.distance(along: stops), 0)
        // Moving away from it, then standing at the middle stop.
        let moving = try XCTUnwrap(motion.buses(at: leaves + 60).first)
        XCTAssertFalse(moving.stopped)
        XCTAssertGreaterThan(moving.distance(along: stops), 0)
        XCTAssertEqual(motion.dwell, 20)
        let arrives = leaves + (360 - 20) / 2
        let atStop = try XCTUnwrap(motion.buses(at: arrives + 10).first)
        XCTAssertTrue(atStop.stopped)
        XCTAssertEqual(atStop.distance(along: stops), 900, accuracy: 0.001)
        XCTAssertFalse(try XCTUnwrap(motion.buses(at: arrives + 21).first).stopped, "a stand, then on")
        // At the station, then back the other way.
        let station = try XCTUnwrap(motion.buses(at: leaves + 360 + 100).first)
        XCTAssertTrue(station.stopped)
        XCTAssertEqual(station.distance(along: stops), 1_800, accuracy: 0.001)
        let back = try XCTUnwrap(motion.buses(at: leaves + 360 + 300 + 60).first)
        XCTAssertFalse(back.outbound)
        XCTAssertGreaterThan(back.distance(along: stops), 900)
        XCTAssertLessThan(back.distance(along: stops), 1_800)
        // Gone once back at the first stop.
        XCTAssertEqual(motion.buses(at: leaves + 2 * 360 + 300 - 1).first.map { $0.distance(along: stops) } ?? -1, 0, accuracy: 6)
        XCTAssertTrue(motion.buses(at: leaves + 2 * 360 + 300 + 1).isEmpty)
    }

    func testTheFirstAndLastRunsBoundTheDay() throws {
        let motion = try XCTUnwrap(BusMotion(route(.runs([360, 600, 840, 1_080, 1_320]), buses: 1)))
        XCTAssertTrue(motion.buses(at: 0).isEmpty, "before the first run")
        XCTAssertTrue(motion.buses(at: 360 * 60 - BusMotion.layover - 1).isEmpty)
        XCTAssertEqual(motion.buses(at: 360 * 60 - BusMotion.layover + 1).count, 1, "comes to its first stop before it leaves")
        XCTAssertEqual(motion.buses(at: 1_320 * 60 + 600).count, 1)
        XCTAssertTrue(motion.buses(at: 1_320 * 60 + motion.cycle).isEmpty, "after the last run is back")
        XCTAssertTrue(motion.buses(at: 86_399).isEmpty)
    }

    func testABusOverMidnightGoesOnIntoTheNextDay() throws {
        let motion = try XCTUnwrap(BusMotion(route(.runs([1_435]), buses: 1)))
        XCTAssertEqual(motion.buses(at: 30).count, 1, "left at 23:55, still on its way at 00:00:30")
        XCTAssertFalse(try XCTUnwrap(motion.buses(at: 30).first).stopped)
    }

    func testABusGrowsAndShrinksAtTheEndsOfItsTrip() throws {
        let motion = try XCTUnwrap(BusMotion(route(.runs([600]), buses: 1)))
        let comes = 600 * 60 - BusMotion.layover
        XCTAssertEqual(try XCTUnwrap(motion.buses(at: comes + 1).first).scale, 0.25, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(motion.buses(at: comes + 100).first).scale, 1)
        XCTAssertEqual(try XCTUnwrap(motion.buses(at: comes + motion.cycle - 2).first).scale, 0.5, accuracy: 0.001)
    }

    func testRunsTooCloseForTheBusesAreLeftOut() {
        // One bus takes 22 minutes round: of runs 10 minutes apart it keeps
        // every third.
        let route = route(.runs([600, 610, 620, 630, 640, 650, 660]), buses: 1)
        XCTAssertEqual(BusMotion.departures(of: route, headway: route.headway ?? 0), [600, 630, 660])
    }
}
